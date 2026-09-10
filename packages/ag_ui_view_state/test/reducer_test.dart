import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:test/test.dart';

void main() {
  group('EventViewReducer', () {
    test('snapshot baseline and repeated deltas preserve exact text', () {
      final reducer = EventViewReducer();
      var state = AgentViewState();
      state = reducer.reduce(
        state,
        MessagesSnapshotEvent(
          messages: [const AssistantMessage(id: 'message', content: 'base')],
        ),
      );
      state = reducer.reduce(
        state,
        const TextMessageContentEvent(messageId: 'message', delta: '!'),
      );
      state = reducer.reduce(
        state,
        const TextMessageContentEvent(messageId: 'message', delta: '!'),
      );

      expect(state.messages, hasLength(1));
      expect(state.messages.single.text, 'base!!');
    });

    test('same-name tools retain stable distinct identities', () {
      final reducer = EventViewReducer();
      var state = reducer.reduce(
        AgentViewState(),
        const ToolCallStartEvent(toolCallId: 'one', toolCallName: 'lookup'),
      );
      state = reducer.reduce(
        state,
        const ToolCallStartEvent(toolCallId: 'two', toolCallName: 'lookup'),
      );
      state = reducer.reduce(
        state,
        const ToolCallResultEvent(
          messageId: 'result',
          toolCallId: 'two',
          content: 'private result',
        ),
      );

      expect(state.tools.map((tool) => tool.id), ['one', 'two']);
      expect(state.tools.last.phase, ToolActivityPhase.resultObserved);
      expect(state.toSafeJson().toString(), isNot(contains('private result')));
    });

    test('child-attributed events cannot mutate parent projection', () {
      final reducer = EventViewReducer();
      final initial = AgentViewState(
        messages: const [
          MessageView(
            id: 'shared',
            role: ViewMessageRole.assistant,
            text: 'parent',
          ),
        ],
      );
      final state = reducer.reduce(
        initial,
        const TextMessageContentEvent(
          messageId: 'shared',
          delta: 'child secret',
          subagentRunId: 'child',
        ),
      );

      expect(state, same(initial));
      expect(state.messages.single.text, 'parent');
    });

    test('interrupt outcome maps to paused without retaining payload', () {
      final reducer = EventViewReducer();
      var state = reducer.reduce(
        AgentViewState(),
        RunStartedEvent(threadId: 'thread', runId: 'run'),
      );
      state = reducer.reduce(
        state,
        RunFinishedEvent(
          threadId: 'thread',
          runId: 'run',
          outcome: RunFinishedInterruptOutcome(
            interrupts: const [
              Interrupt(id: 'secret-id', reason: 'secret reason'),
            ],
          ),
        ),
      );

      expect(state.runPhase, RunPhase.paused);
      expect(state.status, 'Waiting for host action');
      expect(state.toSafeJson().toString(), isNot(contains('secret')));
    });

    test('empty snapshot authoritatively clears the view', () {
      final reducer = EventViewReducer();
      final state = reducer.reduce(
        AgentViewState(
          messages: const [
            MessageView(id: 'old', role: ViewMessageRole.user, text: 'old'),
          ],
        ),
        MessagesSnapshotEvent(messages: const []),
      );
      expect(state.messages, isEmpty);
      expect(state.tools, isEmpty);
    });
  });
}
