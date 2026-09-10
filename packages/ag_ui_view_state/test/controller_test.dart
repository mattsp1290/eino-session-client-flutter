import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:test/test.dart';

void main() {
  test('listener removal and disposal stop later callbacks', () async {
    final controller = AgentViewController();
    var calls = 0;
    final remove = controller.addListener((_) => calls += 1);
    final generation = controller.beginRequest();
    controller.apply(
      RunStartedEvent(threadId: 'thread', runId: 'run'),
      generation: generation,
    );
    expect(calls, 2);
    remove();
    controller.apply(
      const TextMessageContentEvent(messageId: 'message', delta: 'hello'),
      generation: generation,
    );
    expect(calls, 2);
    await controller.dispose();
    controller.apply(
      const TextMessageContentEvent(messageId: 'message', delta: 'late'),
      generation: generation,
    );
    expect(controller.state.connectionPhase, ConnectionPhase.disposed);
  });

  test('listener failures are content-free and isolated', () {
    final controller = AgentViewController();
    controller.addListener((_) => throw StateError('private canary'));
    final generation = controller.beginRequest();
    expect(controller.state.failure?.kind, ViewFailureKind.hostCallbackFailed);
    expect(controller.state.toSafeJson().toString(), isNot(contains('canary')));
    expect(generation, controller.generation);
  });
}
