import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:test/test.dart';

void main() {
  test('commits paired snapshots as authoritative replacements', () {
    final projection = WatchProjection(expectedSessionId: 'session');
    expect(
      projection.add(
        MessagesSnapshotEvent(
          messages: [UserMessage(id: 'message', content: 'live replacement')],
        ),
      ),
      isNull,
    );
    final commit = projection.add(
      StateSnapshotEvent(
        snapshot: _state(
          live: [_live(messageId: 'message', available: false)],
          tools: [
            {
              'ID': 'tool-1',
              'RunID': 'run-1',
              'MessageID': 'message',
              'Name': 'lookup',
              'Status': 'completed',
            },
          ],
        ),
      ),
    );

    expect(commit, isNotNull);
    expect(commit!.viewState.messages.single.text, 'live replacement');
    expect(commit.viewState.messages.single.liveUnavailable, isTrue);
    expect(commit.viewState.tools.single.id, 'tool-1');
    expect(commit.viewState.tools.single.phase, ToolActivityPhase.completed);
  });

  test('equal revisions are valid but lower revisions fail', () {
    final projection = WatchProjection(expectedSessionId: 'session');
    for (var i = 0; i < 2; i++) {
      projection.add(MessagesSnapshotEvent(messages: const []));
      expect(
        projection.add(StateSnapshotEvent(snapshot: _state(revision: 2))),
        isNotNull,
      );
    }
    projection.add(MessagesSnapshotEvent(messages: const []));
    expect(
      () => projection.add(StateSnapshotEvent(snapshot: _state(revision: 1))),
      throwsA(isA<ViewProjectionException>()),
    );
  });

  test('null slices normalize to empty and unsafe integers fail', () {
    final projection = WatchProjection(expectedSessionId: 'session');
    projection.add(MessagesSnapshotEvent(messages: const []));
    final commit = projection.add(
      StateSnapshotEvent(snapshot: _state(runs: null, tools: null, live: null)),
    );
    expect(commit!.snapshot.runs, isEmpty);

    final unsafe = WatchProjection(expectedSessionId: 'session');
    unsafe.add(MessagesSnapshotEvent(messages: const []));
    expect(
      () => unsafe.add(
        StateSnapshotEvent(snapshot: _state(revision: 9007199254740992)),
      ),
      throwsA(isA<ViewProjectionException>()),
    );
  });

  test('half pairs and resync markers do not commit', () {
    final projection = WatchProjection(expectedSessionId: 'session');
    projection.add(MessagesSnapshotEvent(messages: const []));
    projection.discardStagedPair();
    expect(projection.hasStagedMessages, isFalse);
    expect(
      () => projection.add(
        const StateSnapshotEvent(snapshot: {'ResyncRequired': true}),
      ),
      throwsA(
        isA<ViewProjectionException>().having(
          (error) => error.kind,
          'kind',
          ViewFailureKind.transient,
        ),
      ),
    );
  });
}

Map<String, Object?> _state({
  int revision = 1,
  Object? runs = const <Object?>[],
  Object? tools = const <Object?>[],
  Object? live = const <Object?>[],
}) => {
  'Watermark': {
    'StoreID': 'store',
    'SessionID': 'session',
    'Revision': revision,
  },
  'Exists': true,
  'OmittedOlderMessages': false,
  'Runs': runs,
  'Tools': tools,
  'Live': live,
};

Map<String, Object?> _live({
  required String messageId,
  required bool available,
}) => {
  'Identity': {
    'ServiceID': 'service',
    'SessionID': 'session',
    'RunID': 'run-1',
    'MessageID': messageId,
    'RequestID': 'request',
    'Attempt': 1,
    'Step': 1,
  },
  'Available': available,
  'PublicationVersion': 1,
};
