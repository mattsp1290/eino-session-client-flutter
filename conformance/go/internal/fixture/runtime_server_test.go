package fixture

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mattsp1290/eino-agent/session"
)

func TestRuntimeServerPersistsAndReplaysCompletedRun(t *testing.T) {
	database := filepath.Join(t.TempDir(), "fixture.db")
	server, err := NewRuntimeServer(context.Background(), database)
	if err != nil {
		t.Fatal(err)
	}
	httpServer := httptest.NewServer(server)

	unauthorized, err := http.Get(httpServer.URL + "/sessions/session/events")
	if err != nil {
		t.Fatal(err)
	}
	_ = unauthorized.Body.Close()
	if unauthorized.StatusCode != http.StatusForbidden {
		t.Fatalf("unauthorized watch status=%d", unauthorized.StatusCode)
	}

	runID := admitRuntimeRun(t, httpServer.URL, "session", "first turn")
	watchData := readWatchUntil(t, httpServer.URL, "session", func(data string) bool {
		return strings.Contains(data, `"ID":"`+runID+`"`) &&
			strings.Contains(data, `"Status":"completed"`) &&
			strings.Contains(data, `"Name":"echo"`)
	})
	if !strings.Contains(watchData, `"role":"user","content":"first turn"`) {
		t.Fatal("durable user message missing from watch")
	}
	waitForRuntimeHandleCleanup(t, server, session.RunID(runID))
	secondRunID := admitRuntimeRun(t, httpServer.URL, "session", "second turn")
	if secondRunID == runID {
		t.Fatal("sequential turns reused a run ID")
	}
	_ = readWatchUntil(t, httpServer.URL, "session", func(data string) bool {
		return strings.Contains(data, `"ID":"`+secondRunID+`"`) &&
			strings.Contains(data, `"Status":"completed"`) &&
			strings.Count(data, `"Name":"echo"`) == 2
	})
	snapshot, err := server.store.ReadObservationSnapshot(
		context.Background(),
		"session",
		session.ObservationLimits{
			MaxMessages:      50,
			MaxTools:         100,
			MaxParts:         200,
			MaxSnapshotBytes: 1 << 20,
			MaxTextBytes:     128 << 10,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Runs) != 2 || len(snapshot.Tools) != 2 {
		t.Fatalf("durable history runs=%d tools=%d", len(snapshot.Runs), len(snapshot.Tools))
	}
	if snapshot.Tools[0].Name != "echo" || snapshot.Tools[1].Name != "echo" ||
		snapshot.Tools[0].ID == snapshot.Tools[1].ID {
		t.Fatalf("same-name tool identities were not distinct: %#v", snapshot.Tools)
	}

	httpServer.Close()
	if err := server.Close(); err != nil {
		t.Fatal(err)
	}

	reopened, err := NewRuntimeServer(context.Background(), database)
	if err != nil {
		t.Fatal(err)
	}
	reopenedHTTP := httptest.NewServer(reopened)
	replay := readWatchUntil(t, reopenedHTTP.URL, "session", func(data string) bool {
		return strings.Contains(data, `"ID":"`+secondRunID+`"`) &&
			strings.Count(data, `"Name":"echo"`) == 2
	})
	if !strings.Contains(replay, `"content":"first turn"`) ||
		!strings.Contains(replay, `"content":"second turn"`) {
		t.Fatal("reopened store did not replay durable history")
	}
	reopenedHTTP.Close()
	if err := reopened.Close(); err != nil {
		t.Fatal(err)
	}
}

func waitForRuntimeHandleCleanup(t *testing.T, server *RuntimeServer, runID session.RunID) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		server.mu.Lock()
		_, active := server.handles[runID]
		server.mu.Unlock()
		if !active {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("completed runtime handle remained active")
}

func admitRuntimeRun(t *testing.T, baseURL, sessionID, message string) string {
	t.Helper()
	body, err := json.Marshal(map[string]string{"message": message})
	if err != nil {
		t.Fatal(err)
	}
	request, err := http.NewRequest(http.MethodPost, baseURL+"/sessions/"+sessionID+"/runs", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Fixture-Session", sessionID)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		data, _ := io.ReadAll(response.Body)
		t.Fatalf("admission status=%d body=%s", response.StatusCode, data)
	}
	var acknowledgement struct {
		RunID string `json:"run_id"`
	}
	if err := json.NewDecoder(response.Body).Decode(&acknowledgement); err != nil {
		t.Fatal(err)
	}
	return acknowledgement.RunID
}

func readWatchUntil(t *testing.T, baseURL, sessionID string, complete func(string) bool) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/sessions/"+sessionID+"/events", nil)
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("X-Fixture-Session", sessionID)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("watch status=%d", response.StatusCode)
	}
	scanner := bufio.NewScanner(response.Body)
	scanner.Buffer(make([]byte, 1024), 2<<20)
	var collected strings.Builder
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		data := strings.TrimPrefix(line, "data: ")
		collected.WriteString(data)
		if complete(data) {
			return collected.String()
		}
	}
	if err := scanner.Err(); err != nil && ctx.Err() == nil {
		t.Fatal(err)
	}
	t.Fatalf("watch condition not reached: %s", collected.String())
	return ""
}
