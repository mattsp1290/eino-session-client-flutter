import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:http/http.dart' as http;

import 'transport.dart';
import 'view_state.dart';

/// Owns one cancellable SSE request and all resources used to decode it.
final class SseRequestSession {
  SseRequestSession.open({
    required RequestTransport transport,
    required RequestSpec request,
    required ViewLimits limits,
    http.Client Function()? parserClientFactory,
  }) : _operation = transport.open(request),
       _limits = limits,
       _parserClientFactory = parserClientFactory ?? http.Client.new;

  final RequestOperation _operation;
  final ViewLimits _limits;
  final http.Client Function() _parserClientFactory;
  final Completer<void> _cancelled = Completer<void>();

  // The subscription is cancelled by the idempotent [close] lifecycle.
  // ignore: cancel_subscriptions
  StreamSubscription<BaseEvent>? _subscription;
  http.Client? _parserHttpClient;
  SseClient? _sseClient;
  Future<void>? _closeFuture;

  Future<void> get cancelled => _cancelled.future;

  Future<TransportResponse?> responseBefore(Duration timeout) async {
    try {
      return await Future.any<TransportResponse?>([
        _operation.response.timeout(timeout),
        cancelled.then<TransportResponse?>((_) => null),
      ]);
    } on TimeoutException {
      await close();
      rethrow;
    }
  }

  StreamSubscription<BaseEvent> listen(
    TransportResponse response, {
    required void Function(BaseEvent event) onData,
    required void Function(Object error) onError,
    required void Function() onDone,
    bool cancelOnError = true,
  }) {
    if (_closeFuture != null) throw StateError('SSE session is closed');
    if (_subscription != null) {
      throw StateError('SSE session already has a listener');
    }
    final parserHttpClient = _parserClientFactory();
    final sseClient = SseClient(
      httpClient: parserHttpClient,
      maxDataCodeUnits: _limits.maxSseDataCodeUnits,
      maxLineCodeUnits: _limits.maxSseLineCodeUnits,
    );
    _parserHttpClient = parserHttpClient;
    _sseClient = sseClient;
    final events =
        EventStreamAdapter(maxDataCodeUnits: _limits.maxSseDataCodeUnits)
            .fromSseStream(
              sseClient.parseStream(response.body, headers: response.headers),
              skipInvalidEvents: false,
            );
    return _subscription = events.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (!_cancelled.isCompleted) _cancelled.complete();
    final subscription = _subscription;
    final sseClient = _sseClient;
    final parserHttpClient = _parserHttpClient;
    _subscription = null;
    _sseClient = null;
    _parserHttpClient = null;
    await subscription?.cancel();
    await sseClient?.close();
    parserHttpClient?.close();
    await _operation.abort();
  }
}
