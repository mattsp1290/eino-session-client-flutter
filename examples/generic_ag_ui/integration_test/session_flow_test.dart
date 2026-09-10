import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const endpoint = String.fromEnvironment('AG_UI_ENDPOINT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browser transport sends exact caller-owned history twice', (
    tester,
  ) async {
    expect(endpoint, isNotEmpty);
    final history = _CanonicalHistory();
    final controller = AgentViewController();
    final adapter = AgUiPostAdapter(
      controller: controller,
      transport: HttpRequestTransport.owned(),
      endpoint: Uri.parse(endpoint),
      onProtocolEvent: history.record,
    );

    history.messages.add(UserMessage(id: 'user-1', content: 'first turn'));
    await adapter.start(
      SimpleRunAgentInput(
        threadId: 'browser-thread',
        runId: 'browser-run-1',
        messages: List.unmodifiable(history.messages),
      ),
    );
    expect(controller.state.runPhase, RunPhase.completed);
    expect(
      history.messages.whereType<AssistantMessage>().single.toolCalls,
      hasLength(1),
    );

    history.messages.add(UserMessage(id: 'user-2', content: 'second turn'));
    await adapter.start(
      SimpleRunAgentInput(
        threadId: 'browser-thread',
        runId: 'browser-run-2',
        messages: List.unmodifiable(history.messages),
      ),
    );

    expect(controller.state.runPhase, RunPhase.completed);
    expect(controller.state.messages.last.text, 'Response 2');
    expect(history.messages.whereType<AssistantMessage>(), hasLength(2));
    expect(history.messages.whereType<ToolMessage>(), hasLength(2));
    await adapter.dispose();
    await controller.dispose();
  });
}

final class _CanonicalHistory {
  final List<Message> messages = [];
  final Map<String, _AssistantBuilder> _assistants = {};

  void record(BaseEvent event) {
    if (event is MessagesSnapshotEvent) {
      messages
        ..clear()
        ..addAll(event.messages);
    } else if (event is TextMessageStartEvent) {
      _assistants.putIfAbsent(event.messageId, _AssistantBuilder.new);
    } else if (event is TextMessageContentEvent) {
      _assistants.putIfAbsent(event.messageId, _AssistantBuilder.new).text +=
          event.delta;
    } else if (event is ToolCallStartEvent) {
      _assistants
          .putIfAbsent(
            event.parentMessageId ?? _activeAssistantID,
            _AssistantBuilder.new,
          )
          .tools[event.toolCallId] = _ToolBuilder(
        event.toolCallName,
      );
    } else if (event is ToolCallArgsEvent) {
      for (final assistant in _assistants.values) {
        final tool = assistant.tools[event.toolCallId];
        if (tool != null) tool.arguments += event.delta;
      }
    } else if (event is ToolCallResultEvent) {
      for (final entry in _assistants.entries.toList()) {
        if (entry.value.tools.containsKey(event.toolCallId)) {
          _commitAssistant(entry.key);
          break;
        }
      }
      messages.add(
        ToolMessage(
          id: event.messageId,
          toolCallId: event.toolCallId,
          content: event.content,
        ),
      );
    } else if (event is RunFinishedEvent) {
      for (final id in _assistants.keys.toList()) {
        _commitAssistant(id);
      }
    }
  }

  String get _activeAssistantID {
    if (_assistants.length != 1) throw StateError('ambiguous assistant');
    return _assistants.keys.single;
  }

  void _commitAssistant(String id) {
    final builder = _assistants.remove(id);
    if (builder == null) return;
    messages.add(
      AssistantMessage(
        id: id,
        content: builder.text,
        toolCalls: [
          for (final entry in builder.tools.entries)
            ToolCall(
              id: entry.key,
              function: FunctionCall(
                name: entry.value.name,
                arguments: entry.value.arguments,
              ),
            ),
        ],
      ),
    );
  }
}

final class _AssistantBuilder {
  String text = '';
  final Map<String, _ToolBuilder> tools = {};
}

final class _ToolBuilder {
  _ToolBuilder(this.name);

  final String name;
  String arguments = '';
}
