package fixture

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	"github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/core/types"
	"github.com/ag-ui-protocol/ag-ui/sdks/community/go/pkg/encoding/sse"
	agentagui "github.com/mattsp1290/eino-agent/agui"
	"github.com/mattsp1290/eino-agent/session"
	"github.com/mattsp1290/eino-agui/emitter"
)

const PrivacyCanary = "PRIVATE_PROVIDER_STATE_CANARY_7f31"

func Generic() ([]byte, error) {
	return emit("thread-generic", "run-generic", func(e *emitter.Emitter) {
		e.RunStarted()
		e.MessagesSnapshot([]types.Message{{ID: "user-1", Role: "user", Content: "safe synthetic café request"}, {ID: "assistant-1", Role: "assistant", Content: "baseline"}})
		e.TextStart("assistant-1")
		e.TextContent("assistant-1", " plus ")
		e.TextContent("assistant-1", "plus")
		e.TextEnd("assistant-1")
		e.ToolStart("tool-1", "lookup")
		e.ToolArgs("tool-1", `{"query":"safe"}`)
		e.ToolEnd("tool-1")
		e.ToolResult("tool-result-1", "tool-1", "safe result")
		e.ToolStart("tool-2", "lookup")
		e.ToolArgs("tool-2", `{}`)
		e.ToolEnd("tool-2")
		e.ToolResult("tool-result-2", "tool-2", "safe result")
		e.RunFinishedSuccess()
	})
}

func GenericTurn(turn int) ([]byte, error) {
	if turn < 1 || turn > 2 {
		return nil, fmt.Errorf("unsupported generic turn")
	}
	return emit("browser-thread", fmt.Sprintf("browser-run-%d", turn), func(e *emitter.Emitter) {
		e.RunStarted()
		if turn == 1 {
			e.MessagesSnapshot([]types.Message{{ID: "user-1", Role: "user", Content: "first turn"}})
		}
		messageID := fmt.Sprintf("assistant-%d", turn)
		toolID := fmt.Sprintf("tool-%d", turn)
		resultID := fmt.Sprintf("tool-result-%d", turn)
		e.TextStart(messageID)
		e.TextContent(messageID, fmt.Sprintf("Response %d", turn))
		e.ToolStart(toolID, "lookup")
		e.ToolArgs(toolID, fmt.Sprintf(`{"turn":%d}`, turn))
		e.ToolEnd(toolID)
		e.TextEnd(messageID)
		e.ToolResult(resultID, toolID, fmt.Sprintf("result %d", turn))
		e.RunFinishedSuccess()
	})
}

func Watch() ([]byte, error) {
	snapshot := session.ObservationSnapshot{
		Watermark: session.ObservationWatermark{StoreID: "store-fixture", SessionID: "session-fixture", Revision: 3},
		Exists:    true,
		Messages: []session.ObservationMessage{
			{ID: "user-1", RunID: "run-1", Role: session.RoleUser, Text: "safe synthetic request", Finalized: true},
			{ID: "assistant-1", RunID: "run-1", Role: session.RoleAssistant, Text: "durable baseline", Finalized: true},
		},
		Runs: []session.ObservationRun{{ID: "run-1", Status: session.RunCompleted, ProviderID: "fixture", ModelID: "scripted"}},
		Tools: []session.ObservationTool{
			{ID: "tool-1", RunID: "run-1", MessageID: "assistant-1", Name: "lookup", Status: session.ToolCallCompleted},
			{ID: "tool-2", RunID: "run-1", MessageID: "assistant-1", Name: "lookup", Status: session.ToolCallInterrupted},
		},
	}
	return EncodeWatch(snapshot)
}

func EncodeWatch(snapshot session.ObservationSnapshot) ([]byte, error) {
	var output bytes.Buffer
	writer := bufio.NewWriter(&output)
	emit := emitter.NewEmitter(context.Background(), writer, sse.NewSSEWriter(), string(snapshot.Watermark.SessionID), "", nil)
	bridge := agentagui.NewWatchBridge(emit, snapshot)
	if err := bridge.Initial(); err != nil {
		return nil, err
	}
	if err := writer.Flush(); err != nil {
		return nil, err
	}
	return normalizeTimestamps(output.Bytes()), errors.Join(emit.Err(), emit.EncErr())
}

func Privacy() ([]byte, error) {
	return emit("thread-privacy", "run-privacy", func(e *emitter.Emitter) {
		e.RunStarted()
		e.MessagesSnapshot([]types.Message{{ID: "assistant-safe", Role: "assistant", Content: "safe visible output", EncryptedValue: PrivacyCanary}})
		e.StateSnapshot(map[string]any{"safe": true})
		e.RunFinishedSuccess()
	})
}

func Resync() ([]byte, error) {
	return emit("session-fixture", "", func(e *emitter.Emitter) {
		e.StateSnapshot(struct{ ResyncRequired bool }{ResyncRequired: true})
	})
}

func emit(threadID, runID string, write func(*emitter.Emitter)) ([]byte, error) {
	var output bytes.Buffer
	writer := bufio.NewWriter(&output)
	emit := emitter.NewEmitter(context.Background(), writer, sse.NewSSEWriter(), threadID, runID, nil)
	write(emit)
	if err := writer.Flush(); err != nil {
		return nil, err
	}
	return normalizeTimestamps(output.Bytes()), errors.Join(emit.Err(), emit.EncErr())
}

var (
	eventIDTimestamp = regexp.MustCompile(`_[0-9]+\n`)
	jsonTimestamp    = regexp.MustCompile(`"timestamp":[0-9]+`)
)

func normalizeTimestamps(data []byte) []byte {
	data = eventIDTimestamp.ReplaceAll(data, []byte("_1700000000000\n"))
	return jsonTimestamp.ReplaceAll(data, []byte(`"timestamp":1700000000000`))
}

func Generate(root string) (map[string]string, error) {
	fixtures := map[string]func() ([]byte, error){
		"generic.sse":     Generic,
		"eino-watch.sse":  Watch,
		"eino-resync.sse": Resync,
		"privacy.sse":     Privacy,
	}
	hashes := make(map[string]string, len(fixtures))
	for name, generate := range fixtures {
		data, err := generate()
		if err != nil {
			return nil, fmt.Errorf("generate %s: %w", name, err)
		}
		if bytes.Contains(data, []byte(PrivacyCanary)) {
			return nil, fmt.Errorf("privacy canary escaped into %s", name)
		}
		if err := os.WriteFile(filepath.Join(root, name), data, 0o644); err != nil {
			return nil, err
		}
		sum := sha256.Sum256(data)
		hashes[name] = hex.EncodeToString(sum[:])
	}
	return hashes, nil
}
