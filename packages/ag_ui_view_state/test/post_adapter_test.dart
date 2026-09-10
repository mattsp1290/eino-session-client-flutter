import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
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
