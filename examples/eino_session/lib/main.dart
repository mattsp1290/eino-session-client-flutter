import 'dart:async';
import 'dart:convert';

import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:eino_session_client/eino_session_client.dart';
import 'package:flutter/material.dart';

const _server = String.fromEnvironment(
  'EINO_SERVER',
  defaultValue: 'http://127.0.0.1:8080',
);
const _session = String.fromEnvironment(
  'EINO_SESSION',
  defaultValue: 'example',
);

void main() => runApp(const EinoSessionExampleApp());

final class EinoSessionExampleApp extends StatelessWidget {
  const EinoSessionExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Eino session example',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    home: const _SessionHome(),
  );
}

final class _SessionHome extends StatefulWidget {
  const _SessionHome();

  @override
  State<_SessionHome> createState() => _SessionHomeState();
}

final class _SessionHomeState extends State<_SessionHome> {
  final AgentViewController _controller = AgentViewController();
  late final EinoSessionAdapter _adapter;
  late final RemoveViewStateListener _removeListener;

  @override
  void initState() {
    super.initState();
    _adapter = EinoSessionAdapter(
      controller: _controller,
      transport: HttpRequestTransport.owned(),
      contract: _ExampleContract(Uri.parse(_server)),
    );
    _removeListener = _controller.addListener((_) {
      if (mounted) setState(() {});
    });
    unawaited(_adapter.connect(_session));
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final busy =
        state.runPhase == RunPhase.submitting ||
        state.runPhase == RunPhase.running ||
        state.runPhase == RunPhase.interrupting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eino server-owned session'),
        actions: [
          IconButton(
            tooltip: 'Reconnect session',
            onPressed: () => unawaited(_adapter.reconnect()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TranscriptView(
              messages: state.messages,
              omittedOlderMessages: state.omittedOlderMessages,
              isStale: state.isStale,
            ),
          ),
          ToolActivityList(tools: state.tools, runPhase: state.runPhase),
          if (state.failure case final failure?)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(failure.safeMessage),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: AgentInput(
              onSubmit: _adapter.start,
              onInterrupt: busy ? _adapter.interrupt : null,
              busy: busy,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _removeListener();
    unawaited(_adapter.dispose());
    unawaited(_controller.dispose());
    super.dispose();
  }
}

final class _ExampleContract implements EinoSessionContract {
  const _ExampleContract(this.baseUri);

  final Uri baseUri;

  Uri _route(String path) => baseUri.resolve(path);

  @override
  RequestSpec watchRequest(String sessionId) => RequestSpec(
    method: 'GET',
    uri: _route('/sessions/${Uri.encodeComponent(sessionId)}/events'),
    headers: {'accept': 'text/event-stream', 'x-fixture-session': sessionId},
  );

  @override
  RequestSpec admissionRequest(String sessionId, String newText) => RequestSpec(
    method: 'POST',
    uri: _route('/sessions/${Uri.encodeComponent(sessionId)}/runs'),
    headers: {
      'content-type': 'application/json',
      'x-fixture-session': sessionId,
    },
    body: utf8.encode(jsonEncode({'message': newText})),
  );

  @override
  RunAdmission decodeAdmission(List<int> body) {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic> ||
        decoded['session_id'] is! String ||
        decoded['run_id'] is! String) {
      throw const FormatException('Invalid admission acknowledgement');
    }
    return RunAdmission(
      sessionId: decoded['session_id'] as String,
      runId: decoded['run_id'] as String,
    );
  }

  @override
  RequestSpec interruptRequest(String sessionId, String runId) => RequestSpec(
    method: 'POST',
    uri: _route('/runs/${Uri.encodeComponent(runId)}/interrupt'),
  );
}
