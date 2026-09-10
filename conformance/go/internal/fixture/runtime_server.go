package fixture

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/mattsp1290/eino-agent/composition"
	"github.com/mattsp1290/eino-agent/config"
	"github.com/mattsp1290/eino-agent/model"
	"github.com/mattsp1290/eino-agent/runtime"
	"github.com/mattsp1290/eino-agent/session"
	"github.com/mattsp1290/eino-agent/store/sqlite"
	"github.com/mattsp1290/eino-agent/transport"
	"github.com/mattsp1290/eino-agent/watch"
)

// RuntimeServer is the retained cross-language fixture host. Its Eino routes
// use the public runtime, SQLite store, watch service, and transport handlers.
// The separate generic route remains caller-history based.
type RuntimeServer struct {
	store    *sqlite.Store
	observer *watch.Service
	mount    *composition.Mount
	runtime  *runtime.StreamingOrchestrator
	config   config.Snapshot
	generic  *Server

	mu      sync.Mutex
	handles map[session.RunID]runtimeHandle
}

type runtimeHandle struct {
	handle runtime.Handle
	done   chan struct{}
}

func NewRuntimeServer(ctx context.Context, dbPath string) (*RuntimeServer, error) {
	if dbPath == "" {
		return nil, fmt.Errorf("database path required")
	}
	store, err := sqlite.Open(ctx, dbPath)
	if err != nil {
		return nil, err
	}
	observer, err := watch.NewService(store, watch.Options{
		Snapshot: session.ObservationLimits{
			MaxMessages:      50,
			MaxTools:         100,
			MaxParts:         200,
			MaxSnapshotBytes: 1 << 20,
			MaxTextBytes:     128 << 10,
		},
		PollInterval:       20 * time.Millisecond,
		ReadTimeout:        time.Second,
		MaxSubscriptions:   64,
		MaxWatchedSessions: 32,
		MaxLiveRuns:        32,
		MaxLiveTextBytes:   1 << 20,
		PendingUpdates:     64,
	})
	if err != nil {
		_ = store.Close()
		return nil, err
	}
	registry, err := composition.NewRegistry(nil)
	if err != nil {
		_ = observer.Close(ctx)
		_ = store.Close()
		return nil, err
	}
	mount, err := mountFixtureTool(ctx, registry)
	if err != nil {
		_ = observer.Close(ctx)
		_ = store.Close()
		return nil, err
	}
	ids := &fixtureIDs{}
	orchestrator, err := runtime.NewStreamingOrchestrator(
		runtime.WithStore(store),
		runtime.WithModelResolver(fixtureResolver{}),
		runtime.WithSessionObserver(observer),
		runtime.WithIDGenerator(ids),
		runtime.WithRunPlanProvider(registry),
		runtime.WithOwnerID("flutter-conformance"),
		runtime.WithQueueSize(16),
	)
	if err != nil {
		mount.Deactivate()
		_ = mount.Close(ctx)
		_ = observer.Close(ctx)
		_ = store.Close()
		return nil, err
	}
	return &RuntimeServer{
		store:    store,
		observer: observer,
		mount:    mount,
		runtime:  orchestrator,
		config:   fixtureConfig(),
		generic:  NewServer(),
		handles:  make(map[session.RunID]runtimeHandle),
	}, nil
}

func (s *RuntimeServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	addDevelopmentCORS(w, r)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	switch {
	case r.URL.Path == "/healthz" || r.URL.Path == "/generic/run":
		s.generic.ServeHTTP(w, r)
	case strings.HasPrefix(r.URL.Path, "/sessions/"):
		s.serveSession(w, r)
	case strings.HasPrefix(r.URL.Path, "/runs/"):
		s.serveControl(w, r)
	default:
		http.NotFound(w, r)
	}
}

func (s *RuntimeServer) serveSession(w http.ResponseWriter, r *http.Request) {
	sessionID, action, ok := sessionRoute(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	if r.Header.Get("X-Fixture-Session") != string(sessionID) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	switch action {
	case "events":
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		transport.SessionWatchHandler(transport.SessionWatchConfig{
			Service:      s.observer,
			WriteTimeout: time.Second,
			Auth: func(ctx context.Context, _ *http.Request) (context.Context, error) {
				return ctx, nil
			},
			Session: func(*http.Request) (session.ID, error) { return sessionID, nil },
		}).ServeHTTP(w, r)
	case "runs":
		s.startRun(w, r, sessionID)
	default:
		http.NotFound(w, r)
	}
}

func (s *RuntimeServer) startRun(w http.ResponseWriter, r *http.Request, sessionID session.ID) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	message, err := decodeRuntimeMessage(w, r)
	if err != nil {
		http.Error(w, "invalid message", http.StatusBadRequest)
		return
	}
	handle, err := s.runtime.Start(context.WithoutCancel(r.Context()), runtime.Request{
		SessionID: sessionID,
		Message:   message,
		Config:    s.config,
		Metadata:  map[string]string{"fixture": "flutter-conformance"},
	})
	if err != nil {
		status := http.StatusBadGateway
		if errors.Is(err, session.ErrSessionBusy) {
			status = http.StatusConflict
		}
		http.Error(w, "run unavailable", status)
		return
	}
	s.remember(handle)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"session_id": string(sessionID),
		"run_id":     string(handle.RunID()),
		"events":     "/sessions/" + string(sessionID) + "/events",
	})
}

func (s *RuntimeServer) serveControl(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/runs/"), "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] != "interrupt" {
		http.NotFound(w, r)
		return
	}
	runID := session.RunID(parts[0])
	transport.InterruptHandler(nil, func(context.Context, *http.Request) (transport.Interruptor, error) {
		return s.lookup(runID)
	}).ServeHTTP(w, r)
}

func (s *RuntimeServer) remember(handle runtime.Handle) {
	active := runtimeHandle{handle: handle, done: make(chan struct{})}
	s.mu.Lock()
	s.handles[handle.RunID()] = active
	s.mu.Unlock()
	go func() {
		<-handle.Done()
		s.mu.Lock()
		delete(s.handles, handle.RunID())
		s.mu.Unlock()
		close(active.done)
	}()
}

func (s *RuntimeServer) lookup(id session.RunID) (runtime.Handle, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	active, ok := s.handles[id]
	if !ok {
		return nil, fmt.Errorf("run unavailable")
	}
	return active.handle, nil
}

func (s *RuntimeServer) Close() error {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	handles := make([]runtimeHandle, 0, len(s.handles))
	for _, handle := range s.handles {
		handles = append(handles, handle)
	}
	s.mu.Unlock()
	for _, handle := range handles {
		_ = handle.handle.Interrupt(context.Background(), "fixture closing")
	}
	for _, handle := range handles {
		select {
		case <-handle.done:
		case <-time.After(2 * time.Second):
			return fmt.Errorf("run cleanup timeout")
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	s.mount.Deactivate()
	if err := s.mount.Close(ctx); err != nil {
		return err
	}
	if err := s.observer.Close(ctx); err != nil {
		return err
	}
	return s.store.Close()
}

func decodeRuntimeMessage(w http.ResponseWriter, r *http.Request) (runtime.UserMessage, error) {
	var payload struct {
		Message string `json:"message"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		return runtime.UserMessage{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return runtime.UserMessage{}, fmt.Errorf("one object required")
	}
	if strings.TrimSpace(payload.Message) == "" {
		return runtime.UserMessage{}, fmt.Errorf("message required")
	}
	return runtime.UserMessage{Content: payload.Message}, nil
}

func fixtureConfig() config.Snapshot {
	selection := model.Selection{ProviderID: "fixture", ModelID: "scripted"}
	workingDirectory, _ := os.Getwd()
	return config.Snapshot{
		Agent: config.Agent{
			Name:         "flutter-conformance",
			SystemPrompt: "Use only deterministic synthetic fixture data.",
			Model:        selection,
			Options:      map[string]string{"stream_delay_ms": "10"},
		},
		Model: selection,
		Metadata: map[string]string{
			"workspace_id":   "flutter-conformance",
			"workspace_root": workingDirectory,
		},
	}
}

type fixtureIDs struct {
	mu sync.Mutex
	n  int
}

func (s *fixtureIDs) next(kind string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.n++
	return "fixture-" + kind + "-" + strconv.Itoa(s.n)
}

func (s *fixtureIDs) NewRunID() session.RunID           { return session.RunID(s.next("run")) }
func (s *fixtureIDs) NewMessageID() session.MessageID   { return session.MessageID(s.next("message")) }
func (s *fixtureIDs) NewPartID() session.PartID         { return session.PartID(s.next("part")) }
func (s *fixtureIDs) NewToolCallID() session.ToolCallID { return session.ToolCallID(s.next("tool")) }
func (s *fixtureIDs) NewEventID() session.EventID       { return session.EventID(s.next("event")) }
func (s *fixtureIDs) NewEpochID() session.EpochID       { return session.EpochID(s.next("epoch")) }
