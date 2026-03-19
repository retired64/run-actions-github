import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'services.dart';

const _kLastRunsSnapshot = 'gha_notif_runs_snapshot';
const _kNotifTaskUnique = 'gha_workflow_poll_unique';
const _kNotifTaskName = 'gha_workflow_poll';

// ── Punto de entrada del task en background (debe ser top-level) ──────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await _NotificationPoller.runPoll(inputData ?? {});
      return true;
    } catch (_) {
      return false; // WorkManager reintentará automáticamente
    }
  });
}

// ── Servicio principal ────────────────────────────────────────────────────────
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Llama esto en main() después de ensureInitialized.
  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
    // Solicitar permiso en Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Registra (o reemplaza) el job periódico de WorkManager.
  /// Llama esto cuando el usuario activa un repo.
  static Future<void> schedulePolling({
    required String owner,
    required String repo,
    required String token,
    required String branch,
  }) async {
    await Workmanager().cancelByUniqueName(_kNotifTaskUnique);
    await Workmanager().registerPeriodicTask(
      _kNotifTaskUnique,
      _kNotifTaskName,
      frequency: const Duration(minutes: 15), // mínimo que permite Android
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {
        'owner': owner,
        'repo': repo,
        'token': token,
        'branch': branch,
      },
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Cancela el job (llamar al eliminar todos los repos).
  static Future<void> cancelPolling() =>
      Workmanager().cancelByUniqueName(_kNotifTaskUnique);

  /// Muestra una notificación local.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required bool isFailure,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'gha_runs',
          'Workflow runs',
          channelDescription: 'Estado de tus workflows de GitHub Actions',
          importance: Importance.high,
          priority: Priority.high,
          color: isFailure ? const Color(0xFFFF453A) : const Color(0xFF00D084),
        ),
      ),
    );
  }
}

// ── Lógica del poll (se ejecuta en background) ────────────────────────────────
class _NotificationPoller {
  static Future<void> runPoll(Map<String, dynamic> data) async {
    final owner = data['owner'] as String?;
    final repo = data['repo'] as String?;
    final token = data['token'] as String?;
    final branch = data['branch'] as String? ?? 'main';
    if (owner == null || repo == null || token == null) return;

    final creds = GithubCredentials(
      owner: owner,
      repo: repo,
      token: token,
      branch: branch,
    );

    final api = GithubApiService();
    final freshRuns = await api.getLatestRuns(creds);

    // Cargar snapshot de la ejecución anterior
    final prefs = await SharedPreferences.getInstance();
    final snapRaw = prefs.getString(_kLastRunsSnapshot);
    final snapshot = snapRaw != null
        ? (jsonDecode(snapRaw) as Map<String, dynamic>).map(
            (k, v) => MapEntry(int.parse(k), v as Map<String, dynamic>),
          )
        : <int, Map<String, dynamic>>{};

    // Detectar cambios y notificar
    for (final entry in freshRuns.entries) {
      final wfId = entry.key;
      final run = entry.value;
      final prev = snapshot[wfId];

      final finished = !run.isRunning && run.conclusion != null;
      final isNew =
          prev == null ||
          prev['id'] != run.id ||
          prev['conclusion'] != run.conclusion;

      if (finished && isNew) {
        final icon = run.conclusion == 'success' ? '✓' : '✗';
        final label = switch (run.conclusion) {
          'success' => 'Exitoso',
          'failure' => 'Fallido',
          'cancelled' => 'Cancelado',
          _ => run.conclusion ?? 'Terminado',
        };
        await NotificationService.show(
          id: wfId.hashCode,
          title: '$icon  ${run.name}',
          body: '$label · ${run.duration()}',
          isFailure: run.conclusion != 'success',
        );
      }
    }

    // Guardar nuevo snapshot
    await prefs.setString(
      _kLastRunsSnapshot,
      jsonEncode(
        freshRuns.map(
          (k, v) =>
              MapEntry(k.toString(), {'id': v.id, 'conclusion': v.conclusion}),
        ),
      ),
    );
  }
}
