import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:test/test.dart';

void main() {
  test('silent initial watches hit the baseline deadline', () async {
    final bodies = List.generate(3, (_) => StreamController<List<int>>());
    final transport = _QueueTransport([
      for (final body in bodies)
        Future.value(
          TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/event-stream'},
            body: body.stream,
          ),
        ),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: transport,
      contract: const _Contract(),
      baselineTimeout: const Duration(milliseconds: 5),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    await adapter.connect('session');
    expect(transport.requests, hasLength(3));
    expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
    await adapter.dispose();
    for (final body in bodies) {
      await body.close();
    }
  });

  test(
    'comment-only initial watches retry but established idle stays healthy',
    () async {
      final established = StreamController<List<int>>();
      final transport = _QueueTransport([
        Future.value(
          TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/event-stream'},
            body: Stream.value(utf8.encode(': keepalive\n\n')),
          ),
        ),
        Future.value(
          TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/event-stream'},
            body: established.stream,
          ),
        ),
      ]);
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: transport,
        contract: const _Contract(),
        baselineTimeout: const Duration(milliseconds: 5),
        retryDelays: const [Duration.zero],
      );
      final connecting = adapter.connect('session');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      established
        ..add(_sse(MessagesSnapshotEvent(messages: const [])))
        ..add(_sse(StateSnapshotEvent(snapshot: _state())));
      await connecting;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.connectionPhase, ConnectionPhase.connected);
      expect(transport.requests, hasLength(2));
      await adapter.dispose();
      await established.close();
    },
  );

  test('transient watch failures use exactly three GET attempts', () async {
    final transport = _QueueTransport([
      for (var attempt = 0; attempt < 3; attempt++)
        Future.value(
          TransportResponse(
            statusCode: 503,
            headers: const {},
            body: const Stream.empty(),
          ),
        ),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: transport,
      contract: const _Contract(),
      retryDelays: const [Duration.zero, Duration.zero],
    );

    await adapter.connect('session');

    expect(transport.requests, hasLength(3));
    expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
    await adapter.dispose();
  });

  for (final entry in const {
    401: ViewFailureKind.unauthorized,
    403: ViewFailureKind.forbidden,
  }.entries) {
    test('${entry.key} is classified without retry', () async {
      final transport = _QueueTransport([
        Future.value(
          TransportResponse(
            statusCode: entry.key,
            headers: const {},
            body: const Stream.empty(),
          ),
        ),
      ]);
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: transport,
        contract: const _Contract(),
      );

      await adapter.connect('session');

      expect(transport.requests, hasLength(1));
      expect(controller.state.failure?.kind, entry.value);
      await adapter.dispose();
    });
  }

  test(
    'lost admission acknowledgement is not retried and watch stays usable',
    () async {
      final watchBody = StreamController<List<int>>();
      final lostAdmission = Completer<TransportResponse>();
      final transport = _QueueTransport([
        Future.value(
          TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/event-stream'},
            body: watchBody.stream,
          ),
        ),
        lostAdmission.future,
      ]);
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: transport,
        contract: const _Contract(),
      );
      final connected = adapter.connect('session');
      watchBody
        ..add(_sse(MessagesSnapshotEvent(messages: const [])))
        ..add(_sse(StateSnapshotEvent(snapshot: _state())));
      await connected;

      final starting = adapter.start('one message');
      lostAdmission.completeError(StateError('lost acknowledgement'));
      await starting;

      expect(transport.requests, hasLength(2));
      expect(controller.state.runPhase, RunPhase.outcomeUnknown);
      expect(controller.state.connectionPhase, ConnectionPhase.connected);
      adapter.resetSubmissionTracking();
      expect(controller.state.runPhase, RunPhase.idle);
      expect(controller.state.failure, isNull);
      expect(transport.requests, hasLength(2));
      await adapter.dispose();
      await watchBody.close();
    },
  );

  test('dispose during retry delay opens no later GET', () async {
    final delayStarted = Completer<void>();
    final releaseDelay = Completer<void>();
    final transport = _QueueTransport([
      Future.value(
        TransportResponse(
          statusCode: 503,
          headers: const {},
          body: const Stream.empty(),
        ),
      ),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: transport,
      contract: const _Contract(),
      delay: (_) async {
        if (!delayStarted.isCompleted) delayStarted.complete();
        await releaseDelay.future;
      },
    );
    final connecting = adapter.connect('session');
    await delayStarted.future;
    await adapter.dispose();
    releaseDelay.complete();
    await connecting;
    await Future<void>.delayed(Duration.zero);

    expect(transport.requests, hasLength(1));
  });
}

List<int> _sse(BaseEvent event) =>
    utf8.encode('data: ${jsonEncode(event.toJson())}\n\n');

Map<String, Object?> _state() => {
  'Watermark': {'StoreID': 'store', 'SessionID': 'session', 'Revision': 1},
  'Exists': true,
  'OmittedOlderMessages': false,
  'Runs': <Object?>[],
  'Tools': <Object?>[],
  'Live': <Object?>[],
};

final class _Contract implements EinoSessionContract {
  const _Contract();

  @override
  RequestSpec watchRequest(String sessionId) => RequestSpec(
    method: 'GET',
    uri: Uri.parse('https://example.invalid/$sessionId/watch'),
  );

  @override
  RequestSpec admissionRequest(String sessionId, String newText) => RequestSpec(
    method: 'POST',
    uri: Uri.parse('https://example.invalid/$sessionId/runs'),
    body: utf8.encode(jsonEncode({'message': newText})),
  );

  @override
  RunAdmission decodeAdmission(List<int> body) =>
      const RunAdmission(sessionId: 'session', runId: 'run');

  @override
  RequestSpec interruptRequest(String sessionId, String runId) => RequestSpec(
    method: 'POST',
    uri: Uri.parse('https://example.invalid/$runId/interrupt'),
  );
}

final class _QueueTransport implements RequestTransport {
  _QueueTransport(List<Future<TransportResponse>> responses)
    : _responses = List.of(responses);

  final List<Future<TransportResponse>> _responses;
  final List<RequestSpec> requests = [];

  @override
  RequestOperation open(RequestSpec request) {
    requests.add(request);
    return _Operation(_responses.removeAt(0));
  }

  @override
  Future<void> dispose() async {}
}

final class _Operation implements RequestOperation {
  _Operation(this.response);

  @override
  final Future<TransportResponse> response;

  @override
  Future<void> abort() async {}
}
