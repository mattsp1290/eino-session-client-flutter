import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:test/test.dart';

void main() {
  test('raw, custom, state, metadata, and run errors are never retained', () {
    const canary = 'PRIVATE_PROVIDER_STATE_CANARY_7f31';
    final reducer = EventViewReducer();
    var state = AgentViewState();
    final events = <BaseEvent>[
      const RawEvent(event: {'provider': canary}, source: canary),
      const CustomEvent(name: canary, value: {'secret': canary}),
      const StateSnapshotEvent(snapshot: {'opaque': canary}),
      RunStartedEvent(
        threadId: 'thread',
        runId: 'run',
        rawEvent: {'secret': canary},
      ),
      const RunErrorEvent(message: canary, code: canary),
    ];

    for (final event in events) {
      state = reducer.reduce(state, event);
    }

    expect(state.runPhase, RunPhase.failed);
    expect(state.failure?.kind, ViewFailureKind.protocolViolation);
    expect(state.toSafeJson().toString(), isNot(contains(canary)));
  });
}
