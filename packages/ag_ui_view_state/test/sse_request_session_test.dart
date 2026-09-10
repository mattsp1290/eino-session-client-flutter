import 'dart:async';

import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('close cancels a request before response headers arrive', () async {
    final response = Completer<TransportResponse>();
    final operation = _Operation(response.future);
    final session = SseRequestSession.open(
      transport: _Transport(operation),
      request: _request,
      limits: ViewLimits(),
    );
    final pendingResponse = session.responseBefore(const Duration(seconds: 1));

    final firstClose = session.close();
    final secondClose = session.close();

    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
    expect(await pendingResponse, isNull);
    expect(operation.abortCount, 1);
  });

  test('close cancels streaming and releases parser resources once', () async {
    final body = StreamController<List<int>>();
    final parserClient = _TrackingParserClient();
    final operation = _Operation(
      Future.value(
        TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/event-stream'},
          body: body.stream,
        ),
      ),
    );
    final session = SseRequestSession.open(
      transport: _Transport(operation),
      request: _request,
      limits: ViewLimits(),
      parserClientFactory: () => parserClient,
    );
    final response = await session.responseBefore(const Duration(seconds: 1));
    session.listen(response!, onData: (_) {}, onError: (_) {}, onDone: () {});

    await session.close();
    await session.close();

    expect(parserClient.closed, isTrue);
    expect(operation.abortCount, 1);
    await body.close();
  });
}

final _request = RequestSpec(
  method: 'GET',
  uri: Uri.parse('https://example.invalid/events'),
);

final class _Transport implements RequestTransport {
  _Transport(this.operation);

  final RequestOperation operation;

  @override
  RequestOperation open(RequestSpec request) => operation;

  @override
  Future<void> dispose() async {}
}

final class _Operation implements RequestOperation {
  _Operation(this.response);

  @override
  final Future<TransportResponse> response;
  int abortCount = 0;

  @override
  Future<void> abort() async => abortCount += 1;
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
