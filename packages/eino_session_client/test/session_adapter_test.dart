import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:eino_session_client/eino_session_client.dart';
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

    await adapter.dispose();
    await first.close();
    await second.close();
  });
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
