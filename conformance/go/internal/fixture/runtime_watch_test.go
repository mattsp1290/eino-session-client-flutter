package fixture

import (
	"bufio"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mattsp1290/eino-agent/session"
	"github.com/mattsp1290/eino-agent/store/sqlite"
	"github.com/mattsp1290/eino-agent/transport"
	"github.com/mattsp1290/eino-agent/watch"
)

func TestWatchOverflowRequiresFreshAuthoritativeAttachment(t *testing.T) {
	store, err := sqlite.Open(t.Context(), filepath.Join(t.TempDir(), "overflow.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = store.Close() }()
	options := fixtureWatchOptions()
	options.PendingUpdates = 1
	service, err := watch.NewService(store, options)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = service.Close(context.Background()) }()
	subscription, err := service.Watch(t.Context(), "overflow")
	if err != nil {
		t.Fatal(err)
	}
	defer subscription.Close()
	if _, err := store.CreateSession(t.Context(), session.Session{ID: "overflow"}); err != nil {
		t.Fatal(err)
	}
	run, err := store.AdmitRun(t.Context(), session.Run{
		ID: "overflow-run", SessionID: "overflow", Status: session.RunRunning, ClaimToken: "fixture",
	}, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Execution(session.RunFence{RunID: run.ID, ClaimToken: run.ClaimToken}).
		AppendMessage(t.Context(), session.Message{
			ID: "overflow-message", SessionID: run.SessionID, RunID: run.ID, Role: session.RoleAssistant,
		}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	for {
		if _, err = subscription.Next(ctx); err != nil {
			break
		}
	}
	if !errors.Is(err, watch.ErrResyncRequired) {
		t.Fatalf("overflow error=%v", err)
	}
	fresh, err := service.Watch(ctx, "overflow")
	if err != nil {
		t.Fatal(err)
	}
	defer fresh.Close()
	if got := fresh.Initial().Messages; len(got) != 1 || got[0].ID != "overflow-message" {
		t.Fatalf("fresh authoritative snapshot=%#v", got)
	}
}

func TestHTTP2WatchSurvivesIdleBeyondWriteDeadline(t *testing.T) {
	store, err := sqlite.Open(t.Context(), filepath.Join(t.TempDir(), "http2.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = store.Close() }()
	service, err := watch.NewService(store, fixtureWatchOptions())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = service.Close(context.Background()) }()
	const writeTimeout = 40 * time.Millisecond
	handler := transport.SessionWatchHandler(transport.SessionWatchConfig{
		Service:      service,
		WriteTimeout: writeTimeout,
		Auth: func(ctx context.Context, _ *http.Request) (context.Context, error) {
			return ctx, nil
		},
		Session: func(*http.Request) (session.ID, error) { return "http2", nil },
	})
	server := httptest.NewUnstartedServer(handler)
	server.EnableHTTP2 = true
	server.StartTLS()
	defer server.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := server.Client().Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.ProtoMajor != 2 {
		t.Fatalf("protocol=%s", response.Proto)
	}
	scanner := bufio.NewScanner(response.Body)
	readWatchState(t, scanner, `"Exists":false`)
	time.Sleep(3 * writeTimeout)
	if _, err := store.CreateSession(ctx, session.Session{ID: "http2"}); err != nil {
		t.Fatal(err)
	}
	service.Hint("http2")
	readWatchState(t, scanner, `"Exists":true`)
}

func fixtureWatchOptions() watch.Options {
	return watch.Options{
		Snapshot: session.ObservationLimits{
			MaxMessages: 20, MaxTools: 20, MaxParts: 40,
			MaxSnapshotBytes: 1 << 20, MaxTextBytes: 128 << 10,
		},
		PollInterval:     5 * time.Millisecond,
		ReadTimeout:      time.Second,
		MaxSubscriptions: 10, MaxWatchedSessions: 10,
		MaxLiveRuns: 10, MaxLiveTextBytes: 1 << 20, PendingUpdates: 10,
	}
}

func readWatchState(t *testing.T, scanner *bufio.Scanner, marker string) {
	t.Helper()
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "STATE_SNAPSHOT") && strings.Contains(line, marker) {
			return
		}
	}
	t.Fatalf("watch ended before %s: %v", marker, scanner.Err())
}
