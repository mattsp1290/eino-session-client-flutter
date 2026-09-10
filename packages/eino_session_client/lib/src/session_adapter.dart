import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:ag_ui_view_state/ag_ui_view_state.dart';
import 'package:http/http.dart' as http;

import 'session_contract.dart';
import 'watch_projection.dart';

typedef RetryDelay = Future<void> Function(Duration duration);

final class EinoSessionAdapter {
  EinoSessionAdapter({
    required this.controller,
    required this.transport,
    required this.contract,
    ViewLimits? limits,
    this.headerTimeout = const Duration(seconds: 15),
    this.baselineTimeout = const Duration(seconds: 5),
    this.controlBodyTimeout = const Duration(seconds: 15),
    this.maxControlBodyBytes = 64 * 1024,
    this.retryDelays = const [
      Duration(milliseconds: 250),
      Duration(seconds: 1),
    ],
    RetryDelay? delay,
    http.Client Function()? parserClientFactory,
  }) : limits = limits ?? ViewLimits(),
       _delay = delay ?? Future<void>.delayed,
       _parserClientFactory = parserClientFactory ?? http.Client.new {
    if (headerTimeout <= Duration.zero ||
        baselineTimeout <= Duration.zero ||
        controlBodyTimeout <= Duration.zero ||
        maxControlBodyBytes <= 0 ||
        retryDelays.any((value) => value < Duration.zero)) {
      throw ArgumentError('Timeouts and limits must be positive');
    }
  }

  final AgentViewController controller;
  final RequestTransport transport;
  final EinoSessionContract contract;
  final ViewLimits limits;
  final Duration headerTimeout;
  final Duration baselineTimeout;
  final Duration controlBodyTimeout;
  final int maxControlBodyBytes;
  final List<Duration> retryDelays;
  final RetryDelay _delay;
  final http.Client Function() _parserClientFactory;

  String? _sessionId;
  int _lifetimeGeneration = 0;
  int _watchGeneration = 0;
  int _controlGeneration = 0;
  RequestOperation? _watchOperation;
  RequestOperation? _controlOperation;
  StreamSubscription<BaseEvent>? _watchSubscription;
  Future<void> Function()? _endWatchAttempt;
  Completer<void>? _watchReady;
  EinoWatchSnapshot? _latestSnapshot;
  String? _activeRunId;
  int _boundAtWatchGeneration = 0;
  bool _submissionOpen = false;
  bool _disposed = false;

  String? get sessionId => _sessionId;
  String? get activeRunId => _activeRunId;

  Future<void> connect(String sessionId) async {
    if (_disposed) throw StateError('Adapter is disposed');
    if (sessionId.isEmpty) throw ArgumentError.value(sessionId, 'sessionId');
    if (_sessionId != sessionId) {
      final watchCancellation = _cancelWatch();
      final controlCancellation = _abortControl();
      _sessionId = sessionId;
      _activeRunId = null;
      _submissionOpen = false;
      _latestSnapshot = null;
      _lifetimeGeneration = controller.beginSession();
      await watchCancellation;
      await controlCancellation;
    }
    await _startWatch(manual: false);
  }

  Future<void> reconnect() async {
    _ensureConnectedSession();
    await _startWatch(manual: true);
  }

  Future<void> _startWatch({required bool manual}) async {
    await _cancelWatch();
    final watchGeneration = ++_watchGeneration;
    final ready = Completer<void>();
    _watchReady = ready;
    controller.setConnection(
      manual ? ConnectionPhase.reconnecting : ConnectionPhase.connecting,
      generation: _lifetimeGeneration,
      stale: manual && controller.state.messages.isNotEmpty,
    );
    unawaited(_watchLoop(watchGeneration, ready));
    await ready.future;
    if (identical(_watchReady, ready)) _watchReady = null;
  }

  Future<void> _watchLoop(int watchGeneration, Completer<void> ready) async {
    final session = _sessionId!;
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (!_watchCurrent(watchGeneration, session)) return;
      if (attempt > 0) {
        controller.setConnection(
          ConnectionPhase.reconnecting,
          generation: _lifetimeGeneration,
          stale: controller.state.messages.isNotEmpty,
        );
        await _delay(retryDelays[attempt - 1]);
        if (!_watchCurrent(watchGeneration, session)) return;
      }
      final retryable = await _watchAttempt(session, watchGeneration, ready);
      if (!retryable || !_watchCurrent(watchGeneration, session)) return;
    }
    if (_watchCurrent(watchGeneration, session)) {
      controller.setConnection(
        ConnectionPhase.disconnected,
        generation: _lifetimeGeneration,
        stale: controller.state.messages.isNotEmpty,
      );
      if (!ready.isCompleted) ready.complete();
    }
  }

  Future<bool> _watchAttempt(
    String session,
    int watchGeneration,
    Completer<void> ready,
  ) async {
    final projection = WatchProjection(
      expectedSessionId: session,
      limits: limits,
    );
    RequestOperation? operation;
    StreamSubscription<BaseEvent>? subscription;
    http.Client? parserHttpClient;
    SseClient? sseClient;
    Timer? pairTimer;
    final ended = Completer<bool>();
    final finished = Completer<void>();
    void failAttempt(bool retryable) {
      if (!ended.isCompleted) ended.complete(retryable);
    }

    Future<void> endWatchAttempt() {
      failAttempt(false);
      return finished.future;
    }

    _endWatchAttempt = endWatchAttempt;

    try {
      operation = transport.open(contract.watchRequest(session));
      _watchOperation = operation;
      final response = await Future.any<TransportResponse?>([
        operation.response.timeout(headerTimeout),
        ended.future.then<TransportResponse?>((_) => null),
      ]);
      if (response == null) return false;
      if (!_watchCurrent(watchGeneration, session)) return false;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final kind = _failureForStatus(response.statusCode);
        final retry = _retryableWatchStatus(response.statusCode);
        if (!retry) {
          controller.fail(kind, generation: _lifetimeGeneration);
          if (!ready.isCompleted) ready.complete();
        }
        return retry;
      }
      if (!_isEventStream(response)) {
        controller.fail(
          ViewFailureKind.incompatibleContract,
          generation: _lifetimeGeneration,
        );
        if (!ready.isCompleted) ready.complete();
        return false;
      }
      parserHttpClient = _parserClientFactory();
      sseClient = SseClient(
        httpClient: parserHttpClient,
        maxDataCodeUnits: limits.maxSseDataCodeUnits,
        maxLineCodeUnits: limits.maxSseLineCodeUnits,
      );
      final events =
          EventStreamAdapter(maxDataCodeUnits: limits.maxSseDataCodeUnits)
              .fromSseStream(
                sseClient.parseStream(response.body, headers: response.headers),
                skipInvalidEvents: false,
              );
      pairTimer = Timer(baselineTimeout, () => failAttempt(true));
      subscription = events.listen(
        (event) {
          if (!_watchCurrent(watchGeneration, session)) return;
          if (event is MessagesSnapshotEvent) {
            pairTimer?.cancel();
            pairTimer = Timer(baselineTimeout, () => failAttempt(true));
          }
          try {
            final commit = projection.add(event);
            if (commit == null) return;
            pairTimer?.cancel();
            _latestSnapshot = commit.snapshot;
            controller.replaceState(
              _reconcileRun(commit, watchGeneration),
              generation: _lifetimeGeneration,
            );
            if (!ready.isCompleted) ready.complete();
          } on ViewProjectionException catch (error) {
            if (error.kind == ViewFailureKind.transient) {
              failAttempt(true);
            } else {
              controller.fail(error.kind, generation: _lifetimeGeneration);
              if (!ready.isCompleted) ready.complete();
              failAttempt(false);
            }
          }
        },
        onError: (Object _) => failAttempt(true),
        onDone: () => failAttempt(true),
        cancelOnError: true,
      );
      _watchSubscription = subscription;
      final retry = await ended.future;
      return retry;
    } on TimeoutException {
      return true;
    } on Object {
      return true;
    } finally {
      try {
        pairTimer?.cancel();
        projection.discardStagedPair();
        await subscription?.cancel();
        if (identical(_endWatchAttempt, endWatchAttempt)) {
          _endWatchAttempt = null;
        }
        if (identical(_watchOperation, operation)) {
          _watchOperation = null;
        }
        if (identical(_watchSubscription, subscription)) {
          _watchSubscription = null;
        }
        await sseClient?.close();
        parserHttpClient?.close();
        await operation?.abort();
      } finally {
        if (!finished.isCompleted) finished.complete();
      }
    }
  }

  AgentViewState _reconcileRun(WatchCommit commit, int watchGeneration) {
    final active = _activeRunId;
    if (active == null) {
      return commit.viewState.copyWith(
        runPhase: _terminalOrIdle(controller.state.runPhase),
      );
    }
    EinoRunView? run;
    for (final candidate in commit.snapshot.runs) {
      if (candidate.id == active) run = candidate;
    }
    if (run == null) {
      if (_submissionOpen && watchGeneration > _boundAtWatchGeneration) {
        _submissionOpen = false;
        return commit.viewState.copyWith(
          runPhase: RunPhase.outcomeUnknown,
          failure: const ViewFailure(ViewFailureKind.outcomeUnavailable),
        );
      }
      return commit.viewState.copyWith(runPhase: controller.state.runPhase);
    }
    final phase = switch (run.status) {
      EinoRunStatus.pending => RunPhase.submitting,
      EinoRunStatus.running => RunPhase.running,
      EinoRunStatus.completed => RunPhase.completed,
      EinoRunStatus.failed => RunPhase.failed,
      EinoRunStatus.interrupted => RunPhase.interrupted,
    };
    if (phase == RunPhase.completed ||
        phase == RunPhase.failed ||
        phase == RunPhase.interrupted) {
      _submissionOpen = false;
    }
    return commit.viewState.copyWith(runPhase: phase, failure: null);
  }

  RunPhase _terminalOrIdle(RunPhase current) => switch (current) {
    RunPhase.completed ||
    RunPhase.failed ||
    RunPhase.interrupted ||
    RunPhase.outcomeUnknown => current,
    _ => RunPhase.idle,
  };

  Future<void> start(String newText) async {
    _ensureConnectedSession();
    if (_submissionOpen) throw StateError('A submission is already active');
    final bytes = utf8.encode(newText);
    if (newText.trim().isEmpty) throw ArgumentError.value(newText, 'newText');
    if (bytes.length > limits.maxSubmissionBytes) {
      controller.fail(
        ViewFailureKind.capacityExceeded,
        generation: _lifetimeGeneration,
      );
      return;
    }
    final identity = ++_controlGeneration;
    final session = _sessionId!;
    final lifetimeGeneration = _lifetimeGeneration;
    _submissionOpen = true;
    controller.setRunPhase(RunPhase.submitting, generation: lifetimeGeneration);
    RequestOperation? operation;
    try {
      operation = transport.open(contract.admissionRequest(session, newText));
      _controlOperation = operation;
      final response = await operation.response.timeout(headerTimeout);
      if (!_controlContextCurrent(identity, session, lifetimeGeneration)) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _submissionOpen = false;
        controller.reportFailure(
          _failureForStatus(response.statusCode),
          generation: lifetimeGeneration,
          runPhase: RunPhase.failed,
        );
        return;
      }
      final body = await _collectBounded(response.body);
      if (!_controlContextCurrent(identity, session, lifetimeGeneration)) {
        return;
      }
      final admission = contract.decodeAdmission(body);
      if (admission.sessionId != session || admission.runId.isEmpty) {
        throw const ViewProjectionException(
          ViewFailureKind.incompatibleContract,
        );
      }
      _activeRunId = admission.runId;
      _boundAtWatchGeneration = _watchGeneration;
      final latest = _latestSnapshot;
      if (latest != null) {
        final current = WatchCommit(
          viewState: controller.state,
          snapshot: latest,
        );
        controller.replaceState(
          _reconcileRun(current, _watchGeneration),
          generation: lifetimeGeneration,
        );
      }
      if (_submissionOpen &&
          (latest == null ||
              !latest.runs.any((run) => run.id == admission.runId))) {
        unawaited(reconnect());
      }
    } on ViewProjectionException catch (error) {
      if (!_controlContextCurrent(identity, session, lifetimeGeneration)) {
        return;
      }
      _submissionOpen = false;
      controller.reportFailure(
        error.kind,
        generation: lifetimeGeneration,
        runPhase: error.kind == ViewFailureKind.outcomeUnavailable
            ? RunPhase.outcomeUnknown
            : RunPhase.failed,
      );
    } on Object {
      if (_controlContextCurrent(identity, session, lifetimeGeneration)) {
        _submissionOpen = false;
        controller.reportFailure(
          ViewFailureKind.outcomeUnavailable,
          generation: lifetimeGeneration,
          runPhase: RunPhase.outcomeUnknown,
        );
      }
    } finally {
      await operation?.abort();
      if (identical(_controlOperation, operation)) _controlOperation = null;
    }
  }

  Future<void> interrupt() async {
    _ensureConnectedSession();
    final runId = _activeRunId;
    if (runId == null || !_submissionOpen) {
      throw StateError('No active run can be interrupted');
    }
    if (_controlOperation != null) throw StateError('A control action is busy');
    final identity = ++_controlGeneration;
    final session = _sessionId!;
    final lifetimeGeneration = _lifetimeGeneration;
    final previousPhase = controller.state.runPhase;
    controller.setRunPhase(
      RunPhase.interrupting,
      generation: lifetimeGeneration,
    );
    RequestOperation? operation;
    try {
      operation = transport.open(contract.interruptRequest(session, runId));
      _controlOperation = operation;
      final response = await operation.response.timeout(headerTimeout);
      if (!_controlContextCurrent(identity, session, lifetimeGeneration)) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        controller.reportFailure(
          _failureForStatus(response.statusCode),
          generation: lifetimeGeneration,
          runPhase: previousPhase,
        );
        return;
      }
      await _collectBounded(response.body);
    } on Object {
      if (_controlContextCurrent(identity, session, lifetimeGeneration)) {
        controller.reportFailure(
          ViewFailureKind.transient,
          generation: lifetimeGeneration,
          runPhase: previousPhase,
        );
      }
    } finally {
      await operation?.abort();
      if (identical(_controlOperation, operation)) _controlOperation = null;
    }
  }

  void resetSubmissionTracking() {
    if (controller.state.runPhase != RunPhase.outcomeUnknown) {
      throw StateError('Only an unknown outcome can be reset');
    }
    _activeRunId = null;
    _submissionOpen = false;
    controller.setRunPhase(RunPhase.idle, generation: _lifetimeGeneration);
  }

  Future<List<int>> _collectBounded(Stream<List<int>> stream) async {
    final result = <int>[];
    await for (final chunk in stream.timeout(controlBodyTimeout)) {
      if (result.length + chunk.length > maxControlBodyBytes) {
        throw const ViewProjectionException(ViewFailureKind.capacityExceeded);
      }
      result.addAll(chunk);
    }
    return result;
  }

  bool _isEventStream(TransportResponse response) =>
      response.header('content-type')?.split(';').first.trim().toLowerCase() ==
      'text/event-stream';

  bool _retryableWatchStatus(int status) =>
      status == 502 || status == 503 || status == 504;

  ViewFailureKind _failureForStatus(int status) => switch (status) {
    401 => ViewFailureKind.unauthorized,
    403 => ViewFailureKind.forbidden,
    404 => ViewFailureKind.unavailable,
    409 => ViewFailureKind.conflict,
    413 => ViewFailureKind.capacityExceeded,
    _ => ViewFailureKind.transient,
  };

  bool _watchCurrent(int generation, String session) =>
      !_disposed && generation == _watchGeneration && session == _sessionId;

  bool _controlCurrent(int identity) =>
      !_disposed && identity == _controlGeneration;

  bool _controlContextCurrent(
    int identity,
    String session,
    int lifetimeGeneration,
  ) =>
      _controlCurrent(identity) &&
      session == _sessionId &&
      lifetimeGeneration == _lifetimeGeneration;

  void _ensureConnectedSession() {
    if (_disposed) throw StateError('Adapter is disposed');
    if (_sessionId == null) throw StateError('No session is connected');
  }

  Future<void> disconnect() async {
    if (_sessionId == null || _disposed) return;
    await _cancelWatch();
    controller.setConnection(
      ConnectionPhase.disconnected,
      generation: _lifetimeGeneration,
      stale: controller.state.messages.isNotEmpty,
    );
  }

  Future<void> _cancelWatch() async {
    _watchGeneration += 1;
    final ready = _watchReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _watchReady = null;
    final finished = _endWatchAttempt?.call();
    _endWatchAttempt = null;
    final subscription = _watchSubscription;
    _watchSubscription = null;
    final operation = _watchOperation;
    _watchOperation = null;
    await subscription?.cancel();
    await operation?.abort();
    await finished;
  }

  Future<void> _abortControl() async {
    _controlGeneration += 1;
    await _controlOperation?.abort();
    _controlOperation = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final ready = _watchReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    _watchReady = null;
    _watchGeneration += 1;
    _controlGeneration += 1;
    final watchFinished = _endWatchAttempt?.call();
    _endWatchAttempt = null;
    final watchSubscription = _watchSubscription;
    final watchOperation = _watchOperation;
    final controlOperation = _controlOperation;
    _watchSubscription = null;
    _watchOperation = null;
    _controlOperation = null;
    await watchSubscription?.cancel();
    await watchOperation?.abort();
    await watchFinished;
    await controlOperation?.abort();
    _latestSnapshot = null;
    _sessionId = null;
    await transport.dispose();
  }
}
