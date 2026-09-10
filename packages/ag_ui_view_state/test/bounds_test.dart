import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:test/test.dart';

void main() {
  test('message byte cap accepts exact limit and rejects limit plus one', () {
    final reducer = EventViewReducer(
      limits: ViewLimits(maxMessageBytes: 4, maxDisplayBytes: 100),
    );
    final exact = reducer.reduce(
      AgentViewState(),
      const TextMessageContentEvent(messageId: 'id', delta: '1234'),
    );
    expect(exact.messages.single.text, '1234');
    expect(
      () => reducer.reduce(
        exact,
        const TextMessageContentEvent(messageId: 'id', delta: '5'),
      ),
      throwsA(
        isA<ViewProjectionException>().having(
          (error) => error.kind,
          'kind',
          ViewFailureKind.capacityExceeded,
        ),
      ),
    );
    expect(exact.messages.single.text, '1234');
  });

  test('all configurable limits reject non-positive values', () {
    expect(() => ViewLimits(maxMessages: 0), throwsArgumentError);
    expect(() => ViewLimits(maxSseDataCodeUnits: -1), throwsArgumentError);
  });

  test('message and tool counts retain the exact configured limits', () {
    final messageReducer = EventViewReducer(
      limits: ViewLimits(maxMessages: 2, maxDisplayBytes: 1000),
    );
    var messages = AgentViewState();
    for (var index = 0; index < 2; index++) {
      messages = messageReducer.reduce(
        messages,
        TextMessageContentEvent(messageId: 'm$index', delta: 'x'),
      );
    }
    expect(messages.messages, hasLength(2));
    expect(
      () => messageReducer.reduce(
        messages,
        const TextMessageContentEvent(messageId: 'overflow', delta: 'x'),
      ),
      throwsA(isA<ViewProjectionException>()),
    );

    final toolReducer = EventViewReducer(
      limits: ViewLimits(maxTools: 2, maxDisplayBytes: 1000),
    );
    var tools = AgentViewState();
    for (var index = 0; index < 2; index++) {
      tools = toolReducer.reduce(
        tools,
        ToolCallStartEvent(toolCallId: 't$index', toolCallName: 'same'),
      );
    }
    expect(tools.tools, hasLength(2));
    expect(
      () => toolReducer.reduce(
        tools,
        const ToolCallStartEvent(toolCallId: 'overflow', toolCallName: 'same'),
      ),
      throwsA(isA<ViewProjectionException>()),
    );
  });

  test('display byte overflow preserves the last consistent state', () {
    final reducer = EventViewReducer(
      limits: ViewLimits(maxMessageBytes: 100, maxDisplayBytes: 20),
    );
    final exact = reducer.reduce(
      AgentViewState(),
      const TextMessageContentEvent(messageId: 'id', delta: '12'),
    );
    expect(exact.messages.single.text, '12');
    expect(
      () => reducer.reduce(
        exact,
        const TextMessageContentEvent(messageId: 'id', delta: '3'),
      ),
      throwsA(isA<ViewProjectionException>()),
    );
    expect(exact.messages.single.text, '12');
  });
}
