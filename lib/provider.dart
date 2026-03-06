import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ESTADOS GRANULARES
// ─────────────────────────────────────────────────────────────────────────────

enum InitState   { idle, loading, ready, error }
enum RefreshState { idle, refreshing, error }

// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNTS PROVIDER — gestiona cuentas + repos (multi-cuenta)
// ─────────────────────────────────────────────────────────────────────────────

class AccountsProvider extends ChangeNotifier {
  AccountsProvider({GithubRepository? repository})
      : _repo = repository ?? GithubRepository();

  final GithubRepository _repo;
  static const _tag = 'AccountsProvider';
  static const _uuid = Uuid();

  List<GithubAccount> _accounts = [];
  List<GithubRepo>    _repos    = [];
  GithubRepo?         _activeRepo;

  List<GithubAccount> get accounts  => _accounts;
  List<GithubRepo>    get repos     => _repos;
  GithubRepo?         get activeRepo => _activeRepo;

  bool get hasActiveRepo => _activeRepo != null;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  bool _validating = false;
  bool get isValidating => _validating;

  // FIX #3 — _loaded ya no está en el router; el provider mismo lo maneja
  bool _initialized = false;
  bool get initialized => _initialized;

  // ── repos filtrados por cuenta ────────────────────────────────────────────
  List<GithubRepo> reposForAccount(String accountId) =>
      _repos.where((r) => r.accountId == accountId).toList();

  GithubAccount? accountForRepo(GithubRepo repo) {
    try {
      return _accounts.firstWhere((a) => a.id == repo.accountId);
    } catch (_) {
      return null;
    }
  }

  GithubCredentials? credentialsFor(GithubRepo repo) {
    final acc = accountForRepo(repo);
    if (acc == null) return null;
    return GithubCredentials(
      owner:  acc.owner,
      repo:   repo.repo,
      token:  acc.token,
      branch: repo.branch,
    );
  }

  GithubCredentials? get activeCredentials =>
      _activeRepo != null ? credentialsFor(_activeRepo!) : null;

  // ─── INIT ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.loadAccounts(),
        _repo.loadRepos(),
        _repo.loadActiveRepoId(),
      ]);
      _accounts = results[0] as List<GithubAccount>;
      _repos    = results[1] as List<GithubRepo>;
      final activeId = results[2] as String?;

      if (activeId != null) {
        _activeRepo = _repos.firstWhere(
          (r) => r.id == activeId,
          orElse: () => _repos.isNotEmpty ? _repos.first : throw StateError('no repos'),
        );
      } else if (_repos.isNotEmpty) {
        _activeRepo = _repos.first;
        await _repo.saveActiveRepoId(_activeRepo!.id);
      }

      Log.d(_tag, 'Init OK — ${_accounts.length} cuentas, ${_repos.length} repos');
    } catch (e) {
      Log.e(_tag, 'Init falló', e);
      _accounts = [];
      _repos    = [];
      _activeRepo = null;
    } finally {
      _loading      = false;
      _initialized  = true;
      notifyListeners();
    }
  }

  // ─── SELECCIONAR REPO ACTIVO ──────────────────────────────────────────────

  Future<void> setActiveRepo(GithubRepo repo) async {
    _activeRepo = repo;
    await _repo.saveActiveRepoId(repo.id);
    notifyListeners();
  }

  // ─── AÑADIR / EDITAR CUENTA ───────────────────────────────────────────────

  Future<String?> saveAccount({
    String? existingId,
    required String owner,
    required String token,
    required String label,
  }) async {
    _validating = true;
    _error      = null;
    notifyListeners();

    final id      = existingId ?? _uuid.v4();
    final account = GithubAccount(
      id:    id,
      owner: owner.trim(),
      token: token.trim(),
      label: label.trim().isEmpty ? owner.trim() : label.trim(),
    );

    try {
      await _repo.validateAndSaveAccount(account);
      final idx = _accounts.indexWhere((a) => a.id == id);
      if (idx >= 0) {
        _accounts[idx] = account;
      } else {
        _accounts.add(account);
      }
      _validating = false;
      Log.d(_tag, 'Cuenta guardada: ${account.label}');
      notifyListeners();
      return null; // éxito
    } on GithubException catch (e) {
      _error      = e.message;
      _validating = false;
      Log.e(_tag, 'saveAccount falló', e);
      notifyListeners();
      return e.message;
    } catch (e) {
      _error      = 'Error inesperado.';
      _validating = false;
      Log.e(_tag, 'saveAccount error inesperado', e);
      notifyListeners();
      return _error;
    }
  }

  Future<void> deleteAccount(
      String accountId, WorkflowsProvider workflowsProvider) async {
    // Eliminar repos asociados
    final associated = reposForAccount(accountId).map((r) => r.id).toList();
    for (final rid in associated) {
      await _repo.deleteRepo(rid);
    }
    _repos.removeWhere((r) => r.accountId == accountId);

    // Si el repo activo era de esta cuenta, resetear
    if (_activeRepo != null && _activeRepo!.accountId == accountId) {
      _activeRepo = _repos.isNotEmpty ? _repos.first : null;
      await _repo.saveActiveRepoId(_activeRepo?.id);
      workflowsProvider.reset();
    }

    await _repo.deleteAccount(accountId);
    _accounts.removeWhere((a) => a.id == accountId);
    Log.d(_tag, 'Cuenta eliminada: $accountId');
    notifyListeners();
  }

  // ─── AÑADIR / EDITAR REPO ─────────────────────────────────────────────────

  Future<String?> saveRepo({
    String? existingId,
    required String accountId,
    required String repoName,
    required String branch,
    required String label,
  }) async {
    // Validar que existe la cuenta con token
    final accIdx = _accounts.indexWhere((a) => a.id == accountId);
    if (accIdx < 0) return 'Cuenta no encontrada.';
    final account = _accounts[accIdx];

    _validating = true;
    _error      = null;
    notifyListeners();

    final id   = existingId ?? _uuid.v4();
    final repo = GithubRepo(
      id:        id,
      accountId: accountId,
      repo:      repoName.trim(),
      branch:    branch.trim().isEmpty ? 'main' : branch.trim(),
      label:     label.trim().isEmpty ? repoName.trim() : label.trim(),
    );

    // Validar acceso al repo antes de guardar
    try {
      final creds = GithubCredentials(
        owner:  account.owner,
        repo:   repo.repo,
        token:  account.token,
        branch: repo.branch,
      );
      await _repo.getWorkflows(creds); // prueba de acceso
    } on GithubException catch (e) {
      _error      = e.message;
      _validating = false;
      Log.e(_tag, 'saveRepo — validación acceso falló', e);
      notifyListeners();
      return e.message;
    } catch (e) {
      _error      = 'Error al validar el repositorio.';
      _validating = false;
      notifyListeners();
      return _error;
    }

    try {
      await _repo.saveRepo(repo);
      final idx = _repos.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        _repos[idx] = repo;
        if (_activeRepo?.id == id) _activeRepo = repo;
      } else {
        _repos.add(repo);
        // Si es el primero, activarlo automáticamente
        if (_activeRepo == null) {
          _activeRepo = repo;
          await _repo.saveActiveRepoId(repo.id);
        }
      }
      _validating = false;
      Log.d(_tag, 'Repo guardado: ${repo.label}');
      notifyListeners();
      return null;
    } catch (e) {
      _error      = 'Error al guardar el repositorio.';
      _validating = false;
      Log.e(_tag, 'saveRepo error', e);
      notifyListeners();
      return _error;
    }
  }

  Future<void> deleteRepo(
      String repoId, WorkflowsProvider workflowsProvider) async {
    final wasActive = _activeRepo?.id == repoId;
    _repos.removeWhere((r) => r.id == repoId);
    await _repo.deleteRepo(repoId);

    if (wasActive) {
      _activeRepo = _repos.isNotEmpty ? _repos.first : null;
      await _repo.saveActiveRepoId(_activeRepo?.id);
      workflowsProvider.reset();
      if (_activeRepo != null) {
        final creds = credentialsFor(_activeRepo!);
        if (creds != null) await workflowsProvider.load(creds);
      }
    }
    Log.d(_tag, 'Repo eliminado: $repoId');
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW PROVIDER — idéntica lógica pero con FIX #1 (reset _loaded externo),
// FIX #5 (rate limit reset datetime), FIX #6 (estado "awaiting run")
// ─────────────────────────────────────────────────────────────────────────────

class WorkflowsProvider extends ChangeNotifier {
  WorkflowsProvider({GithubRepository? repository})
      : _repo = repository ?? GithubRepository();

  final GithubRepository _repo;
  static const _tag = 'WorkflowsProvider';

  List<Workflow>        _workflows   = [];
  Map<int, WorkflowRun> _runs        = {};
  List<Workflow>        get workflows => _workflows;
  WorkflowRun? runFor(int id)         => _runs[id];

  InitState    _initState    = InitState.idle;
  RefreshState _refreshState = RefreshState.idle;
  InitState    get initState    => _initState;
  RefreshState get refreshState => _refreshState;

  bool get isInitialLoading => _initState == InitState.loading;
  bool get isRefreshing     => _refreshState == RefreshState.refreshing;
  bool get isPollingActive  => _pollTimer != null;
  bool get hasData          => _initState == InitState.ready;

  final Map<int, bool> _dispatching    = {};
  bool isDispatching(int id)           => _dispatching[id] ?? false;

  // FIX #6 — workflows que acaban de hacer dispatch y esperan run
  final Set<int> _awaitingRun = {};
  bool isAwaitingRun(int id) => _awaitingRun.contains(id);

  String? _error;
  String? get error => _error;

  bool      _rateLimited     = false;
  DateTime? _rateLimitReset;           // FIX #5
  bool      get isRateLimited  => _rateLimited;
  DateTime? get rateLimitReset => _rateLimitReset;

  /// FIX #5 — countdown restante en segundos (null si no aplica)
  int? get rateLimitSecondsLeft {
    if (!_rateLimited || _rateLimitReset == null) return null;
    final diff = _rateLimitReset!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : null;
  }

  Timer? _pollTimer;
  Timer? _countdownTimer; // FIX #5 — tick cada segundo para countdown

  // ─── CARGA INICIAL ────────────────────────────────────────────────────────

  Future<void> load(GithubCredentials creds) async {
    _initState = InitState.loading;
    _error     = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.getWorkflows(creds),
        _repo.getLatestRuns(creds),
      ]);
      _workflows   = results[0] as List<Workflow>;
      _runs        = results[1] as Map<int, WorkflowRun>;
      _initState   = InitState.ready;
      _rateLimited = false;
      _rateLimitReset = null;
      Log.d(_tag, 'Carga inicial OK: ${_workflows.length} workflows');
    } on GithubException catch (e) {
      _error     = e.message;
      _initState = InitState.error;
      if (e.isRateLimit) {
        _rateLimited    = true;
        _rateLimitReset = e.rateLimitReset;
        _startCountdown();
      }
      Log.e(_tag, 'load falló', e);
    } finally {
      notifyListeners();
    }
  }

  // ─── REFRESH MANUAL ───────────────────────────────────────────────────────

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
      _rateLimitReset = null;
      Log.d(_tag, 'Refresh OK');
    } on GithubException catch (e) {
      _refreshState = RefreshState.error;
      if (e.isRateLimit) {
        _rateLimited    = true;
        _rateLimitReset = e.rateLimitReset;
        _error          = e.message;
        _startCountdown();
      }
      Log.e(_tag, 'refresh falló — manteniendo estado anterior', e);
    } finally {
      notifyListeners();
    }
  }

  // ─── DISPATCH ─────────────────────────────────────────────────────────────

  Future<String?> dispatch(
    GithubCredentials creds,
    int workflowId, {
    Map<String, dynamic>? inputs,
  }) async {
    if (_rateLimited) return 'Rate limit activo. Espera antes de ejecutar.';

    _dispatching[workflowId]  = true;
    notifyListeners();

    try {
      await _repo.dispatchWorkflow(creds, workflowId, inputs: inputs);
      _dispatching[workflowId] = false;
      // FIX #6 — marcar como "esperando run" durante los primeros ticks
      _awaitingRun.add(workflowId);
      notifyListeners();
      _startPolling(creds);
      return null;
    } on GithubException catch (e) {
      _dispatching[workflowId] = false;
      if (e.isRateLimit) {
        _rateLimited    = true;
        _rateLimitReset = e.rateLimitReset;
        _startCountdown();
      }
      notifyListeners();
      Log.e(_tag, 'dispatch falló', e);
      return e.message;
    }
  }

  // ─── POLLING ──────────────────────────────────────────────────────────────

  void _startPolling(GithubCredentials creds) {
    _pollTimer?.cancel();
    int ticks      = 0;
    int failStreak = 0;
    const maxTicks = 15;   // 60s máximo
    const maxFails = 3;

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
        _runs = fresh;
        failStreak = 0;

        // FIX #6 — limpiar awaitingRun si el run ya apareció
        _awaitingRun.removeWhere((id) => _runs.containsKey(id));

        notifyListeners();
        Log.d(_tag, 'Poll tick $ticks OK');
      } on GithubException catch (e) {
        failStreak++;
        Log.e(_tag, 'Poll tick $ticks falló (racha: $failStreak)', e);
        if (e.isRateLimit) {
          _rateLimited    = true;
          _rateLimitReset = e.rateLimitReset;
          _error          = e.message;
          _startCountdown();
          notifyListeners();
        }
        if (failStreak >= maxFails) {
          Log.e(_tag, 'Polling detenido tras $maxFails fallos');
          _pollTimer?.cancel();
          _pollTimer = null;
          return;
        }
      } catch (e) {
        failStreak++;
        Log.e(_tag, 'Poll tick $ticks — error inesperado', e);
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

  // FIX #5 — countdown visible para rate limit
  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_rateLimitReset == null) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _rateLimitReset!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        _rateLimited    = false;
        _rateLimitReset = null;
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
      notifyListeners();
    });
  }

  // ─── RESET ────────────────────────────────────────────────────────────────

  void reset() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollTimer      = null;
    _countdownTimer = null;
    _workflows      = [];
    _runs           = {};
    _initState      = InitState.idle;
    _refreshState   = RefreshState.idle;
    _error          = null;
    _rateLimited    = false;
    _rateLimitReset = null;
    _dispatching.clear();
    _awaitingRun.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}
