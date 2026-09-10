import 'dart:convert';

import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const server = String.fromEnvironment('EINO_SERVER');
const session = String.fromEnvironment(
  'EINO_TEST_SESSION',
  defaultValue: 'browser-session',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fresh watch, reconnect, second turn, and interrupt use Go runtime',
    (tester) async {
      expect(server, isNotEmpty);
      final controller = AgentViewController();
      final adapter = EinoSessionAdapter(
        controller: controller,
        transport: HttpRequestTransport.owned(),
        contract: _Contract(Uri.parse(server)),
      );
      await adapter.connect(session);
      await adapter.start('one new browser message');
      for (
        var attempt = 0;
        attempt < 50 && controller.state.runPhase != RunPhase.completed;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        controller.state.runPhase,
        RunPhase.completed,
        reason: controller.state.failure?.kind.name,
      );
      expect(
        controller.state.messages.any(
          (message) => message.text == 'one new browser message',
        ),
        isTrue,
      );
      await adapter.start('please pause this run');
      for (
        var attempt = 0;
        attempt < 50 && controller.state.runPhase != RunPhase.running;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(controller.state.runPhase, RunPhase.running);
      await adapter.disconnect();
      expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
      await adapter.reconnect();
      expect(controller.state.connectionPhase, ConnectionPhase.connected);
      expect(
        controller.state.messages.any(
          (message) => message.text == 'Paused live prefix',
        ),
        isTrue,
      );
      await adapter.interrupt();
      for (
        var attempt = 0;
        attempt < 50 && controller.state.runPhase != RunPhase.interrupted;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(controller.state.runPhase, RunPhase.interrupted);
      await adapter.dispose();
      await controller.dispose();
    },
  );
}

final class _Contract implements EinoSessionContract {
  const _Contract(this.base);

  final Uri base;

  @override
  RequestSpec watchRequest(String sessionId) => RequestSpec(
    method: 'GET',
    uri: base.resolve('/sessions/${Uri.encodeComponent(sessionId)}/events'),
    headers: {'x-fixture-session': sessionId},
  );

  @override
  RequestSpec admissionRequest(String sessionId, String newText) => RequestSpec(
    method: 'POST',
    uri: base.resolve('/sessions/${Uri.encodeComponent(sessionId)}/runs'),
    headers: {
      'content-type': 'application/json',
      'x-fixture-session': sessionId,
    },
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
    uri: base.resolve('/runs/${Uri.encodeComponent(runId)}/interrupt'),
  );
}
