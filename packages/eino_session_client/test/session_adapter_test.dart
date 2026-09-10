import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'terminal watch evidence races admission acknowledgement safely',
    () async {
      final watchBody = StreamController<List<int>>();
      final transport = _QueueTransport([
        TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/event-stream'},
          body: watchBody.stream,
        ),
        TransportResponse(
          statusCode: 202,
          headers: const {'content-type': 'application/json'},
          body: Stream.value(
            utf8.encode('{"session_id":"session","run_id":"run-1"}'),
          ),
        ),
      ]);
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: transport,
        contract: _Contract(),
      );

      final connected = adapter.connect('session');
      watchBody.add(
        _sse(
          MessagesSnapshotEvent(
            messages: [UserMessage(id: 'message', content: 'hello')],
          ),
        ),
      );
      watchBody.add(
        _sse(
          StateSnapshotEvent(
            snapshot: _watchState(
              runs: const [
                {'ID': 'run-1', 'Status': 'completed'},
              ],
            ),
          ),
        ),
      );
      await connected;
      await adapter.start('new text');

      expect(controller.state.runPhase, RunPhase.completed);
      expect(controller.state.messages.single.text, 'hello');
      expect(transport.requests, hasLength(2));
      expect(utf8.decode(transport.requests[1].body), '{"message":"new text"}');
      expect(utf8.decode(transport.requests[1].body), isNot(contains('hello')));

      await adapter.dispose();
      await watchBody.close();
    },
  );

  test('session replacement drops old presentation immediately', () async {
    final first = StreamController<List<int>>();
    final second = StreamController<List<int>>();
    final parserClients = <_TrackingParserClient>[];
    final transport = _QueueTransport([
      TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/event-stream'},
        body: first.stream,
      ),
      TransportResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/event-stream'},
        body: second.stream,
      ),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: transport,
      contract: _Contract(),
      parserClientFactory: () {
        final client = _TrackingParserClient();
        parserClients.add(client);
        return client;
      },
    );
    final firstConnect = adapter.connect('session');
    first.add(
      _sse(
        MessagesSnapshotEvent(
          messages: [UserMessage(id: 'old', content: 'old')],
        ),
      ),
    );
    first.add(_sse(StateSnapshotEvent(snapshot: _watchState())));
    await firstConnect;
    expect(controller.state.messages, isNotEmpty);

    final secondConnect = adapter.connect('other');
    expect(controller.state.messages, isEmpty);
    second.add(_sse(MessagesSnapshotEvent(messages: const [])));
    second.add(
      _sse(StateSnapshotEvent(snapshot: _watchState(sessionId: 'other'))),
    );
    await secondConnect;
    expect(controller.state.connectionPhase, ConnectionPhase.connected);
    expect(parserClients, hasLength(2));
    expect(parserClients.first.closed, isTrue);
    expect(parserClients.last.closed, isFalse);

    await adapter.dispose();
    expect(parserClients.last.closed, isTrue);
    await first.close();
    await second.close();
  });

  test(
    'watch cancellation settles attempts and closes parser clients',
    () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      final parserClients = <_TrackingParserClient>[];
      final transport = _QueueTransport([
        _watchResponse(first.stream),
        _watchResponse(second.stream),
      ]);
      final adapter = EinoSessionAdapter(
        controller: AgentViewController(),
        transport: transport,
        contract: _Contract(),
        parserClientFactory: () {
          final client = _TrackingParserClient();
          parserClients.add(client);
          return client;
        },
      );

      final firstConnect = adapter.connect('session');
      _addBaseline(first, sessionId: 'session');
      await firstConnect;
      final reconnect = adapter.reconnect();
      _addBaseline(second, sessionId: 'session');
      await reconnect;

      expect(parserClients, hasLength(2));
      expect(parserClients.first.closed, isTrue);
      expect(parserClients.last.closed, isFalse);
      await adapter.disconnect();
      expect(parserClients.last.closed, isTrue);

      await adapter.dispose();
      await first.close();
      await second.close();
    },
  );

  test(
    'synchronous watch setup failure settles connect after retries',
    () async {
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: _ThrowingTransport(),
        contract: _Contract(),
        retryDelays: const [],
      );

      await adapter.connect('session').timeout(const Duration(seconds: 1));

      expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
      await adapter.dispose();
    },
  );

  test('synchronous admission setup failure clears submission state', () async {
    final watch = StreamController<List<int>>();
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: _QueueTransport([_watchResponse(watch.stream)]),
      contract: _ThrowingAdmissionContract(),
    );
    final connected = adapter.connect('session');
    _addBaseline(watch, sessionId: 'session');
    await connected;

    await adapter.start('first');
    await adapter.start('second');

    expect(controller.state.runPhase, RunPhase.outcomeUnknown);
    expect(controller.state.failure?.kind, ViewFailureKind.outcomeUnavailable);
    await adapter.dispose();
    await watch.close();
  });

  test('synchronous interrupt transport failure restores run phase', () async {
    final watch = StreamController<List<int>>();
    final delegate = _QueueTransport([
      _watchResponse(watch.stream),
      TransportResponse(
        statusCode: 202,
        headers: const {'content-type': 'application/json'},
        body: Stream.value(
          utf8.encode('{"session_id":"session","run_id":"run-1"}'),
        ),
      ),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: _InterruptThrowingTransport(delegate),
      contract: _Contract(),
    );
    final connected = adapter.connect('session');
    _addBaseline(
      watch,
      sessionId: 'session',
      runs: const [
        {'ID': 'run-1', 'Status': 'running'},
      ],
    );
    await connected;
    await adapter.start('start');

    await adapter.interrupt();

    expect(controller.state.runPhase, RunPhase.running);
    expect(controller.state.failure?.kind, ViewFailureKind.transient);
    await adapter.dispose();
    await watch.close();
  });

  test('stale admission body cannot mutate a replacement session', () async {
    final firstWatch = StreamController<List<int>>();
    final admissionBody = StreamController<List<int>>();
    final secondWatch = StreamController<List<int>>();
    final transport = _QueueTransport([
      _watchResponse(firstWatch.stream),
      TransportResponse(
        statusCode: 202,
        headers: const {'content-type': 'application/json'},
        body: admissionBody.stream,
      ),
      _watchResponse(secondWatch.stream),
    ]);
    final controller = AgentViewController();
    final adapter = EinoSessionAdapter(
      controller: controller,
      transport: transport,
      contract: _Contract(),
    );
    final firstConnect = adapter.connect('session');
    _addBaseline(firstWatch, sessionId: 'session');
    await firstConnect;
    final oldStart = adapter.start('old submission');
    await Future<void>.delayed(Duration.zero);

    final secondConnect = adapter.connect('other');
    _addBaseline(secondWatch, sessionId: 'other');
    await secondConnect;
    admissionBody.add(
      utf8.encode('{"session_id":"session","run_id":"old-run"}'),
    );
    await admissionBody.close();
    await oldStart;

    expect(adapter.sessionId, 'other');
    expect(controller.state.connectionPhase, ConnectionPhase.connected);
    expect(controller.state.runPhase, RunPhase.idle);
    expect(controller.state.failure, isNull);

    await adapter.dispose();
    await firstWatch.close();
    await secondWatch.close();
  });
}

TransportResponse _watchResponse(Stream<List<int>> body) => TransportResponse(
  statusCode: 200,
  headers: const {'content-type': 'text/event-stream'},
  body: body,
);

void _addBaseline(
  StreamController<List<int>> body, {
  required String sessionId,
  List<Object?> runs = const [],
}) {
  body.add(_sse(MessagesSnapshotEvent(messages: const [])));
  body.add(
    _sse(
      StateSnapshotEvent(
        snapshot: _watchState(sessionId: sessionId, runs: runs),
      ),
    ),
  );
}

List<int> _sse(BaseEvent event) =>
    utf8.encode('data: ${jsonEncode(event.toJson())}\n\n');

Map<String, Object?> _watchState({
  String sessionId = 'session',
  List<Object?> runs = const [],
}) => {
  'Watermark': {'StoreID': 'store', 'SessionID': sessionId, 'Revision': 1},
  'Exists': true,
  'OmittedOlderMessages': false,
  'Runs': runs,
  'Tools': <Object?>[],
  'Live': <Object?>[],
};

final class _Contract implements EinoSessionContract {
  @override
  RequestSpec admissionRequest(String sessionId, String newText) => RequestSpec(
    method: 'POST',
    uri: Uri.parse('https://example.invalid/sessions/$sessionId/runs'),
    headers: const {'content-type': 'application/json'},
    body: utf8.encode(jsonEncode({'message': newText})),
  );

  @override
  RunAdmission decodeAdmission(List<int> body) {
    final value = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    return RunAdmission(
      sessionId: value['session_id'] as String,
      runId: value['run_id'] as String,
    );
  }

  @override
  RequestSpec interruptRequest(String sessionId, String runId) => RequestSpec(
    method: 'POST',
    uri: Uri.parse(
      'https://example.invalid/sessions/$sessionId/runs/$runId/interrupt',
    ),
  );

  @override
  RequestSpec watchRequest(String sessionId) => RequestSpec(
    method: 'GET',
    uri: Uri.parse('https://example.invalid/sessions/$sessionId/watch'),
  );
}

final class _QueueTransport implements RequestTransport {
  _QueueTransport(List<TransportResponse> responses)
    : _responses = List.of(responses);

  final List<TransportResponse> _responses;
  final List<RequestSpec> requests = [];
  final List<_Operation> operations = [];

  @override
  RequestOperation open(RequestSpec request) {
    requests.add(request);
    final operation = _Operation(_responses.removeAt(0));
    operations.add(operation);
    return operation;
  }

  @override
  Future<void> dispose() async {}
}

final class _Operation implements RequestOperation {
  _Operation(TransportResponse response) : response = Future.value(response);

  @override
  final Future<TransportResponse> response;

  @override
  Future<void> abort() async {}
}

final class _ThrowingTransport implements RequestTransport {
  @override
  RequestOperation open(RequestSpec request) => throw StateError('open failed');

  @override
  Future<void> dispose() async {}
}

final class _InterruptThrowingTransport implements RequestTransport {
  _InterruptThrowingTransport(this.delegate);

  final RequestTransport delegate;

  @override
  RequestOperation open(RequestSpec request) {
    if (request.uri.path.endsWith('/interrupt')) {
      throw StateError('interrupt open failed');
    }
    return delegate.open(request);
  }

  @override
  Future<void> dispose() => delegate.dispose();
}

final class _ThrowingAdmissionContract extends _Contract {
  @override
  RequestSpec admissionRequest(String sessionId, String newText) =>
      throw StateError('admission request failed');
}

final class _TrackingParserClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnsupportedError('No parser network request expected');

  @override
  void close() {
    closed = true;
    super.close();
  }
}
