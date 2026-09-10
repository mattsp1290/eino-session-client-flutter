import 'dart:async';

import 'package:http/http.dart' as http;

import 'transport.dart';

final class HttpRequestTransport implements RequestTransport {
  HttpRequestTransport(http.Client client)
    : _client = client,
      _ownsClient = false;

  HttpRequestTransport.owned([http.Client Function()? factory])
    : _client = (factory ?? http.Client.new)(),
      _ownsClient = true;

  final http.Client _client;
  final bool _ownsClient;
  bool _disposed = false;

  @override
  RequestOperation open(RequestSpec request) {
    if (_disposed) throw StateError('Transport is disposed');
    final abortCompleter = Completer<void>();
    final httpRequest =
        http.AbortableRequest(
            request.method,
            request.uri,
            abortTrigger: abortCompleter.future,
          )
          ..headers.addAll(request.headers)
          ..bodyBytes = request.body;
    final response = _client
        .send(httpRequest)
        .then(
          (value) => TransportResponse(
            statusCode: value.statusCode,
            headers: value.headers,
            body: value.stream,
          ),
        );
    return _HttpRequestOperation(response, abortCompleter);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}

final class _HttpRequestOperation implements RequestOperation {
  _HttpRequestOperation(this.response, this._abortCompleter);

  @override
  final Future<TransportResponse> response;
  final Completer<void> _abortCompleter;

  @override
  Future<void> abort() async {
    if (!_abortCompleter.isCompleted) _abortCompleter.complete();
  }
}
