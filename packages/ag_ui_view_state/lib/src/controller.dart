import 'dart:async';

import 'package:ag_ui/ag_ui.dart';

import 'reducer.dart';
import 'view_state.dart';

typedef ViewStateListener = void Function(AgentViewState state);
typedef RemoveViewStateListener = void Function();

final class AgentViewController {
  AgentViewController({EventViewReducer? reducer})
    : _reducer = reducer ?? EventViewReducer();

  final EventViewReducer _reducer;
  final List<ViewStateListener> _listeners = [];
  AgentViewState _state = AgentViewState();
  int _generation = 0;
  bool _disposed = false;
  bool _notifying = false;

  AgentViewState get state => _state;
  bool get isDisposed => _disposed;
  int get generation => _generation;

  RemoveViewStateListener addListener(ViewStateListener listener) {
    if (_disposed) throw StateError('Controller is disposed');
    _listeners.add(listener);
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      _listeners.remove(listener);
    };
  }

  int beginRequest({bool clearPresentation = false}) {
    _ensureMutable();
    _generation += 1;
    _reducer.resetIdentity();
    _publish(
      AgentViewState(
        messages: clearPresentation ? const [] : _state.messages,
        tools: clearPresentation ? const [] : _state.tools,
        connectionPhase: ConnectionPhase.connecting,
        runPhase: RunPhase.submitting,
      ),
    );
    return _generation;
  }

  int replaceConversation() => beginRequest(clearPresentation: true);

  int beginSession() {
    _ensureMutable();
    _generation += 1;
    _reducer.resetIdentity();
    _publish(
      AgentViewState(
        connectionPhase: ConnectionPhase.connecting,
        runPhase: RunPhase.idle,
      ),
    );
    return _generation;
  }

  bool isCurrent(int generation) => !_disposed && generation == _generation;

  void apply(BaseEvent event, {required int generation}) {
    if (!isCurrent(generation)) return;
    try {
      _publish(_reducer.reduce(_state, event));
    } on ViewProjectionException catch (error) {
      fail(error.kind, generation: generation);
    }
  }

  void setConnection(
    ConnectionPhase phase, {
    required int generation,
    bool? stale,
  }) {
    if (!isCurrent(generation)) return;
    _publish(_state.copyWith(connectionPhase: phase, isStale: stale));
  }

  void setRunPhase(RunPhase phase, {required int generation, String? status}) {
    if (!isCurrent(generation)) return;
    _publish(_state.copyWith(runPhase: phase, status: status, failure: null));
  }

  void replaceState(AgentViewState state, {required int generation}) {
    if (!isCurrent(generation)) return;
    _publish(state);
  }

  void fail(
    ViewFailureKind kind, {
    required int generation,
    bool retryable = false,
  }) {
    if (!isCurrent(generation)) return;
    _publish(
      _state.copyWith(
        connectionPhase: ConnectionPhase.failed,
        runPhase: kind == ViewFailureKind.outcomeUnavailable
            ? RunPhase.outcomeUnknown
            : RunPhase.failed,
        failure: ViewFailure(kind, retryable: retryable),
      ),
    );
  }

  void reportFailure(
    ViewFailureKind kind, {
    required int generation,
    RunPhase? runPhase,
    bool retryable = false,
  }) {
    if (!isCurrent(generation)) return;
    _publish(
      _state.copyWith(
        runPhase: runPhase,
        failure: ViewFailure(kind, retryable: retryable),
      ),
    );
  }

  void markIncomplete({required int generation}) {
    if (!isCurrent(generation)) return;
    _publish(
      _state.copyWith(
        connectionPhase: ConnectionPhase.disconnected,
        runPhase: RunPhase.outcomeUnknown,
        failure: const ViewFailure(ViewFailureKind.incomplete),
      ),
    );
  }

  void _publish(AgentViewState next) {
    _ensureMutable();
    _state = next;
    if (_notifying) return;
    _notifying = true;
    var listenerFailed = false;
    try {
      for (final listener in List<ViewStateListener>.of(_listeners)) {
        if (!_listeners.contains(listener)) continue;
        try {
          listener(_state);
        } on Object {
          listenerFailed = true;
        }
      }
    } finally {
      _notifying = false;
    }
    if (listenerFailed && !_disposed) {
      _state = _state.copyWith(
        failure: const ViewFailure(ViewFailureKind.hostCallbackFailed),
      );
    }
  }

  void _ensureMutable() {
    if (_disposed) throw StateError('Controller is disposed');
    if (_notifying) throw StateError('Reentrant controller mutation');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _listeners.clear();
    _state = AgentViewState(
      connectionPhase: ConnectionPhase.disposed,
      runPhase: _state.runPhase,
    );
    await Future<void>.value();
  }
}
