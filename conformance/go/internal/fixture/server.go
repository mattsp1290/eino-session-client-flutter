package fixture

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"

	"github.com/mattsp1290/eino-agent/session"
)

type Server struct {
	mu           sync.Mutex
	sessions     map[session.ID]*serverSession
	genericTurns map[string]int
}

type serverSession struct {
	revision int64
	runCount int
	messages []session.ObservationMessage
	runs     []session.ObservationRun
	watchers map[chan struct{}]struct{}
}

func NewServer() *Server {
	return &Server{
		sessions:     make(map[session.ID]*serverSession),
		genericTurns: make(map[string]int),
	}
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	addDevelopmentCORS(w, r)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	s.serveWithoutCORS(w, r)
}

func addDevelopmentCORS(w http.ResponseWriter, r *http.Request) {
	origin := r.Header.Get("Origin")
	if strings.HasPrefix(origin, "http://127.0.0.1:") || strings.HasPrefix(origin, "http://localhost:") {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Headers", "content-type, accept, x-fixture-session")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	}
}

func (s *Server) serveWithoutCORS(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/healthz":
		w.WriteHeader(http.StatusNoContent)
	case r.URL.Path == "/generic/run":
		s.serveGeneric(w, r)
	case strings.HasPrefix(r.URL.Path, "/sessions/"):
		s.serveSession(w, r)
	case strings.HasPrefix(r.URL.Path, "/runs/"):
		s.serveInterrupt(w, r)
	default:
		http.NotFound(w, r)
	}
}

func (s *Server) serveGeneric(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 2<<20))
	if err != nil {
		http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
		return
	}
	var input struct {
		ThreadID string                   `json:"threadId"`
		Messages []map[string]interface{} `json:"messages"`
	}
	if json.Unmarshal(body, &input) != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	data, err := s.genericResponse(input.ThreadID, input.Messages)
	if err != nil {
		http.Error(w, "invalid caller history", http.StatusUnprocessableEntity)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	_, _ = w.Write(data)
}

func (s *Server) genericResponse(threadID string, messages []map[string]interface{}) ([]byte, error) {
	if threadID != "browser-thread" {
		return Generic()
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	turn := s.genericTurns[threadID] + 1
	if err := validateGenericHistory(turn, messages); err != nil {
		return nil, err
	}
	s.genericTurns[threadID] = turn
	return GenericTurn(turn)
}

func validateGenericHistory(turn int, messages []map[string]interface{}) error {
	expected := []map[string]interface{}{
		{"id": "user-1", "role": "user", "content": "first turn"},
	}
	if turn == 2 {
		expected = append(expected,
			map[string]interface{}{
				"id": "assistant-1", "role": "assistant", "content": "Response 1",
				"toolCalls": []interface{}{map[string]interface{}{
					"id": "tool-1", "type": "function",
					"function": map[string]interface{}{"name": "lookup", "arguments": `{"turn":1}`},
				}},
			},
			map[string]interface{}{"id": "tool-result-1", "role": "tool", "content": "result 1", "toolCallId": "tool-1"},
			map[string]interface{}{"id": "user-2", "role": "user", "content": "second turn"},
		)
	}
	if turn < 1 || turn > 2 || !jsonEqual(messages, expected) {
		return fmt.Errorf("generic history mismatch")
	}
	return nil
}

func jsonEqual(left, right interface{}) bool {
	leftJSON, leftErr := json.Marshal(left)
	rightJSON, rightErr := json.Marshal(right)
	return leftErr == nil && rightErr == nil && string(leftJSON) == string(rightJSON)
}

func (s *Server) serveSession(w http.ResponseWriter, r *http.Request) {
	id, action, ok := sessionRoute(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	switch action {
	case "events":
		s.watch(w, r, id)
	case "runs":
		s.admit(w, r, id)
	default:
		http.NotFound(w, r)
	}
}

func (s *Server) watch(w http.ResponseWriter, r *http.Request, id session.ID) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	updates := make(chan struct{}, 1)
	s.mu.Lock()
	state := s.sessionLocked(id)
	state.watchers[updates] = struct{}{}
	snapshot := s.snapshotLocked(id, state)
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(state.watchers, updates)
		s.mu.Unlock()
	}()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	flusher, _ := w.(http.Flusher)
	for {
		data, err := EncodeWatch(snapshot)
		if err != nil {
			return
		}
		if _, err := w.Write(data); err != nil {
			return
		}
		if flusher != nil {
			flusher.Flush()
		}
		select {
		case <-r.Context().Done():
			return
		case <-updates:
			s.mu.Lock()
			snapshot = s.snapshotLocked(id, state)
			s.mu.Unlock()
		}
	}
}

func (s *Server) admit(w http.ResponseWriter, r *http.Request, id session.ID) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var input struct {
		Message string `json:"message"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&input) != nil || strings.TrimSpace(input.Message) == "" {
		http.Error(w, "invalid message", http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	state := s.sessionLocked(id)
	state.runCount++
	runID := session.RunID(fmt.Sprintf("run-%d", state.runCount))
	userID := session.MessageID(fmt.Sprintf("user-%d", state.runCount))
	assistantID := session.MessageID(fmt.Sprintf("assistant-%d", state.runCount))
	state.messages = append(state.messages,
		session.ObservationMessage{ID: userID, RunID: runID, Role: session.RoleUser, Text: input.Message, Finalized: true},
		session.ObservationMessage{ID: assistantID, RunID: runID, Role: session.RoleAssistant, Text: "Scripted response", Finalized: true},
	)
	state.runs = append(state.runs, session.ObservationRun{ID: runID, Status: session.RunCompleted, ProviderID: "fixture", ModelID: "scripted"})
	state.revision++
	s.notifyLocked(state)
	s.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{"session_id": string(id), "run_id": string(runID), "events": "/sessions/" + string(id) + "/events"})
}

func (s *Server) serveInterrupt(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || !strings.HasSuffix(r.URL.Path, "/interrupt") {
		http.NotFound(w, r)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func (s *Server) sessionLocked(id session.ID) *serverSession {
	state := s.sessions[id]
	if state == nil {
		state = &serverSession{revision: 1, watchers: make(map[chan struct{}]struct{})}
		s.sessions[id] = state
	}
	return state
}

func (s *Server) snapshotLocked(id session.ID, state *serverSession) session.ObservationSnapshot {
	return session.ObservationSnapshot{
		Watermark: session.ObservationWatermark{StoreID: "fixture-server", SessionID: id, Revision: state.revision},
		Exists:    true,
		Messages:  append([]session.ObservationMessage(nil), state.messages...),
		Runs:      append([]session.ObservationRun(nil), state.runs...),
	}
}

func (s *Server) notifyLocked(state *serverSession) {
	for watcher := range state.watchers {
		select {
		case watcher <- struct{}{}:
		default:
		}
	}
}

func sessionRoute(path string) (session.ID, string, bool) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(path, "/sessions/"), "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", false
	}
	return session.ID(parts[0]), parts[1], true
}
