package fixture

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/cloudwego/eino/schema"
	"github.com/mattsp1290/eino-agent/composition"
	"github.com/mattsp1290/eino-agent/extension"
	"github.com/mattsp1290/eino-agent/model"
	"github.com/mattsp1290/eino-agent/tools"
)

type fixtureResolver struct{}

func (fixtureResolver) Resolve(_ context.Context, selection model.Selection, _ model.Runtime) (model.Resolved, error) {
	return model.Resolved{
		Provider: model.Provider{ID: selection.ProviderID, Name: "Fixture provider", Source: "conformance"},
		Model: model.Descriptor{
			ID:           selection.ModelID,
			ProviderID:   selection.ProviderID,
			Name:         "Deterministic scripted model",
			ContextLimit: 8192,
			OutputLimit:  512,
			Capabilities: map[string]bool{"streaming": true},
		},
		Streamer: fixtureStreamer{},
	}, nil
}

type fixtureStreamer struct{}

func (fixtureStreamer) StreamProvider(ctx context.Context, request model.Request) (*schema.StreamReader[model.StreamDelta], error) {
	reader, writer := schema.Pipe[model.StreamDelta](2)
	go func() {
		defer writer.Close()
		userText := lastFixtureUserText(request.Messages)
		delay := fixtureStreamDelay(request.Options)
		if strings.Contains(strings.ToLower(userText), "pause") {
			if sendFixtureDelta(ctx, writer, delay, schema.AssistantMessage("Paused live prefix", nil)) {
				return
			}
			<-ctx.Done()
			writer.Send(model.StreamDelta{}, ctx.Err())
			return
		}
		if !fixtureTurnHasTool(request.Messages) {
			if sendFixtureDelta(ctx, writer, delay, schema.AssistantMessage("Checking input. ", nil)) {
				return
			}
			call := schema.ToolCall{
				ID:       "scripted-call-" + request.Identity.RunID + "-" + strconv.Itoa(len(request.Messages)),
				Type:     "function",
				Function: schema.FunctionCall{Name: "echo", Arguments: `{"text":"safe scripted input"}`},
			}
			_ = sendFixtureDelta(ctx, writer, delay, schema.AssistantMessage("", []schema.ToolCall{call}))
			return
		}
		_ = sendFixtureDelta(ctx, writer, delay, schema.AssistantMessage("Scripted response to "+strconv.Quote(userText), nil))
	}()
	return reader, nil
}

func sendFixtureDelta(ctx context.Context, writer *schema.StreamWriter[model.StreamDelta], delay time.Duration, message *schema.Message) bool {
	select {
	case <-ctx.Done():
		writer.Send(model.StreamDelta{}, ctx.Err())
		return true
	case <-time.After(delay):
	}
	return writer.Send(model.StreamDelta{Message: message}, nil)
}

func fixtureStreamDelay(options map[string]string) time.Duration {
	if value := options["stream_delay_ms"]; value != "" {
		if milliseconds, err := strconv.Atoi(value); err == nil && milliseconds >= 0 {
			return time.Duration(milliseconds) * time.Millisecond
		}
	}
	return 10 * time.Millisecond
}

func lastFixtureUserText(messages []*schema.Message) string {
	for index := len(messages) - 1; index >= 0; index-- {
		if messages[index] != nil && messages[index].Role == schema.User {
			return messages[index].Content
		}
	}
	return "request"
}

func fixtureTurnHasTool(messages []*schema.Message) bool {
	for index := len(messages) - 1; index >= 0; index-- {
		if messages[index] == nil {
			continue
		}
		if messages[index].Role == schema.User {
			return false
		}
		if messages[index].Role == schema.Tool {
			return true
		}
	}
	return false
}

type echoInput struct {
	Text string `json:"text"`
}

func mountFixtureTool(ctx context.Context, registry *composition.Registry) (*composition.Mount, error) {
	return registry.Mount(ctx, extension.Component{
		InstanceID: "fixture-echo",
		Artifact: extension.Artifact{
			Name: "fixture-echo", Version: "v1", Hash: "fixture-echo-v1",
			ConfigHash: "default", SourceKind: extension.SourceNative,
		},
	}, composition.InstallerFunc(func(_ context.Context, registrar *composition.Registrar) error {
		return registrar.Tool(composition.ToolRegistration{
			ID:    "echo",
			Scope: extension.GlobalScope(),
			Definition: tools.Definition{
				Name:        "echo",
				Description: "Echo deterministic synthetic input locally.",
				Parameters: schema.NewParamsOneOfByParams(map[string]*schema.ParameterInfo{
					"text": {Type: schema.String, Required: true},
				}),
				Execute: tools.TypedExecutor[echoInput, echoInput](func(_ context.Context, execution tools.TypedExecution[echoInput]) (echoInput, error) {
					return execution.Input, nil
				}),
			},
		})
	}))
}
