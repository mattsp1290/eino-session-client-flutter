import 'dart:async';

final class RequestSpec {
  RequestSpec({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable(headers),
       body = List.unmodifiable(body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

final class TransportResponse {
  TransportResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.body,
  }) : headers = Map.unmodifiable(headers);

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

abstract interface class RequestOperation {
  Future<TransportResponse> get response;
  Future<void> abort();
}

abstract interface class RequestTransport {
  RequestOperation open(RequestSpec request);
  Future<void> dispose();
}
