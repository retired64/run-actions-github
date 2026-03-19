import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGGER — solo en debug, nunca expone tokens
// ─────────────────────────────────────────────────────────────────────────────

abstract final class Log {
  static void d(String tag, String msg) {
    if (kDebugMode) debugPrint('[$tag] $msg');
  }

  static void e(String tag, String msg, [Object? err]) {
    if (kDebugMode) debugPrint('[$tag] ❌ $msg${err != null ? ' → $err' : ''}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS MULTI-CUENTA
// ─────────────────────────────────────────────────────────────────────────────

class GithubAccount {
  final String id;
  final String owner;
  final String token;
  final String label;

  const GithubAccount({
    required this.id,
    required this.owner,
    required this.token,
    required this.label,
  });

  Map<String, dynamic> toJson() => {'id': id, 'owner': owner, 'label': label};

  factory GithubAccount.fromJson(Map<String, dynamic> j) => GithubAccount(
    id: j['id'] as String,
    owner: j['owner'] as String,
    token: '',
    label: j['label'] as String,
  );

  GithubAccount copyWith({String? token, String? label, String? owner}) =>
      GithubAccount(
        id: id,
        owner: owner ?? this.owner,
        token: token ?? this.token,
        label: label ?? this.label,
      );
}

class GithubRepo {
  final String id;
  final String accountId;
  final String repo;
  final String branch;
  final String label;

  const GithubRepo({
    required this.id,
    required this.accountId,
    required this.repo,
    required this.branch,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'repo': repo,
    'branch': branch,
    'label': label,
  };

  factory GithubRepo.fromJson(Map<String, dynamic> j) => GithubRepo(
    id: j['id'] as String,
    accountId: j['accountId'] as String,
    repo: j['repo'] as String,
    branch: (j['branch'] as String?) ?? 'main',
    label: j['label'] as String,
  );

  GithubRepo copyWith({String? repo, String? branch, String? label}) =>
      GithubRepo(
        id: id,
        accountId: accountId,
        repo: repo ?? this.repo,
        branch: branch ?? this.branch,
        label: label ?? this.label,
      );
}

class GithubCredentials {
  final String owner;
  final String repo;
  final String token;
  final String branch;

  const GithubCredentials({
    required this.owner,
    required this.repo,
    required this.token,
    required this.branch,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE WORKFLOW
// ─────────────────────────────────────────────────────────────────────────────

class WorkflowInput {
  final String key;
  final String description;
  final String type;
  final bool required;
  final String? defaultValue;
  final List<String>? options;

  const WorkflowInput({
    required this.key,
    required this.description,
    required this.type,
    required this.required,
    this.defaultValue,
    this.options,
  });

  factory WorkflowInput.fromEntry(String key, Map<String, dynamic> j) =>
      WorkflowInput(
        key: key,
        description: j['description'] as String? ?? '',
        type: j['type'] as String? ?? 'string',
        required: j['required'] as bool? ?? false,
        defaultValue: j['default']?.toString(),
        options: (j['options'] as List?)?.map((e) => e.toString()).toList(),
      );
}

class Workflow {
  final int id;
  final String name;
  final String state;
  final String path;
  final List<WorkflowInput> inputs;

  const Workflow({
    required this.id,
    required this.name,
    required this.state,
    required this.path,
    required this.inputs,
  });

  bool get hasInputs => inputs.isNotEmpty;

  factory Workflow.fromJson(Map<String, dynamic> j) => Workflow(
    id: j['id'] as int,
    name: j['name'] as String,
    state: j['state'] as String,
    path: j['path'] as String,
    inputs: _parseInputs(j),
  );

  static List<WorkflowInput> _parseInputs(Map<String, dynamic> j) {
    final raw = j['inputs'] as Map<String, dynamic>?;
    if (raw == null) return [];
    return raw.entries
        .map(
          (e) =>
              WorkflowInput.fromEntry(e.key, e.value as Map<String, dynamic>),
        )
        .toList();
  }
}

class WorkflowRun {
  final int id;
  final int workflowId;
  final String status;
  final String? conclusion;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const WorkflowRun({
    required this.id,
    required this.workflowId,
    required this.status,
    required this.conclusion,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkflowRun.fromJson(Map<String, dynamic> j) => WorkflowRun(
    id: j['id'] as int,
    workflowId: j['workflow_id'] as int,
    status: j['status'] as String,
    conclusion: j['conclusion'] as String?,
    name: j['name'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: j['updated_at'] != null
        ? DateTime.parse(j['updated_at'] as String)
        : null,
  );

  bool get isRunning =>
      status == 'queued' || status == 'in_progress' || status == 'waiting';

  String duration({DateTime? now}) {
    final ref = now ?? DateTime.now();
    if (isRunning) {
      final d = ref.difference(createdAt);
      if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
      return '${d.inSeconds}s';
    }
    if (updatedAt == null) return '—';
    final d = updatedAt!.difference(createdAt);
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELO DE ARTEFACTO ← NUEVO
// ─────────────────────────────────────────────────────────────────────────────

class WorkflowArtifact {
  final int id;
  final String name;
  final int sizeInBytes;
  final String archiveDownloadUrl;
  final int runId;
  final int workflowId;
  final String workflowName;
  final String workflowFilename;
  final DateTime createdAt;
  final bool expired;

  const WorkflowArtifact({
    required this.id,
    required this.name,
    required this.sizeInBytes,
    required this.archiveDownloadUrl,
    required this.runId,
    required this.workflowId,
    required this.workflowName,
    required this.workflowFilename,
    required this.createdAt,
    required this.expired,
  });

  double get sizeMb => sizeInBytes / (1024 * 1024);

  /// URL pública de nightly.link — no requiere login de GitHub
  String nightlyZipUrl(String owner, String repo, String branch) {
    // Usamos el formato que descubriste: /actions/runs/{runId}/{name}.zip
    // (Mantenemos 'branch' en los parámetros para no romper tu ArtifactsProvider, aunque ya no lo usemos en la URL)
    return 'https://nightly.link/$owner/$repo/actions/runs/$runId/$name.zip';
  }

  factory WorkflowArtifact.fromJson(
    Map<String, dynamic> j, {
    required int workflowId,
    required String workflowName,
    required String workflowFilename,
    required int runId,
  }) => WorkflowArtifact(
    id: j['id'] as int,
    name: j['name'] as String,
    sizeInBytes: j['size_in_bytes'] as int,
    archiveDownloadUrl: j['archive_download_url'] as String,
    runId: runId,
    workflowId: workflowId,
    workflowName: workflowName,
    workflowFilename: workflowFilename,
    createdAt: DateTime.parse(j['created_at'] as String),
    expired: j['expired'] as bool? ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPCIONES
// ─────────────────────────────────────────────────────────────────────────────

enum GithubErrorKind {
  unauthorized,
  forbidden,
  notFound,
  rateLimit,
  network,
  unknown,
}

class GithubException implements Exception {
  final String message;
  final int? statusCode;
  final GithubErrorKind kind;
  final bool isRateLimit;
  final DateTime? rateLimitReset;

  const GithubException(
    this.message, {
    this.statusCode,
    this.kind = GithubErrorKind.unknown,
    this.isRateLimit = false,
    this.rateLimitReset,
  });

  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// MULTI-ACCOUNT STORAGE SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class AccountStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAccountsJson = 'gha_v2_accounts';
  static const _kReposJson = 'gha_v2_repos';
  static const _kActiveRepoId = 'gha_v2_active_repo';
  static const _tokenPrefix = 'gha_v2_token_';

  Future<List<GithubAccount>> loadAccounts() async {
    final raw = await _storage.read(key: _kAccountsJson);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final accounts = list
        .map((e) => GithubAccount.fromJson(e as Map<String, dynamic>))
        .toList();
    final hydrated = <GithubAccount>[];
    for (final acc in accounts) {
      final token = await _storage.read(key: '$_tokenPrefix${acc.id}') ?? '';
      hydrated.add(acc.copyWith(token: token));
    }
    return hydrated;
  }

  Future<void> saveAccount(GithubAccount account) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
    } else {
      accounts.add(account);
    }
    await _storage.write(
      key: _kAccountsJson,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    await _storage.write(
      key: '$_tokenPrefix${account.id}',
      value: account.token,
    );
    Log.d('Storage', 'Cuenta guardada: ${account.label}');
  }

  Future<void> deleteAccount(String accountId) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await _storage.write(
      key: _kAccountsJson,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    await _storage.delete(key: '$_tokenPrefix$accountId');
    Log.d('Storage', 'Cuenta eliminada: $accountId');
  }

  Future<List<GithubRepo>> loadRepos() async {
    final raw = await _storage.read(key: _kReposJson);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => GithubRepo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRepo(GithubRepo repo) async {
    final repos = await loadRepos();
    final idx = repos.indexWhere((r) => r.id == repo.id);
    if (idx >= 0) {
      repos[idx] = repo;
    } else {
      repos.add(repo);
    }
    await _storage.write(
      key: _kReposJson,
      value: jsonEncode(repos.map((r) => r.toJson()).toList()),
    );
    Log.d('Storage', 'Repo guardado: ${repo.label}');
  }

  Future<void> deleteRepo(String repoId) async {
    final repos = await loadRepos();
    repos.removeWhere((r) => r.id == repoId);
    await _storage.write(
      key: _kReposJson,
      value: jsonEncode(repos.map((r) => r.toJson()).toList()),
    );
    Log.d('Storage', 'Repo eliminado: $repoId');
  }

  Future<String?> loadActiveRepoId() => _storage.read(key: _kActiveRepoId);

  Future<void> saveActiveRepoId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _kActiveRepoId);
    } else {
      await _storage.write(key: _kActiveRepoId, value: id);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GITHUB API SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class GithubApiService {
  static const _base = 'https://api.github.com';
  static const _timeout = Duration(seconds: 12);
  static const _tag = 'API';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  bool _isRateLimit(http.Response res) {
    if (res.statusCode != 403 && res.statusCode != 429) return false;
    final remaining = res.headers['x-ratelimit-remaining'];
    return remaining == '0';
  }

  GithubException _rateLimitException(http.Response res) {
    final reset = res.headers['x-ratelimit-reset'];
    DateTime? resetTime;
    if (reset != null) {
      resetTime = DateTime.fromMillisecondsSinceEpoch(int.parse(reset) * 1000);
    }
    final msg = resetTime != null
        ? 'Rate limit alcanzado. Se restablece a las ${resetTime.toLocal().toString().substring(11, 16)}.'
        : 'Rate limit alcanzado. Espera unos minutos.';
    Log.e(_tag, 'Rate limit hit');
    return GithubException(
      msg,
      statusCode: res.statusCode,
      kind: GithubErrorKind.rateLimit,
      isRateLimit: true,
      rateLimitReset: resetTime,
    );
  }

  void _checkStatus(http.Response res) {
    if (_isRateLimit(res)) throw _rateLimitException(res);
    switch (res.statusCode) {
      case 401:
        throw const GithubException(
          'Token inválido o expirado.',
          statusCode: 401,
          kind: GithubErrorKind.unauthorized,
        );
      case 403:
        throw const GithubException(
          'Sin permisos para esta acción.',
          statusCode: 403,
          kind: GithubErrorKind.forbidden,
        );
      case 404:
        throw const GithubException(
          'Repositorio o recurso no encontrado.',
          statusCode: 404,
          kind: GithubErrorKind.notFound,
        );
      case 422:
        throw const GithubException(
          'Parámetros inválidos. Verifica el branch.',
          statusCode: 422,
          kind: GithubErrorKind.unknown,
        );
      default:
        if (res.statusCode >= 400) {
          throw GithubException(
            'Error HTTP ${res.statusCode}.',
            statusCode: res.statusCode,
          );
        }
    }
  }

  Future<http.Response> _get(
    Uri uri,
    String token, {
    int maxAttempts = 2,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await http
            .get(uri, headers: _headers(token))
            .timeout(_timeout);
        Log.d(_tag, 'GET ${uri.path} → ${res.statusCode} (intento $attempt)');
        return res;
      } on GithubException {
        rethrow;
      } catch (e) {
        Log.e(_tag, 'GET ${uri.path} intento $attempt falló', e);
        if (attempt == maxAttempts) {
          throw const GithubException(
            'Error de conexión tras reintentos.',
            kind: GithubErrorKind.network,
          );
        }
        await Future.delayed(Duration(seconds: 2 << (attempt - 1)));
      }
    }
    throw const GithubException(
      'Error inesperado.',
      kind: GithubErrorKind.unknown,
    );
  }

  Future<http.Response> _post(
    Uri uri,
    String token,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http
          .post(uri, headers: _headers(token), body: jsonEncode(body))
          .timeout(_timeout);
      Log.d(_tag, 'POST ${uri.path} → ${res.statusCode}');
      return res;
    } on GithubException {
      rethrow;
    } on TimeoutException {
      throw const GithubException(
        'Tiempo de espera agotado. El workflow puede haberse iniciado.',
        kind: GithubErrorKind.network,
      );
    } catch (e) {
      Log.e(_tag, 'POST ${uri.path} falló', e);
      throw const GithubException(
        'Error de conexión.',
        kind: GithubErrorKind.network,
      );
    }
  }

  Future<void> validateToken(String token) async {
    Log.d(_tag, 'Validando token…');
    final uri = Uri.parse('$_base/user');
    try {
      final res = await http
          .get(uri, headers: _headers(token))
          .timeout(_timeout);
      Log.d(_tag, 'Validación → ${res.statusCode}');
      _checkStatus(res);
    } on GithubException {
      rethrow;
    } on TimeoutException {
      throw const GithubException(
        'Tiempo de espera agotado.',
        kind: GithubErrorKind.network,
      );
    } catch (e) {
      Log.e(_tag, 'validateToken falló', e);
      throw const GithubException(
        'Error de conexión al validar.',
        kind: GithubErrorKind.network,
      );
    }
  }

  Future<List<Workflow>> getWorkflows(GithubCredentials c) async {
    final uri = Uri.parse(
      '$_base/repos/${c.owner}/${c.repo}/actions/workflows',
    );
    final res = await _get(uri, c.token);
    _checkStatus(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['workflows'] as List<dynamic>;
    final workflows = list
        .map((w) => Workflow.fromJson(w as Map<String, dynamic>))
        .where((w) => w.state == 'active')
        .toList();
    Log.d(_tag, 'Workflows activos: ${workflows.length}');
    return workflows;
  }

  Future<Map<int, WorkflowRun>> getLatestRuns(GithubCredentials c) async {
    final uri = Uri.parse(
      '$_base/repos/${c.owner}/${c.repo}/actions/runs?per_page=100&branch=${Uri.encodeComponent(c.branch)}',
    );
    final res = await _get(uri, c.token);
    _checkStatus(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['workflow_runs'] as List<dynamic>;
    final Map<int, WorkflowRun> latest = {};
    for (final item in list) {
      final run = WorkflowRun.fromJson(item as Map<String, dynamic>);
      if (!latest.containsKey(run.workflowId)) {
        latest[run.workflowId] = run;
      }
    }
    Log.d(_tag, 'Runs cargados: ${latest.length}');
    return latest;
  }

  Future<void> dispatchWorkflow(
    GithubCredentials c,
    int workflowId, {
    Map<String, dynamic>? inputs,
  }) async {
    final uri = Uri.parse(
      '$_base/repos/${c.owner}/${c.repo}/actions/workflows/$workflowId/dispatches',
    );
    final body = <String, dynamic>{'ref': c.branch};
    if (inputs != null && inputs.isNotEmpty) body['inputs'] = inputs;
    final res = await _post(uri, c.token, body);
    if (res.statusCode != 204) _checkStatus(res);
    Log.d(_tag, 'Dispatch OK: workflow $workflowId → ${c.branch}');
  }

  // ─── ARTEFACTOS ← NUEVO ────────────────────────────────────────────────────

  /// Obtiene artefactos de los últimos [maxRunsPerWorkflow] runs de cada workflow.
  /// Usa semáforo para limitar a 4 peticiones concurrentes.
  Future<List<WorkflowArtifact>> getRecentArtifacts(
    GithubCredentials c,
    List<Workflow> workflows, {
    int maxRunsPerWorkflow = 3,
  }) async {
    final semaphore = _Semaphore(4);
    final allArtifacts = <WorkflowArtifact>[];

    await Future.wait(
      workflows.map((wf) async {
        final filename = wf.path.split('/').last;
        await semaphore.acquire();
        try {
          final runsUri = Uri.parse(
            '$_base/repos/${c.owner}/${c.repo}/actions/workflows/${wf.id}/runs'
            '?per_page=$maxRunsPerWorkflow&branch=${Uri.encodeComponent(c.branch)}&status=completed',
          );
          final runsRes = await _get(runsUri, c.token);
          _checkStatus(runsRes);
          final runs = (jsonDecode(runsRes.body)['workflow_runs'] as List)
              .cast<Map<String, dynamic>>();

          final batches = await Future.wait(
            runs.map((run) async {
              final runId = run['id'] as int;
              await semaphore.acquire();
              try {
                final artUri = Uri.parse(
                  '$_base/repos/${c.owner}/${c.repo}/actions/runs/$runId/artifacts?per_page=30',
                );
                final artRes = await _get(artUri, c.token);
                _checkStatus(artRes);
                return (jsonDecode(artRes.body)['artifacts'] as List)
                    .map(
                      (a) => WorkflowArtifact.fromJson(
                        a as Map<String, dynamic>,
                        workflowId: wf.id,
                        workflowName: wf.name,
                        workflowFilename: filename,
                        runId: runId,
                      ),
                    )
                    .where((a) => !a.expired)
                    .toList();
              } finally {
                semaphore.release();
              }
            }),
          );

          for (final batch in batches) {
            allArtifacts.addAll(batch);
          }
        } finally {
          semaphore.release();
        }
      }),
    );

    allArtifacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Log.d(_tag, 'Artefactos encontrados: ${allArtifacts.length}');
    return allArtifacts;
  }

  /// Obtiene todos los repos del usuario autenticado (paginado).
  Future<List<String>> getUserRepos(String token) async {
    final all = <String>[];
    int page = 1;
    while (true) {
      final uri = Uri.parse(
        '$_base/user/repos?per_page=100&page=$page&sort=pushed&affiliation=owner,collaborator',
      );
      final res = await _get(uri, token);
      _checkStatus(res);
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) break;
      all.addAll(list.map((r) => r['full_name'] as String));
      if (list.length < 100) break;
      page++;
    }
    return all;
  }

  /// Obtiene los branches de un repo específico.
  Future<List<String>> getRepoBranches(
    String owner,
    String repo,
    String token,
  ) async {
    final uri = Uri.parse('$_base/repos/$owner/$repo/branches?per_page=100');
    final res = await _get(uri, token);
    _checkStatus(res);
    final list = jsonDecode(res.body) as List;
    return list.map((b) => b['name'] as String).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPOSITORIO
// ─────────────────────────────────────────────────────────────────────────────

class GithubRepository {
  final GithubApiService _api;
  final AccountStorageService _storage;

  GithubRepository({GithubApiService? api, AccountStorageService? storage})
    : _api = api ?? GithubApiService(),
      _storage = storage ?? AccountStorageService();

  Future<List<GithubAccount>> loadAccounts() => _storage.loadAccounts();
  Future<List<GithubRepo>> loadRepos() => _storage.loadRepos();
  Future<String?> loadActiveRepoId() => _storage.loadActiveRepoId();
  Future<void> saveActiveRepoId(String? id) => _storage.saveActiveRepoId(id);

  Future<void> validateAndSaveAccount(GithubAccount account) async {
    await _api.validateToken(account.token);
    await _storage.saveAccount(account);
  }

  Future<void> saveRepo(GithubRepo repo) => _storage.saveRepo(repo);
  Future<void> deleteAccount(String id) => _storage.deleteAccount(id);
  Future<void> deleteRepo(String id) => _storage.deleteRepo(id);

  Future<List<Workflow>> getWorkflows(GithubCredentials c) =>
      _api.getWorkflows(c);
  Future<Map<int, WorkflowRun>> getLatestRuns(GithubCredentials c) =>
      _api.getLatestRuns(c);
  Future<void> dispatchWorkflow(
    GithubCredentials c,
    int id, {
    Map<String, dynamic>? inputs,
  }) => _api.dispatchWorkflow(c, id, inputs: inputs);
  Future<void> validateToken(String token) => _api.validateToken(token);

  Future<List<WorkflowArtifact>> getRecentArtifacts(
    GithubCredentials c,
    List<Workflow> workflows, {
    int maxRunsPerWorkflow = 3,
  }) => _api.getRecentArtifacts(
    c,
    workflows,
    maxRunsPerWorkflow: maxRunsPerWorkflow,
  );

  Future<List<String>> getUserRepos(String token) => _api.getUserRepos(token);

  Future<List<String>> getRepoBranches(
    String owner,
    String repo,
    String token,
  ) => _api.getRepoBranches(owner, repo, token);
}

// ─────────────────────────────────────────────────────────────────────────────
// CACHE DE WORKFLOWS EN SHARED PREFERENCES
// ─────────────────────────────────────────────────────────────────────────────

class WorkflowCacheService {
  static const _kWorkflows = 'gha_cache_workflows';
  static const _kRuns = 'gha_cache_runs';
  static const _kRepoId = 'gha_cache_repo_id';

  static Future<void> save({
    required String repoId,
    required List<Workflow> workflows,
    required Map<int, WorkflowRun> runs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRepoId, repoId);
    await prefs.setString(
      _kWorkflows,
      jsonEncode(
        workflows
            .map(
              (w) => {
                'id': w.id,
                'name': w.name,
                'state': w.state,
                'path': w.path,
              },
            )
            .toList(),
      ),
    );
    await prefs.setString(
      _kRuns,
      jsonEncode(
        runs.map(
          (id, run) => MapEntry(id.toString(), {
            'id': run.id,
            'workflowId': run.workflowId,
            'status': run.status,
            'conclusion': run.conclusion,
            'name': run.name,
            'createdAt': run.createdAt.toIso8601String(),
            'updatedAt': run.updatedAt?.toIso8601String(),
          }),
        ),
      ),
    );
  }

  static Future<({List<Workflow> workflows, Map<int, WorkflowRun> runs})?> load(
    String repoId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kRepoId) != repoId) return null;

    final rawW = prefs.getString(_kWorkflows);
    final rawR = prefs.getString(_kRuns);
    if (rawW == null || rawR == null) return null;

    final workflows = (jsonDecode(rawW) as List)
        .map(
          (j) => Workflow(
            id: j['id'] as int,
            name: j['name'] as String,
            state: j['state'] as String,
            path: j['path'] as String,
            inputs: [],
          ),
        )
        .toList();

    final runs = (jsonDecode(rawR) as Map<String, dynamic>).map(
      (k, v) => MapEntry(int.parse(k), WorkflowRun.fromJson(v)),
    );

    return (workflows: workflows, runs: runs);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWorkflows);
    await prefs.remove(_kRuns);
    await prefs.remove(_kRepoId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMÁFORO SIMPLE PARA LIMITAR CONCURRENCIA DE FUTURES
// ─────────────────────────────────────────────────────────────────────────────

class _Semaphore {
  _Semaphore(int maxConcurrent) : _count = maxConcurrent;
  int _count;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _count++;
    }
  }
}
