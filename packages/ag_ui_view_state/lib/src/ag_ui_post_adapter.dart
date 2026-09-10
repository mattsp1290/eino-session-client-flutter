import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:http/http.dart' as http;

import 'controller.dart';
import 'transport.dart';
import 'view_state.dart';

typedef ProtocolEventCallback = void Function(BaseEvent event);
typedef RequestHeaders = Map<String, String> Function();

final class AgUiPostAdapter {
  AgUiPostAdapter({
    required this.controller,
    required this.transport,
    required this.endpoint,
    this.headers,
    this.onProtocolEvent,
    this.responseHeaderTimeout = const Duration(seconds: 15),
    ViewLimits? limits,
    http.Client Function()? parserClientFactory,
  }) : limits = limits ?? ViewLimits(),
       _parserClientFactory = parserClientFactory ?? http.Client.new {
    if (responseHeaderTimeout <= Duration.zero) {
      throw ArgumentError.value(responseHeaderTimeout, 'responseHeaderTimeout');
    }
  }

  final AgentViewController controller;
  final RequestTransport transport;
  final Uri endpoint;
  final RequestHeaders? headers;
  final ProtocolEventCallback? onProtocolEvent;
  final Duration responseHeaderTimeout;
  final ViewLimits limits;
  final http.Client Function() _parserClientFactory;

  RequestOperation? _operation;
  StreamSubscription<BaseEvent>? _subscription;
  bool _busy = false;
  bool _disposed = false;

  bool get isBusy => _busy;

  Future<void> start(SimpleRunAgentInput input) async {
    if (_disposed) throw StateError('Adapter is disposed');
    if (_busy) throw StateError('Adapter is busy');

    final encoded = utf8.encode(
      jsonEncode(const Encoder().encodeRunAgentInput(input)),
    );
    if (encoded.length > limits.maxEncodedInputBytes) {
      final generation = controller.beginRequest();
      controller.fail(ViewFailureKind.capacityExceeded, generation: generation);
      return;
    }

    _busy = true;
    final generation = controller.beginRequest();
    final operation = transport.open(
      RequestSpec(
        method: 'POST',
        uri: endpoint,
        headers: {
          'accept': 'text/event-stream',
          'content-type': 'application/json',
          ...?headers?.call(),
        },
        body: encoded,
      ),
    );
    _operation = operation;
    http.Client? parserHttpClient;
    SseClient? sseClient;
    var terminal = false;
    try {
      final response = await _responseBeforeDeadline(operation);
      if (!controller.isCurrent(generation)) return;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        controller.fail(
          _failureForStatus(response.statusCode),
          generation: generation,
        );
        return;
      }
      final contentType = response
          .header('content-type')
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != 'text/event-stream') {
        controller.fail(
          ViewFailureKind.incompatibleContract,
          generation: generation,
        );
        return;
      }

      controller.setConnection(
        ConnectionPhase.connected,
        generation: generation,
      );
      parserHttpClient = _parserClientFactory();
      sseClient = SseClient(
        httpClient: parserHttpClient,
        maxDataCodeUnits: limits.maxSseDataCodeUnits,
        maxLineCodeUnits: limits.maxSseLineCodeUnits,
      );
      final events =
          EventStreamAdapter(maxDataCodeUnits: limits.maxSseDataCodeUnits)
              .fromSseStream(
                sseClient.parseStream(response.body, headers: response.headers),
                skipInvalidEvents: false,
              );
      final done = Completer<void>();
      _subscription = events.listen(
        (event) {
          if (!controller.isCurrent(generation) || terminal) return;
          try {
            onProtocolEvent?.call(event);
          } on Object {
            controller.fail(
              ViewFailureKind.hostCallbackFailed,
              generation: generation,
            );
            unawaited(operation.abort());
            if (!done.isCompleted) done.complete();
            return;
          }
          controller.apply(event, generation: generation);
          if (event is RunFinishedEvent || event is RunErrorEvent) {
            terminal = true;
            if (!done.isCompleted) done.complete();
          }
        },
        onError: (Object _) {
          if (controller.isCurrent(generation)) {
            controller.fail(
              ViewFailureKind.protocolViolation,
              generation: generation,
            );
          }
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
      if (controller.isCurrent(generation) &&
          !terminal &&
          controller.state.failure == null) {
        controller.markIncomplete(generation: generation);
      } else if (controller.isCurrent(generation) && terminal) {
        controller.setConnection(
          ConnectionPhase.disconnected,
          generation: generation,
        );
      }
    } on TimeoutException {
      if (controller.isCurrent(generation)) {
        controller.fail(
          ViewFailureKind.transient,
          generation: generation,
          retryable: false,
        );
      }
    } on Object {
      if (controller.isCurrent(generation) &&
          controller.state.failure == null) {
        controller.fail(
          ViewFailureKind.transient,
          generation: generation,
          retryable: false,
        );
      }
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      await sseClient?.close();
      parserHttpClient?.close();
      await operation.abort();
      if (identical(_operation, operation)) _operation = null;
      _busy = false;
    }
  }

  Future<TransportResponse> _responseBeforeDeadline(
    RequestOperation operation,
  ) async {
    try {
      return await operation.response.timeout(responseHeaderTimeout);
    } on TimeoutException {
      await operation.abort();
      rethrow;
    }
  }

  ViewFailureKind _failureForStatus(int status) => switch (status) {
    401 => ViewFailureKind.unauthorized,
    403 => ViewFailureKind.forbidden,
    404 => ViewFailureKind.unavailable,
    409 => ViewFailureKind.conflict,
    413 => ViewFailureKind.capacityExceeded,
    _ => ViewFailureKind.transient,
  };

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _operation?.abort();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await transport.dispose();
  }
}
