import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:http/http.dart' as http;

import 'controller.dart';
import 'sse_request_session.dart';
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

  SseRequestSession? _session;
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
    SseRequestSession? session;
    final done = Completer<void>();
    var terminal = false;
    try {
      session = SseRequestSession.open(
        transport: transport,
        request: RequestSpec(
          method: 'POST',
          uri: endpoint,
          headers: {
            'accept': 'text/event-stream',
            'content-type': 'application/json',
            ...?headers?.call(),
          },
          body: encoded,
        ),
        limits: limits,
        parserClientFactory: _parserClientFactory,
      );
      _session = session;
      final response = await session.responseBefore(responseHeaderTimeout);
      if (response == null) return;
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
      session.listen(
        response,
        onData: (event) {
          if (!controller.isCurrent(generation) || terminal) return;
          try {
            onProtocolEvent?.call(event);
          } on Object {
            controller.fail(
              ViewFailureKind.hostCallbackFailed,
              generation: generation,
            );
            unawaited(session!.close());
            if (!done.isCompleted) done.complete();
            return;
          }
          controller.apply(event, generation: generation);
          if (event is RunFinishedEvent || event is RunErrorEvent) {
            terminal = true;
            if (!done.isCompleted) done.complete();
          }
        },
        onError: (_) {
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
      );
      await Future.any<void>([done.future, session.cancelled]);
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
      await session?.close();
      if (identical(_session, session)) _session = null;
      _busy = false;
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
    await _session?.close();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await transport.dispose();
  }
}
