import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// LOGGER — solo en debug, nunca expone tokens (punto 9)
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
// MODELOS
// ─────────────────────────────────────────────────────────────────────────────

class GithubCredentials {
  final String owner;
  final String repo;
  final String token;
  final String branch; // punto 5

  const GithubCredentials({
    required this.owner,
    required this.repo,
    required this.token,
    required this.branch,
  });
}

// Punto 6 — estructura para inputs de workflow_dispatch
class WorkflowInput {
  final String key;
  final String description;
  final String type;           // string | boolean | choice | environment
  final bool required;
  final String? defaultValue;
  final List<String>? options; // solo para type=choice

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
  final List<WorkflowInput> inputs; // punto 6

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
        .map((e) => WorkflowInput.fromEntry(e.key, e.value as Map<String, dynamic>))
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

  bool get isRunning => status == 'queued' || status == 'in_progress';

  String get duration {
    if (updatedAt == null) return '—';
    final d = updatedAt!.difference(createdAt);
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPCIONES
// ─────────────────────────────────────────────────────────────────────────────

enum GithubErrorKind { unauthorized, forbidden, notFound, rateLimit, network, unknown }

class GithubException implements Exception {
  final String message;
  final int? statusCode;
  final GithubErrorKind kind;
  final bool isRateLimit;

  const GithubException(
    this.message, {
    this.statusCode,
    this.kind = GithubErrorKind.unknown,
    this.isRateLimit = false,
  });

  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// CREDENTIALS SERVICE — delete selectivo, nunca deleteAll (punto 4)
// ─────────────────────────────────────────────────────────────────────────────

class CredentialsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kOwner  = 'gha_v1_owner';
  static const _kRepo   = 'gha_v1_repo';
  static const _kToken  = 'gha_v1_token';
  static const _kBranch = 'gha_v1_branch';

  Future<void> save(GithubCredentials c) async {
    Log.d('Creds', 'Guardando → ${c.owner}/${c.repo} [${c.branch}]');
    await Future.wait([
      _storage.write(key: _kOwner,  value: c.owner),
      _storage.write(key: _kRepo,   value: c.repo),
      _storage.write(key: _kToken,  value: c.token),
      _storage.write(key: _kBranch, value: c.branch),
    ]);
  }

  Future<GithubCredentials?> load() async {
    final r = await Future.wait([
      _storage.read(key: _kOwner),
      _storage.read(key: _kRepo),
      _storage.read(key: _kToken),
      _storage.read(key: _kBranch),
    ]);
    if (r[0] == null || r[1] == null || r[2] == null) return null;
    Log.d('Creds', 'Cargado → ${r[0]}/${r[1]} [${r[3] ?? 'main'}]');
    return GithubCredentials(
        owner: r[0]!, repo: r[1]!, token: r[2]!, branch: r[3] ?? 'main');
  }

  Future<void> clear() async {
    Log.d('Creds', 'Borrando keys específicas');
    await Future.wait([
      _storage.delete(key: _kOwner),
      _storage.delete(key: _kRepo),
      _storage.delete(key: _kToken),
      _storage.delete(key: _kBranch),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GITHUB API SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class GithubApiService {
  static const _base    = 'https://api.github.com';
  static const _timeout = Duration(seconds: 12);
  static const _tag     = 'API';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  // ── Rate limit (punto 3) ──────────────────────────────────────────────────
  bool _isRateLimit(http.Response res) {
    if (res.statusCode != 403) return false;
    final remaining = res.headers['x-ratelimit-remaining'];
    return remaining == '0';
  }

  GithubException _rateLimitException(http.Response res) {
    final reset = res.headers['x-ratelimit-reset'];
    final resetTime = reset != null
        ? DateTime.fromMillisecondsSinceEpoch(int.parse(reset) * 1000)
        : null;
    final msg = resetTime != null
        ? 'Rate limit alcanzado. Se restablece a las ${resetTime.toLocal().toString().substring(11, 16)}.'
        : 'Rate limit alcanzado. Espera unos minutos.';
    Log.e(_tag, 'Rate limit hit');
    return GithubException(msg,
        statusCode: 403, kind: GithubErrorKind.rateLimit, isRateLimit: true);
  }

  void _checkStatus(http.Response res) {
    if (_isRateLimit(res)) throw _rateLimitException(res);
    switch (res.statusCode) {
      case 401:
        throw const GithubException('Token inválido o expirado.',
            statusCode: 401, kind: GithubErrorKind.unauthorized);
      case 403:
        throw const GithubException('Sin permisos para esta acción.',
            statusCode: 403, kind: GithubErrorKind.forbidden);
      case 404:
        throw const GithubException('Repositorio o recurso no encontrado.',
            statusCode: 404, kind: GithubErrorKind.notFound);
      case 422:
        throw const GithubException('Parámetros inválidos. Verifica el branch.',
            statusCode: 422, kind: GithubErrorKind.unknown);
      default:
        if (res.statusCode >= 400) {
          throw GithubException('Error HTTP ${res.statusCode}.',
              statusCode: res.statusCode);
        }
    }
  }

  // ── Retry GET (punto 10) ──────────────────────────────────────────────────
  Future<http.Response> _get(Uri uri, String token) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final res =
            await http.get(uri, headers: _headers(token)).timeout(_timeout);
        Log.d(_tag, 'GET ${uri.path} → ${res.statusCode} (intento $attempt)');
        return res;
      } on GithubException {
        rethrow;
      } catch (e) {
        Log.e(_tag, 'GET ${uri.path} intento $attempt falló', e);
        if (attempt == 2) {
          throw const GithubException('Error de conexión tras 2 intentos.',
              kind: GithubErrorKind.network);
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw const GithubException('Error inesperado.', kind: GithubErrorKind.unknown);
  }

  // ── Retry POST (punto 10) ─────────────────────────────────────────────────
  Future<http.Response> _post(
      Uri uri, String token, Map<String, dynamic> body) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final res = await http
            .post(uri, headers: _headers(token), body: jsonEncode(body))
            .timeout(_timeout);
        Log.d(_tag, 'POST ${uri.path} → ${res.statusCode} (intento $attempt)');
        return res;
      } on GithubException {
        rethrow;
      } catch (e) {
        Log.e(_tag, 'POST ${uri.path} intento $attempt falló', e);
        if (attempt == 2) {
          throw const GithubException('Error de conexión tras 2 intentos.',
              kind: GithubErrorKind.network);
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw const GithubException('Error inesperado.', kind: GithubErrorKind.unknown);
  }

  // ── Punto 1: Validar token ────────────────────────────────────────────────
  Future<void> validateToken(String token) async {
    Log.d(_tag, 'Validando token…');
    final uri = Uri.parse('$_base/user');
    try {
      final res =
          await http.get(uri, headers: _headers(token)).timeout(_timeout);
      Log.d(_tag, 'Validación → ${res.statusCode}');
      _checkStatus(res);
    } on GithubException {
      rethrow;
    } on TimeoutException {
      throw const GithubException('Tiempo de espera agotado.',
          kind: GithubErrorKind.network);
    } catch (e) {
      Log.e(_tag, 'validateToken falló', e);
      throw const GithubException('Error de conexión al validar.',
          kind: GithubErrorKind.network);
    }
  }

  Future<List<Workflow>> getWorkflows(GithubCredentials c) async {
    final uri =
        Uri.parse('$_base/repos/${c.owner}/${c.repo}/actions/workflows');
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
        '$_base/repos/${c.owner}/${c.repo}/actions/runs?per_page=50');
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
    Map<String, dynamic>? inputs, // punto 6
  }) async {
    final uri = Uri.parse(
        '$_base/repos/${c.owner}/${c.repo}/actions/workflows/$workflowId/dispatches');
    final body = <String, dynamic>{'ref': c.branch};
    if (inputs != null && inputs.isNotEmpty) body['inputs'] = inputs;
    final res = await _post(uri, c.token, body);
    if (res.statusCode != 204) _checkStatus(res);
    Log.d(_tag, 'Dispatch OK: workflow $workflowId → ${c.branch}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPOSITORIO
// ─────────────────────────────────────────────────────────────────────────────

class GithubRepository {
  final GithubApiService   _api;
  final CredentialsService _creds;

  GithubRepository({GithubApiService? api, CredentialsService? creds})
      : _api   = api   ?? GithubApiService(),
        _creds = creds ?? CredentialsService();

  Future<GithubCredentials?> loadCredentials() => _creds.load();

  /// Punto 1: valida con la API antes de persistir.
  Future<void> validateAndSave(GithubCredentials c) async {
    await _api.validateToken(c.token);
    await _creds.save(c);
  }

  Future<void> clearCredentials()         => _creds.clear();
  Future<List<Workflow>> getWorkflows(GithubCredentials c) => _api.getWorkflows(c);
  Future<Map<int, WorkflowRun>> getLatestRuns(GithubCredentials c) => _api.getLatestRuns(c);
  Future<void> dispatchWorkflow(GithubCredentials c, int id,
          {Map<String, dynamic>? inputs}) =>
      _api.dispatchWorkflow(c, id, inputs: inputs);
}
