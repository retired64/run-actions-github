import 'package:flutter/foundation.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ARTIFACTS PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

enum ArtifactsState { idle, loading, ready, error }

class ArtifactsProvider extends ChangeNotifier {
  ArtifactsProvider({GithubRepository? repository})
      : _repo = repository ?? GithubRepository();

  final GithubRepository _repo;
  static const _tag = 'ArtifactsProvider';

  List<WorkflowArtifact> _artifacts = [];
  ArtifactsState         _state     = ArtifactsState.idle;
  String?                _error;

  // progreso de descarga por artifact.id: 0.0–1.0, null = no descargando
  final Map<int, double> _downloadProgress = {};
  // artefactos ya descargados correctamente en esta sesión
  final Set<int> _downloaded = {};

  List<WorkflowArtifact> get artifacts => _artifacts;
  ArtifactsState         get state     => _state;
  String?                get error     => _error;
  bool get isLoading => _state == ArtifactsState.loading;
  bool get hasData   => _state == ArtifactsState.ready;

  double? downloadProgress(int id) => _downloadProgress[id];
  bool    isDownloading(int id)    =>
      _downloadProgress.containsKey(id) && (_downloadProgress[id] ?? 0) < 1.0;
  bool    isDownloaded(int id)     => _downloaded.contains(id);

  /// Artefactos agrupados por nombre de workflow
  Map<String, List<WorkflowArtifact>> get byWorkflow {
    final map = <String, List<WorkflowArtifact>>{};
    for (final a in _artifacts) {
      (map[a.workflowName] ??= []).add(a);
    }
    return map;
  }

  // ─── CARGA ────────────────────────────────────────────────────────────────

  Future<void> load(
    GithubCredentials creds,
    List<Workflow> workflows, {
    int maxRunsPerWorkflow = 3,
  }) async {
    _state = ArtifactsState.loading;
    _error = null;
    notifyListeners();

    try {
      _artifacts = await _repo.getRecentArtifacts(
        creds,
        workflows,
        maxRunsPerWorkflow: maxRunsPerWorkflow,
      );
      _state = ArtifactsState.ready;
      Log.d(_tag, 'Artefactos cargados: ${_artifacts.length}');
    } on GithubException catch (e) {
      _error = e.message;
      _state = ArtifactsState.error;
      Log.e(_tag, 'load falló', e);
    } catch (e) {
      _error = 'Error inesperado al cargar artefactos.';
      _state = ArtifactsState.error;
      Log.e(_tag, 'load error', e);
    } finally {
      notifyListeners();
    }
  }

  void reset() {
    _artifacts = [];
    _state     = ArtifactsState.idle;
    _error     = null;
    _downloadProgress.clear();
    _downloaded.clear();
    notifyListeners();
  }

  // ─── DESCARGA via nightly.link ────────────────────────────────────────────

  Future<void> downloadArtifact({
    required WorkflowArtifact artifact,
    required String owner,
    required String repo,
    required String branch,
    required void Function(String path) onSuccess,
    required void Function(String error) onError,
  }) async {
    if (isDownloading(artifact.id)) return;

    _downloadProgress[artifact.id] = 0.0;
    notifyListeners();

    final zipUrl  = artifact.nightlyZipUrl(owner, repo, branch);
    final fileName = '${artifact.name}.zip';

    Log.d(_tag, 'Descargando via nightly.link: $zipUrl');

    try {
      await FileDownloader.downloadFile(
        url: zipUrl,
        name: fileName,
        notificationType: NotificationType.all,
        onProgress: (String? name, double progress) {
          _downloadProgress[artifact.id] = progress / 100.0;
          notifyListeners();
        },
        onDownloadCompleted: (String path) {
          _downloadProgress[artifact.id] = 1.0;
          _downloaded.add(artifact.id);
          notifyListeners();
          Log.d(_tag, 'Descargado en: $path');
          onSuccess(path);
          Future.delayed(const Duration(seconds: 3), () {
            _downloadProgress.remove(artifact.id);
            notifyListeners();
          });
        },
        onDownloadError: (String err) {
          _downloadProgress.remove(artifact.id);
          notifyListeners();
          Log.e(_tag, 'Error descarga', err);
          onError(err);
        },
      );
    } catch (e) {
      _downloadProgress.remove(artifact.id);
      notifyListeners();
      Log.e(_tag, 'downloadArtifact exception', e);
      onError(e.toString());
    }
  }
}
