import 'dart:async';
import 'package:flutter/foundation.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ESTADOS GRANULARES (punto 8) — distingue cada fase claramente
// ─────────────────────────────────────────────────────────────────────────────

enum InitState   { idle, loading, ready, error }
enum RefreshState { idle, refreshing, error }

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW PROVIDER — maneja lista + runs (punto 7: separado del setup)
// ─────────────────────────────────────────────────────────────────────────────

class WorkflowsProvider extends ChangeNotifier {
  WorkflowsProvider({GithubRepository? repository})
      : _repo = repository ?? GithubRepository();

  final GithubRepository _repo;
  static const _tag = 'WorkflowsProvider';

  // ── Estado de workflows ───────────────────────────────────────────────────
  List<Workflow> _workflows   = [];
  Map<int, WorkflowRun> _runs = {};

  List<Workflow>        get workflows => _workflows;
  WorkflowRun? runFor(int id)         => _runs[id];

  // ── Estados diferenciados (punto 8) ──────────────────────────────────────
  InitState    _initState    = InitState.idle;
  RefreshState _refreshState = RefreshState.idle;

  InitState    get initState    => _initState;
  RefreshState get refreshState => _refreshState;

  bool get isInitialLoading => _initState == InitState.loading;
  bool get isRefreshing     => _refreshState == RefreshState.refreshing;
  bool get isPollingActive  => _pollTimer != null;
  bool get hasData          => _initState == InitState.ready;

  // ── Dispatch por workflow ─────────────────────────────────────────────────
  final Map<int, bool> _dispatching = {};
  bool isDispatching(int id) => _dispatching[id] ?? false;

  // ── Error ─────────────────────────────────────────────────────────────────
  String? _error;
  String? get error => _error;

  // ── Rate limit guard (punto 3) ────────────────────────────────────────────
  bool _rateLimited = false;
  bool get isRateLimited => _rateLimited;

  // ── Polling ───────────────────────────────────────────────────────────────
  Timer? _pollTimer;

  // ─────────────────────────────────────────────────────────────────────────
  // CARGA INICIAL
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> load(GithubCredentials creds) async {
    _initState = InitState.loading;
    _error     = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.getWorkflows(creds),
        _repo.getLatestRuns(creds),
      ]);
      _workflows = results[0] as List<Workflow>;
      _runs      = results[1] as Map<int, WorkflowRun>;
      _initState = InitState.ready;
      _rateLimited = false;
      Log.d(_tag, 'Carga inicial OK: ${_workflows.length} workflows');
    } on GithubException catch (e) {
      _error     = e.message;
      _initState = InitState.error;
      if (e.isRateLimit) _rateLimited = true;
      Log.e(_tag, 'load falló', e);
    } finally {
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REFRESH MANUAL (pull to refresh)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> refresh(GithubCredentials creds) async {
    if (_rateLimited) {
      Log.d(_tag, 'Refresh bloqueado por rate limit');
      return;
    }
    _refreshState = RefreshState.refreshing;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.getWorkflows(creds),
        _repo.getLatestRuns(creds),
      ]);
      _workflows    = results[0] as List<Workflow>;
      _runs         = results[1] as Map<int, WorkflowRun>;
      _refreshState = RefreshState.idle;
      _rateLimited  = false;
      Log.d(_tag, 'Refresh OK');
    } on GithubException catch (e) {
      // Punto 2: no borrar estado anterior, mantener datos existentes
      _refreshState = RefreshState.error;
      if (e.isRateLimit) {
        _rateLimited = true;
        _error = e.message;
      }
      Log.e(_tag, 'refresh falló — manteniendo estado anterior', e);
    } finally {
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPATCH
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> dispatch(
    GithubCredentials creds,
    int workflowId, {
    Map<String, dynamic>? inputs,
  }) async {
    if (_rateLimited) return 'Rate limit activo. Espera antes de ejecutar.';

    _dispatching[workflowId] = true;
    notifyListeners();

    try {
      await _repo.dispatchWorkflow(creds, workflowId, inputs: inputs);
      _dispatching[workflowId] = false;
      notifyListeners();
      _startPolling(creds);
      return null; // null = éxito
    } on GithubException catch (e) {
      _dispatching[workflowId] = false;
      if (e.isRateLimit) _rateLimited = true;
      notifyListeners();
      Log.e(_tag, 'dispatch falló', e);
      return e.message;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POLLING (punto 2 + punto 3 mejorados)
  // ─────────────────────────────────────────────────────────────────────────

  void _startPolling(GithubCredentials creds) {
    _pollTimer?.cancel();
    int ticks       = 0;
    int failStreak  = 0;
    const maxTicks  = 10; // 40s máximo
    const maxFails  = 3;  // parar si 3 fallos consecutivos

    Log.d(_tag, 'Polling iniciado');
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      ticks++;

      if (_rateLimited) {
        Log.d(_tag, 'Polling detenido — rate limit activo');
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }

      try {
        final fresh = await _repo.getLatestRuns(creds);
        _runs      = fresh;
        failStreak = 0;
        notifyListeners();
        Log.d(_tag, 'Poll tick $ticks OK');
      } on GithubException catch (e) {
        // Punto 2: log interno, mantener estado anterior, no romper UI
        failStreak++;
        Log.e(_tag, 'Poll tick $ticks falló (racha: $failStreak)', e);
        if (e.isRateLimit) {
          _rateLimited = true;
          _error = e.message;
          notifyListeners();
        }
        if (failStreak >= maxFails) {
          Log.e(_tag, 'Polling detenido tras $maxFails fallos consecutivos');
          _pollTimer?.cancel();
          _pollTimer = null;
          return;
        }
      } catch (e) {
        // Punto 2: nunca catch vacío
        failStreak++;
        Log.e(_tag, 'Poll tick $ticks — error inesperado (racha: $failStreak)', e);
        if (failStreak >= maxFails) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
        return;
      }

      if (ticks >= maxTicks) {
        Log.d(_tag, 'Polling completado tras $ticks ticks');
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESET
  // ─────────────────────────────────────────────────────────────────────────

  void reset() {
    _pollTimer?.cancel();
    _pollTimer    = null;
    _workflows    = [];
    _runs         = {};
    _initState    = InitState.idle;
    _refreshState = RefreshState.idle;
    _error        = null;
    _rateLimited  = false;
    _dispatching.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETUP PROVIDER — maneja credenciales (punto 7: separado de workflows)
// ─────────────────────────────────────────────────────────────────────────────

class SetupProvider extends ChangeNotifier {
  SetupProvider({GithubRepository? repository})
      : _repo = repository ?? GithubRepository();

  final GithubRepository _repo;
  static const _tag = 'SetupProvider';

  GithubCredentials? _credentials;
  bool get hasCredentials => _credentials != null;
  GithubCredentials? get credentials => _credentials;

  bool   _validating = false;
  bool   get isValidating => _validating;

  String? _error;
  String? get error => _error;

  // ── Carga inicial desde storage ───────────────────────────────────────────
  Future<void> init() async {
    _credentials = await _repo.loadCredentials();
    Log.d(_tag, _credentials != null
        ? 'Credenciales encontradas'
        : 'Sin credenciales guardadas');
    notifyListeners();
  }

  // ── Punto 1: validar y guardar ────────────────────────────────────────────
  Future<bool> validateAndSave({
    required String owner,
    required String repo,
    required String token,
    required String branch,
  }) async {
    _validating = true;
    _error      = null;
    notifyListeners();

    final creds = GithubCredentials(
      owner:  owner.trim(),
      repo:   repo.trim(),
      token:  token.trim(),
      branch: branch.trim().isEmpty ? 'main' : branch.trim(),
    );

    try {
      await _repo.validateAndSave(creds);
      _credentials = creds;
      _validating  = false;
      Log.d(_tag, 'Credenciales validadas y guardadas');
      notifyListeners();
      return true;
    } on GithubException catch (e) {
      _error      = e.message;
      _validating = false;
      Log.e(_tag, 'Validación falló', e);
      notifyListeners();
      return false;
    } catch (e) {
      _error      = 'Error inesperado al guardar.';
      _validating = false;
      Log.e(_tag, 'Error inesperado', e);
      notifyListeners();
      return false;
    }
  }

  Future<void> logout(WorkflowsProvider workflowsProvider) async {
    await _repo.clearCredentials();
    _credentials = null;
    _error       = null;
    workflowsProvider.reset();
    Log.d(_tag, 'Sesión cerrada');
    notifyListeners();
  }
}
