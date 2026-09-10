import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';

enum EinoRunStatus { pending, running, completed, failed, interrupted }

enum EinoToolStatus { pending, running, completed, failed, interrupted }

final class EinoRunView {
  const EinoRunView({required this.id, required this.status});

  final String id;
  final EinoRunStatus status;
}

final class EinoToolView {
  const EinoToolView({
    required this.id,
    required this.runId,
    required this.messageId,
    required this.name,
    required this.status,
  });

  final String id;
  final String runId;
  final String messageId;
  final String name;
  final EinoToolStatus status;
}

final class EinoLiveView {
  const EinoLiveView({
    required this.runId,
    required this.messageId,
    required this.available,
    required this.publicationVersion,
  });

  final String runId;
  final String messageId;
  final bool available;
  final int publicationVersion;
}

final class EinoWatchSnapshot {
  EinoWatchSnapshot({
    required this.storeId,
    required this.sessionId,
    required this.revision,
    required this.exists,
    required this.omittedOlderMessages,
    required List<EinoRunView> runs,
    required List<EinoToolView> tools,
    required List<EinoLiveView> live,
  }) : runs = List.unmodifiable(runs),
       tools = List.unmodifiable(tools),
       live = List.unmodifiable(live);

  final String storeId;
  final String sessionId;
  final int revision;
  final bool exists;
  final bool omittedOlderMessages;
  final List<EinoRunView> runs;
  final List<EinoToolView> tools;
  final List<EinoLiveView> live;
}

final class WatchCommit {
  const WatchCommit({required this.viewState, required this.snapshot});

  final AgentViewState viewState;
  final EinoWatchSnapshot snapshot;
}

final class WatchProjection {
  WatchProjection({required this.expectedSessionId, ViewLimits? limits})
    : _reducer = EventViewReducer(limits: limits);

  static const int _maxSafeInteger = 9007199254740991;
  static const int _maxIdLength = 1024;

  final String expectedSessionId;
  final EventViewReducer _reducer;
  MessagesSnapshotEvent? _stagedMessages;
  String? _storeId;
  int? _revision;

  bool get hasStagedMessages => _stagedMessages != null;

  WatchCommit? add(BaseEvent event) {
    if (event is MessagesSnapshotEvent) {
      if (_stagedMessages != null) _incompatible();
      _stagedMessages = event;
      return null;
    }
    if (event is StateSnapshotEvent) {
      final raw = event.snapshot;
      if (raw is Map<String, dynamic> && raw['ResyncRequired'] == true) {
        _stagedMessages = null;
        throw const ViewProjectionException(ViewFailureKind.transient);
      }
      final messages = _stagedMessages;
      if (messages == null) _incompatible();
      _stagedMessages = null;
      final snapshot = _decodeSnapshot(raw);
      final base = _reducer.reduce(AgentViewState(), messages);
      return WatchCommit(
        snapshot: snapshot,
        viewState: _buildView(base, snapshot),
      );
    }
    _stagedMessages = null;
    _incompatible();
  }

  void discardStagedPair() => _stagedMessages = null;

  AgentViewState _buildView(AgentViewState base, EinoWatchSnapshot snapshot) {
    if (!snapshot.exists) {
      return AgentViewState(
        connectionPhase: ConnectionPhase.connected,
        runPhase: RunPhase.idle,
      );
    }
    final unavailableIds = {
      for (final live in snapshot.live)
        if (!live.available && live.messageId.isNotEmpty) live.messageId,
    };
    return AgentViewState(
      messages: [
        for (final message in base.messages)
          message.copyWith(
            isStreaming: snapshot.live.any(
              (live) => live.available && live.messageId == message.id,
            ),
            liveUnavailable: unavailableIds.contains(message.id),
          ),
      ],
      tools: [
        for (final tool in snapshot.tools)
          ToolActivityView(
            id: tool.id,
            name: tool.name,
            parentMessageId: tool.messageId,
            phase: _toolPhase(tool.status),
          ),
      ],
      connectionPhase: ConnectionPhase.connected,
      runPhase: RunPhase.idle,
      omittedOlderMessages: snapshot.omittedOlderMessages,
    );
  }

  EinoWatchSnapshot _decodeSnapshot(Object? raw) {
    final map = _map(raw);
    final watermark = _map(map['Watermark']);
    final storeId = _string(watermark['StoreID']);
    final sessionId = _string(watermark['SessionID']);
    final revision = _integer(watermark['Revision']);
    if (sessionId != expectedSessionId) _incompatible();
    if (_storeId != null && (_storeId != storeId || revision < _revision!)) {
      _incompatible();
    }
    _storeId = storeId;
    _revision = revision;

    final runs = <EinoRunView>[];
    final runIds = <String>{};
    for (final rawRun in _listOrEmpty(map['Runs'])) {
      final run = _map(rawRun);
      final id = _string(run['ID']);
      if (!runIds.add(id)) _incompatible();
      runs.add(EinoRunView(id: id, status: _runStatus(_string(run['Status']))));
    }

    final tools = <EinoToolView>[];
    final toolIds = <String>{};
    for (final rawTool in _listOrEmpty(map['Tools'])) {
      final tool = _map(rawTool);
      final id = _string(tool['ID']);
      if (!toolIds.add(id)) _incompatible();
      tools.add(
        EinoToolView(
          id: id,
          runId: _string(tool['RunID']),
          messageId: _string(tool['MessageID']),
          name: _string(tool['Name']),
          status: _toolStatus(_string(tool['Status'])),
        ),
      );
    }

    final live = <EinoLiveView>[];
    for (final rawLive in _listOrEmpty(map['Live'])) {
      final item = _map(rawLive);
      final identity = _map(item['Identity']);
      if (_string(identity['SessionID']) != expectedSessionId) _incompatible();
      _string(identity['ServiceID'], allowEmpty: true);
      _string(identity['RequestID'], allowEmpty: true);
      _integer(identity['Attempt']);
      _integer(identity['Step']);
      live.add(
        EinoLiveView(
          runId: _string(identity['RunID']),
          messageId: _string(identity['MessageID'], allowEmpty: true),
          available: _boolean(item['Available']),
          publicationVersion: _integer(item['PublicationVersion']),
        ),
      );
    }
    return EinoWatchSnapshot(
      storeId: storeId,
      sessionId: sessionId,
      revision: revision,
      exists: _boolean(map['Exists']),
      omittedOlderMessages: _boolean(map['OmittedOlderMessages']),
      runs: runs,
      tools: tools,
      live: live,
    );
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) _incompatible();
    return value;
  }

  List<Object?> _listOrEmpty(Object? value) {
    if (value == null) return const [];
    if (value is! List<Object?>) _incompatible();
    return value;
  }

  String _string(Object? value, {bool allowEmpty = false}) {
    if (value is! String ||
        (!allowEmpty && value.isEmpty) ||
        value.length > _maxIdLength) {
      _incompatible();
    }
    return value;
  }

  int _integer(Object? value) {
    if (value is! int || value < 0 || value > _maxSafeInteger) _incompatible();
    return value;
  }

  bool _boolean(Object? value) {
    if (value is! bool) _incompatible();
    return value;
  }

  EinoRunStatus _runStatus(String value) => switch (value) {
    'pending' => EinoRunStatus.pending,
    'running' => EinoRunStatus.running,
    'completed' => EinoRunStatus.completed,
    'failed' => EinoRunStatus.failed,
    'interrupted' => EinoRunStatus.interrupted,
    _ => throw const ViewProjectionException(
      ViewFailureKind.incompatibleContract,
    ),
  };

  EinoToolStatus _toolStatus(String value) => switch (value) {
    'pending' => EinoToolStatus.pending,
    'running' => EinoToolStatus.running,
    'completed' => EinoToolStatus.completed,
    'failed' => EinoToolStatus.failed,
    'interrupted' => EinoToolStatus.interrupted,
    _ => throw const ViewProjectionException(
      ViewFailureKind.incompatibleContract,
    ),
  };

  ToolActivityPhase _toolPhase(EinoToolStatus status) => switch (status) {
    EinoToolStatus.pending => ToolActivityPhase.awaitingResult,
    EinoToolStatus.running => ToolActivityPhase.running,
    EinoToolStatus.completed => ToolActivityPhase.completed,
    EinoToolStatus.failed => ToolActivityPhase.failed,
    EinoToolStatus.interrupted => ToolActivityPhase.interrupted,
  };

  Never _incompatible() =>
      throw const ViewProjectionException(ViewFailureKind.incompatibleContract);
}
