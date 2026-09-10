import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';

import 'view_state.dart';

final class ViewProjectionException implements Exception {
  const ViewProjectionException(this.kind);

  final ViewFailureKind kind;
}

final class EventViewReducer {
  EventViewReducer({ViewLimits? limits}) : limits = limits ?? ViewLimits();

  final ViewLimits limits;
  String? _threadId;
  String? _runId;

  AgentViewState reduce(AgentViewState state, BaseEvent event) {
    if (_isAttributed(event)) return state;

    final next = switch (event) {
      MessagesSnapshotEvent() => _snapshot(state, event),
      TextMessageStartEvent() => _textStart(state, event),
      TextMessageContentEvent() => _textContent(state, event),
      TextMessageEndEvent() => _textEnd(state, event),
      TextMessageChunkEvent() => _textChunk(state, event),
      ToolCallStartEvent() => _toolStart(state, event),
      ToolCallArgsEvent() => _toolArgs(state, event),
      ToolCallEndEvent() => _toolEnd(state, event),
      ToolCallChunkEvent() => _toolChunk(state, event),
      ToolCallResultEvent() => _toolResult(state, event),
      RunStartedEvent() => _runStarted(state, event),
      RunFinishedEvent() => _runFinished(state, event),
      RunErrorEvent() => _runError(state),
      _ => state,
    };
    _checkBounds(next);
    return next;
  }

  void resetIdentity() {
    _threadId = null;
    _runId = null;
  }

  bool _isAttributed(BaseEvent event) => switch (event) {
    TextMessageStartEvent(:final subagentRunId) ||
    TextMessageContentEvent(:final subagentRunId) ||
    TextMessageEndEvent(:final subagentRunId) ||
    TextMessageChunkEvent(:final subagentRunId) ||
    ToolCallStartEvent(:final subagentRunId) ||
    ToolCallArgsEvent(:final subagentRunId) ||
    ToolCallEndEvent(:final subagentRunId) ||
    ToolCallChunkEvent(:final subagentRunId) ||
    ToolCallResultEvent(:final subagentRunId) => subagentRunId != null,
    SubagentStartedEvent() ||
    SubagentFinishedEvent() ||
    SubagentErrorEvent() => true,
    _ => false,
  };

  AgentViewState _snapshot(AgentViewState state, MessagesSnapshotEvent event) {
    final messages = <MessageView>[];
    final tools = <ToolActivityView>[];
    final messageIds = <String>{};
    final toolIds = <String>{};
    for (final message in event.messages) {
      if (message.subagentRunId != null) continue;
      final id = message.id;
      if (id == null || id.isEmpty) continue;
      if (!messageIds.add(id)) {
        throw const ViewProjectionException(ViewFailureKind.protocolViolation);
      }
      if (message case UserMessage(:final content)) {
        if (content != null) {
          messages.add(
            MessageView(id: id, role: ViewMessageRole.user, text: content),
          );
        }
      } else if (message case AssistantMessage(
        :final content,
        :final toolCalls,
      )) {
        if (content != null) {
          messages.add(
            MessageView(id: id, role: ViewMessageRole.assistant, text: content),
          );
        }
        for (final call in toolCalls ?? const <ToolCall>[]) {
          if (!toolIds.add(call.id)) {
            throw const ViewProjectionException(
              ViewFailureKind.protocolViolation,
            );
          }
          tools.add(
            ToolActivityView(
              id: call.id,
              name: call.function.name,
              parentMessageId: id,
              phase: ToolActivityPhase.awaitingResult,
            ),
          );
        }
      } else if (message case ToolMessage(:final toolCallId)) {
        final index = tools.indexWhere((tool) => tool.id == toolCallId);
        if (index >= 0) {
          tools[index] = tools[index].copyWith(
            phase: ToolActivityPhase.resultObserved,
          );
        } else if (toolIds.add(toolCallId)) {
          tools.add(
            ToolActivityView(
              id: toolCallId,
              name: 'Tool',
              phase: ToolActivityPhase.resultObserved,
            ),
          );
        }
      }
    }
    return state.copyWith(messages: messages, tools: tools, failure: null);
  }

  AgentViewState _textStart(AgentViewState state, TextMessageStartEvent event) {
    final role = _role(event.role);
    if (role == null) return state;
    final messages = state.messages.toList();
    final index = messages.indexWhere(
      (message) => message.id == event.messageId,
    );
    if (index >= 0) {
      if (messages[index].role != role) {
        throw const ViewProjectionException(ViewFailureKind.protocolViolation);
      }
      messages[index] = messages[index].copyWith(isStreaming: true);
    } else {
      messages.add(
        MessageView(
          id: event.messageId,
          role: role,
          text: '',
          isStreaming: true,
        ),
      );
    }
    return state.copyWith(messages: messages);
  }

  AgentViewState _textContent(
    AgentViewState state,
    TextMessageContentEvent event,
  ) {
    final messages = state.messages.toList();
    final index = messages.indexWhere(
      (message) => message.id == event.messageId,
    );
    if (index < 0) {
      messages.add(
        MessageView(
          id: event.messageId,
          role: ViewMessageRole.assistant,
          text: event.delta,
          isStreaming: true,
        ),
      );
    } else {
      messages[index] = messages[index].copyWith(
        text: '${messages[index].text}${event.delta}',
        isStreaming: true,
      );
    }
    return state.copyWith(messages: messages);
  }

  AgentViewState _textEnd(AgentViewState state, TextMessageEndEvent event) {
    final messages = state.messages.toList();
    final index = messages.indexWhere(
      (message) => message.id == event.messageId,
    );
    if (index < 0) {
      throw const ViewProjectionException(ViewFailureKind.protocolViolation);
    }
    messages[index] = messages[index].copyWith(isStreaming: false);
    return state.copyWith(messages: messages);
  }

  AgentViewState _textChunk(AgentViewState state, TextMessageChunkEvent event) {
    final id = event.messageId ?? _uniqueStreamingMessage(state);
    if (id == null) {
      throw const ViewProjectionException(ViewFailureKind.protocolViolation);
    }
    var next = state;
    if (!state.messages.any((message) => message.id == id)) {
      final role = _role(event.role ?? TextMessageRole.assistant);
      if (role == null) return state;
      next = _textStart(
        state,
        TextMessageStartEvent(
          messageId: id,
          role: event.role ?? TextMessageRole.assistant,
        ),
      );
    }
    if (event.delta != null) {
      next = _textContent(
        next,
        TextMessageContentEvent(messageId: id, delta: event.delta!),
      );
    }
    return next;
  }

  AgentViewState _toolStart(AgentViewState state, ToolCallStartEvent event) {
    final tools = state.tools.toList();
    final index = tools.indexWhere((tool) => tool.id == event.toolCallId);
    if (index >= 0) {
      final existing = tools[index];
      if (existing.name != 'Tool' && existing.name != event.toolCallName) {
        throw const ViewProjectionException(ViewFailureKind.protocolViolation);
      }
      tools[index] = existing.copyWith(
        name: event.toolCallName,
        parentMessageId: event.parentMessageId,
      );
    } else {
      tools.add(
        ToolActivityView(
          id: event.toolCallId,
          name: event.toolCallName,
          parentMessageId: event.parentMessageId,
          phase: ToolActivityPhase.receivingArguments,
        ),
      );
    }
    return state.copyWith(tools: tools);
  }

  AgentViewState _toolArgs(AgentViewState state, ToolCallArgsEvent event) =>
      _setToolPhase(
        state,
        event.toolCallId,
        ToolActivityPhase.receivingArguments,
      );

  AgentViewState _toolEnd(AgentViewState state, ToolCallEndEvent event) =>
      _setToolPhase(state, event.toolCallId, ToolActivityPhase.awaitingResult);

  AgentViewState _toolResult(AgentViewState state, ToolCallResultEvent event) =>
      _setToolPhase(
        state,
        event.toolCallId,
        ToolActivityPhase.resultObserved,
        create: true,
      );

  AgentViewState _toolChunk(AgentViewState state, ToolCallChunkEvent event) {
    final id = event.toolCallId ?? _uniqueActiveTool(state);
    if (id == null) {
      throw const ViewProjectionException(ViewFailureKind.protocolViolation);
    }
    var next = state;
    if (!state.tools.any((tool) => tool.id == id)) {
      final name = event.toolCallName;
      if (name == null) {
        throw const ViewProjectionException(ViewFailureKind.protocolViolation);
      }
      next = _toolStart(
        state,
        ToolCallStartEvent(
          toolCallId: id,
          toolCallName: name,
          parentMessageId: event.parentMessageId,
        ),
      );
    }
    return event.delta == null
        ? next
        : _setToolPhase(next, id, ToolActivityPhase.receivingArguments);
  }

  AgentViewState _setToolPhase(
    AgentViewState state,
    String id,
    ToolActivityPhase phase, {
    bool create = false,
  }) {
    final tools = state.tools.toList();
    final index = tools.indexWhere((tool) => tool.id == id);
    if (index < 0) {
      if (!create) {
        throw const ViewProjectionException(ViewFailureKind.protocolViolation);
      }
      tools.add(ToolActivityView(id: id, name: 'Tool', phase: phase));
    } else {
      tools[index] = tools[index].copyWith(phase: phase);
    }
    return state.copyWith(tools: tools);
  }

  AgentViewState _runStarted(AgentViewState state, RunStartedEvent event) {
    if ((_threadId != null && _threadId != event.threadId) ||
        (_runId != null && _runId != event.runId)) {
      throw const ViewProjectionException(ViewFailureKind.protocolViolation);
    }
    _threadId = event.threadId;
    _runId = event.runId;
    return state.copyWith(
      connectionPhase: ConnectionPhase.connected,
      runPhase: RunPhase.running,
      failure: null,
      status: null,
    );
  }

  AgentViewState _runFinished(AgentViewState state, RunFinishedEvent event) {
    if ((_threadId != null && _threadId != event.threadId) ||
        (_runId != null && _runId != event.runId)) {
      throw const ViewProjectionException(ViewFailureKind.protocolViolation);
    }
    final paused = event.outcome is RunFinishedInterruptOutcome;
    return state.copyWith(
      runPhase: paused ? RunPhase.paused : RunPhase.completed,
      status: paused ? 'Waiting for host action' : null,
      tools: _resolveUnfinished(state.tools),
    );
  }

  AgentViewState _runError(AgentViewState state) => state.copyWith(
    runPhase: RunPhase.failed,
    failure: const ViewFailure(ViewFailureKind.protocolViolation),
    tools: _resolveUnfinished(state.tools),
  );

  List<ToolActivityView> _resolveUnfinished(Iterable<ToolActivityView> tools) =>
      [
        for (final tool in tools)
          switch (tool.phase) {
            ToolActivityPhase.completed ||
            ToolActivityPhase.failed ||
            ToolActivityPhase.interrupted ||
            ToolActivityPhase.resultObserved => tool,
            _ => tool.copyWith(phase: ToolActivityPhase.unresolved),
          },
      ];

  ViewMessageRole? _role(TextMessageRole role) => switch (role) {
    TextMessageRole.user => ViewMessageRole.user,
    TextMessageRole.assistant => ViewMessageRole.assistant,
    _ => null,
  };

  String? _uniqueStreamingMessage(AgentViewState state) {
    final active = state.messages.where((message) => message.isStreaming);
    return active.length == 1 ? active.single.id : null;
  }

  String? _uniqueActiveTool(AgentViewState state) {
    final active = state.tools.where(
      (tool) =>
          tool.phase == ToolActivityPhase.receivingArguments ||
          tool.phase == ToolActivityPhase.awaitingResult,
    );
    return active.length == 1 ? active.single.id : null;
  }

  void _checkBounds(AgentViewState state) {
    if (state.messages.length > limits.maxMessages ||
        state.tools.length > limits.maxTools) {
      throw const ViewProjectionException(ViewFailureKind.capacityExceeded);
    }
    var total = 0;
    for (final message in state.messages) {
      final bytes = utf8.encode(message.text).length;
      if (bytes > limits.maxMessageBytes) {
        throw const ViewProjectionException(ViewFailureKind.capacityExceeded);
      }
      total += bytes + utf8.encode(message.id).length + 16;
    }
    for (final tool in state.tools) {
      total += utf8.encode(tool.id).length + utf8.encode(tool.name).length + 24;
    }
    if (total > limits.maxDisplayBytes) {
      throw const ViewProjectionException(ViewFailureKind.capacityExceeded);
    }
  }
}
