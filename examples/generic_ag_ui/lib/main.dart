import 'dart:async';

import 'package:ag_ui/ag_ui.dart' hide State;
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:ag_ui_widgets/ag_ui_widgets.dart';
import 'package:flutter/material.dart';

const _endpoint = String.fromEnvironment(
  'AG_UI_ENDPOINT',
  defaultValue: 'http://127.0.0.1:8080/generic/run',
);

void main() => runApp(const GenericExampleApp());

final class GenericExampleApp extends StatelessWidget {
  const GenericExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Generic AG-UI example',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    ),
    home: const _GenericHome(),
  );
}

final class _GenericHome extends StatefulWidget {
  const _GenericHome();

  @override
  State<_GenericHome> createState() => _GenericHomeState();
}

final class _GenericHomeState extends State<_GenericHome> {
  final AgentViewController _controller = AgentViewController();
  final List<Message> _canonicalHistory = [];
  final Map<String, _AssistantBuilder> _assistant = {};
  late final AgUiPostAdapter _adapter;
  late final RemoveViewStateListener _removeListener;
  var _turn = 0;

  @override
  void initState() {
    super.initState();
    _adapter = AgUiPostAdapter(
      controller: _controller,
      transport: HttpRequestTransport.owned(),
      endpoint: Uri.parse(_endpoint),
      onProtocolEvent: _recordProtocolEvent,
    );
    _removeListener = _controller.addListener((_) {
      if (mounted) setState(() {});
    });
  }

  void _recordProtocolEvent(BaseEvent event) {
    if (event is MessagesSnapshotEvent) {
      _canonicalHistory
        ..clear()
        ..addAll(event.messages);
    } else if (event is TextMessageStartEvent) {
      _assistant.putIfAbsent(event.messageId, _AssistantBuilder.new);
    } else if (event is TextMessageContentEvent) {
      _assistant.putIfAbsent(event.messageId, _AssistantBuilder.new).text +=
          event.delta;
    } else if (event is ToolCallStartEvent) {
      _assistant
          .putIfAbsent(
            event.parentMessageId ?? 'assistant-$_turn',
            _AssistantBuilder.new,
          )
          .tools[event.toolCallId] = _ToolBuilder(
        event.toolCallName,
      );
    } else if (event is ToolCallArgsEvent) {
      for (final assistant in _assistant.values) {
        final tool = assistant.tools[event.toolCallId];
        if (tool != null) tool.arguments += event.delta;
      }
    } else if (event is ToolCallResultEvent) {
      for (final entry in _assistant.entries.toList()) {
        if (entry.value.tools.containsKey(event.toolCallId)) {
          _commitAssistant(entry.key);
          break;
        }
      }
      _canonicalHistory.add(
        ToolMessage(
          id: event.messageId,
          toolCallId: event.toolCallId,
          content: event.content,
        ),
      );
    } else if (event is RunFinishedEvent) {
      for (final id in _assistant.keys.toList()) {
        _commitAssistant(id);
      }
    }
  }

  void _commitAssistant(String id) {
    final builder = _assistant.remove(id);
    if (builder == null) return;
    _canonicalHistory.removeWhere((message) => message.id == id);
    _canonicalHistory.add(
      AssistantMessage(
        id: id,
        content: builder.text.isEmpty ? null : builder.text,
        toolCalls: [
          for (final entry in builder.tools.entries)
            ToolCall(
              id: entry.key,
              function: FunctionCall(
                name: entry.value.name,
                arguments: entry.value.arguments,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit(String text) async {
    _turn += 1;
    _canonicalHistory.add(UserMessage(id: 'user-$_turn', content: text));
    await _adapter.start(
      SimpleRunAgentInput(
        threadId: 'generic-example',
        runId: 'run-$_turn',
        messages: List.unmodifiable(_canonicalHistory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Generic caller-owned history')),
      body: Column(
        children: [
          Expanded(
            child: TranscriptView(
              messages: state.messages,
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
            child: AgentInput(onSubmit: _submit, busy: _adapter.isBusy),
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

final class _AssistantBuilder {
  String text = '';
  final Map<String, _ToolBuilder> tools = {};
}

final class _ToolBuilder {
  _ToolBuilder(this.name);

  final String name;
  String arguments = '';
}
