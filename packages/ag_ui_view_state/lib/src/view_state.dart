import 'dart:collection';

enum ConnectionPhase {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
  disposed,
}

enum RunPhase {
  idle,
  submitting,
  running,
  interrupting,
  completed,
  failed,
  paused,
  interrupted,
  outcomeUnknown,
}

enum ViewMessageRole { user, assistant }

enum ToolActivityPhase {
  receivingArguments,
  awaitingResult,
  resultObserved,
  running,
  completed,
  failed,
  interrupted,
  unresolved,
}

enum ViewFailureKind {
  capacityExceeded,
  protocolViolation,
  incompatibleContract,
  unauthorized,
  forbidden,
  unavailable,
  conflict,
  transient,
  hostCallbackFailed,
  incomplete,
  outcomeUnavailable,
}

final class ViewFailure {
  const ViewFailure(this.kind, {this.retryable = false});

  final ViewFailureKind kind;
  final bool retryable;

  String get safeMessage => switch (kind) {
    ViewFailureKind.capacityExceeded => 'Response exceeds display limits',
    ViewFailureKind.protocolViolation => 'The response was not valid',
    ViewFailureKind.incompatibleContract =>
      'The server response is not supported',
    ViewFailureKind.unauthorized => 'Authentication is required',
    ViewFailureKind.forbidden => 'Access is forbidden',
    ViewFailureKind.unavailable => 'The session is unavailable',
    ViewFailureKind.conflict => 'The session is busy',
    ViewFailureKind.transient => 'The connection was interrupted',
    ViewFailureKind.hostCallbackFailed => 'The host callback failed',
    ViewFailureKind.incomplete => 'The response ended before completion',
    ViewFailureKind.outcomeUnavailable =>
      'The run outcome is no longer available',
  };
}

final class ViewLimits {
  ViewLimits({
    this.maxMessages = 100,
    this.maxTools = 200,
    this.maxDisplayBytes = 256 * 1024,
    this.maxMessageBytes = 64 * 1024,
    this.maxSseDataCodeUnits = 1048576,
    this.maxSseLineCodeUnits = 1048583,
    this.maxSubmissionBytes = 64 * 1024,
    this.maxEncodedInputBytes = 2 * 1024 * 1024,
  }) {
    if (maxMessages <= 0 ||
        maxTools <= 0 ||
        maxDisplayBytes <= 0 ||
        maxMessageBytes <= 0 ||
        maxSseDataCodeUnits <= 0 ||
        maxSseLineCodeUnits <= 0 ||
        maxSubmissionBytes <= 0 ||
        maxEncodedInputBytes <= 0) {
      throw ArgumentError('All view limits must be positive');
    }
  }

  final int maxMessages;
  final int maxTools;
  final int maxDisplayBytes;
  final int maxMessageBytes;
  final int maxSseDataCodeUnits;
  final int maxSseLineCodeUnits;
  final int maxSubmissionBytes;
  final int maxEncodedInputBytes;
}

final class MessageView {
  const MessageView({
    required this.id,
    required this.role,
    required this.text,
    this.isStreaming = false,
    this.liveUnavailable = false,
  });

  final String id;
  final ViewMessageRole role;
  final String text;
  final bool isStreaming;
  final bool liveUnavailable;

  MessageView copyWith({
    String? text,
    bool? isStreaming,
    bool? liveUnavailable,
  }) => MessageView(
    id: id,
    role: role,
    text: text ?? this.text,
    isStreaming: isStreaming ?? this.isStreaming,
    liveUnavailable: liveUnavailable ?? this.liveUnavailable,
  );
}

final class ToolActivityView {
  const ToolActivityView({
    required this.id,
    required this.name,
    required this.phase,
    this.parentMessageId,
  });

  final String id;
  final String name;
  final ToolActivityPhase phase;
  final String? parentMessageId;

  ToolActivityView copyWith({
    String? name,
    ToolActivityPhase? phase,
    String? parentMessageId,
  }) => ToolActivityView(
    id: id,
    name: name ?? this.name,
    phase: phase ?? this.phase,
    parentMessageId: parentMessageId ?? this.parentMessageId,
  );
}

final class AgentViewState {
  AgentViewState({
    List<MessageView> messages = const [],
    List<ToolActivityView> tools = const [],
    this.connectionPhase = ConnectionPhase.idle,
    this.runPhase = RunPhase.idle,
    this.failure,
    this.omittedOlderMessages = false,
    this.isStale = false,
    this.status,
  }) : messages = UnmodifiableListView(messages),
       tools = UnmodifiableListView(tools);

  final UnmodifiableListView<MessageView> messages;
  final UnmodifiableListView<ToolActivityView> tools;
  final ConnectionPhase connectionPhase;
  final RunPhase runPhase;
  final ViewFailure? failure;
  final bool omittedOlderMessages;
  final bool isStale;
  final String? status;

  AgentViewState copyWith({
    List<MessageView>? messages,
    List<ToolActivityView>? tools,
    ConnectionPhase? connectionPhase,
    RunPhase? runPhase,
    Object? failure = _unset,
    bool? omittedOlderMessages,
    bool? isStale,
    Object? status = _unset,
  }) => AgentViewState(
    messages: messages ?? this.messages,
    tools: tools ?? this.tools,
    connectionPhase: connectionPhase ?? this.connectionPhase,
    runPhase: runPhase ?? this.runPhase,
    failure: identical(failure, _unset)
        ? this.failure
        : failure as ViewFailure?,
    omittedOlderMessages: omittedOlderMessages ?? this.omittedOlderMessages,
    isStale: isStale ?? this.isStale,
    status: identical(status, _unset) ? this.status : status as String?,
  );

  Map<String, Object?> toSafeJson() => {
    'messages': [
      for (final message in messages)
        {
          'id': message.id,
          'role': message.role.name,
          'text': message.text,
          'isStreaming': message.isStreaming,
          'liveUnavailable': message.liveUnavailable,
        },
    ],
    'tools': [
      for (final tool in tools)
        {
          'id': tool.id,
          'name': tool.name,
          'phase': tool.phase.name,
          if (tool.parentMessageId != null)
            'parentMessageId': tool.parentMessageId,
        },
    ],
    'connectionPhase': connectionPhase.name,
    'runPhase': runPhase.name,
    if (failure != null) 'failure': failure!.kind.name,
    'omittedOlderMessages': omittedOlderMessages,
    'isStale': isStale,
    if (status != null) 'status': status,
  };
}

const Object _unset = Object();
