import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'generic adapter projects terminal event and aborts its operation',
    () async {
      final events = [
        RunStartedEvent(threadId: 'thread', runId: 'run'),
        const TextMessageContentEvent(messageId: 'message', delta: 'hello'),
        const RunFinishedEvent(threadId: 'thread', runId: 'run'),
      ];
      final body = Stream<List<int>>.fromIterable([
        for (final event in events)
          utf8.encode('data: ${jsonEncode(event.toJson())}\n\n'),
      ]);
      final transport = _FakeTransport(
        TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
          body: body,
        ),
      );
      final controller = AgentViewController();
      final observed = <BaseEvent>[];
      final adapter = AgUiPostAdapter(
        controller: controller,
        transport: transport,
        endpoint: Uri.parse('https://example.invalid/run'),
        onProtocolEvent: observed.add,
      );

      await adapter.start(const SimpleRunAgentInput());

      expect(observed, hasLength(3));
      expect(controller.state.messages.single.text, 'hello');
      expect(controller.state.runPhase, RunPhase.completed);
      expect(transport.operation.abortCount, 1);
      expect(
        utf8.decode(transport.lastRequest!.body),
        contains('"messages":[]'),
      );
    },
  );

  test(
    'host callback failure aborts without retaining exception content',
    () async {
      final event = RunStartedEvent(threadId: 'thread', runId: 'run');
      final transport = _FakeTransport(
        TransportResponse(
          statusCode: 200,
          headers: const {'content-type': 'text/event-stream'},
          body: Stream.value(
            utf8.encode('data: ${jsonEncode(event.toJson())}\n\n'),
          ),
        ),
      );
      final controller = AgentViewController();
      final adapter = AgUiPostAdapter(
        controller: controller,
        transport: transport,
        endpoint: Uri.parse('https://example.invalid/run'),
        onProtocolEvent: (_) => throw StateError('private canary'),
      );

      await adapter.start(const SimpleRunAgentInput());

      expect(
        controller.state.failure?.kind,
        ViewFailureKind.hostCallbackFailed,
      );
      expect(
        controller.state.toSafeJson().toString(),
        isNot(contains('canary')),
      );
    },
  );

  for (final cancellation in ['disconnect', 'dispose']) {
    test(
      '$cancellation settles an active start and releases parser state',
      () async {
        final body = StreamController<List<int>>();
        final parserClient = _TrackingParserClient();
        final transport = _FakeTransport(
          TransportResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/event-stream'},
            body: body.stream,
          ),
        );
        final adapter = AgUiPostAdapter(
          controller: AgentViewController(),
          transport: transport,
          endpoint: Uri.parse('https://example.invalid/run'),
          parserClientFactory: () => parserClient,
        );

        final started = adapter.start(const SimpleRunAgentInput());
        await Future<void>.delayed(Duration.zero);
        expect(adapter.isBusy, isTrue);

        if (cancellation == 'disconnect') {
          await adapter.disconnect();
        } else {
          await adapter.dispose();
        }
        await started.timeout(const Duration(seconds: 1));

        expect(adapter.isBusy, isFalse);
        expect(parserClient.closed, isTrue);
        await body.close();
        if (cancellation == 'disconnect') await adapter.dispose();
      },
    );
  }

  test('synchronous transport failure clears busy and permits retry', () async {
    final controller = AgentViewController();
    final adapter = AgUiPostAdapter(
      controller: controller,
      transport: _ThrowingTransport(),
      endpoint: Uri.parse('https://example.invalid/run'),
    );

    await adapter.start(const SimpleRunAgentInput());

    expect(adapter.isBusy, isFalse);
    expect(controller.state.failure?.kind, ViewFailureKind.transient);
    await adapter.start(const SimpleRunAgentInput());
    expect(adapter.isBusy, isFalse);
  });
}

final class _FakeTransport implements RequestTransport {
  _FakeTransport(this.value) : operation = _FakeOperation(value);

  final TransportResponse value;
  final _FakeOperation operation;
  RequestSpec? lastRequest;

  @override
  RequestOperation open(RequestSpec request) {
    lastRequest = request;
    return operation;
  }

  @override
  Future<void> dispose() async {}
}

final class _FakeOperation implements RequestOperation {
  _FakeOperation(TransportResponse value) : response = Future.value(value);

  @override
  final Future<TransportResponse> response;
  int abortCount = 0;

  @override
  Future<void> abort() async => abortCount += 1;
}

final class _ThrowingTransport implements RequestTransport {
  @override
  RequestOperation open(RequestSpec request) => throw StateError('open failed');

  @override
  Future<void> dispose() async {}
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
