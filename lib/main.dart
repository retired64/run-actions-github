import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TEMA
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _C {
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHi = Color(0xFF242428);
  static const border = Color(0xFF2C2C2E);
  static const accent = Color(0xFF00D084);
  static const accentDim = Color(0xFF00D08420);
  static const danger = Color(0xFFFF453A);
  static const warn = Color(0xFFFFD60A);
  static const muted = Color(0xFF8E8E93);
  static const text = Color(0xFFEEEEF0);
  static const textDim = Color(0xFF6E6E73);
}

ThemeData _buildTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _C.bg,
  primaryColor: _C.accent,
  colorScheme: const ColorScheme.dark(
    primary: _C.accent,
    surface: _C.surface,
    error: _C.danger,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: _C.bg,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      color: _C.text,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      fontFamily: 'monospace',
    ),
    iconTheme: IconThemeData(color: _C.muted),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  ),
  dividerColor: _C.border,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _C.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _C.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _C.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _C.accent, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _C.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _C.danger, width: 1.5),
    ),
    labelStyle: const TextStyle(color: _C.muted, fontSize: 13),
    hintStyle: const TextStyle(
      color: _C.textDim,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [
        // Punto 7: providers separados para evitar rebuilds innecesarios
        ChangeNotifierProvider(create: (_) => SetupProvider()..init()),
        ChangeNotifierProvider(create: (_) => WorkflowsProvider()),
      ],
      child: const GhaPanelApp(),
    ),
  );
}

class GhaPanelApp extends StatelessWidget {
  const GhaPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GHA Panel',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _RootRouter(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTER RAÍZ
// ─────────────────────────────────────────────────────────────────────────────

class _RootRouter extends StatefulWidget {
  const _RootRouter();
  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final setup = context.watch<SetupProvider>();
    // Una vez que SetupProvider terminó de inicializar y hay credenciales,
    // disparamos la carga de workflows una sola vez.
    if (!_loaded && setup.hasCredentials && setup.credentials != null) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<WorkflowsProvider>().load(setup.credentials!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCredentials = context.select<SetupProvider, bool>(
      (s) => s.hasCredentials,
    );
    return hasCredentials ? const DashboardScreen() : const SetupScreen();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETUP SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _branchCtrl = TextEditingController(text: 'main'); // punto 5
  bool _obscureToken = true;

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _tokenCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = await context.read<SetupProvider>().validateAndSave(
      owner: _ownerCtrl.text,
      repo: _repoCtrl.text,
      token: _tokenCtrl.text,
      branch: _branchCtrl.text,
    );

    if (!mounted) return;
    if (!ok) {
      final err = context.read<SetupProvider>().error ?? 'Error desconocido.';
      _snack(err, isError: true);
    } else if (context.read<SetupProvider>().credentials != null) {
      context.read<WorkflowsProvider>().load(
        context.read<SetupProvider>().credentials!,
      );
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_buildSnack(msg, isError: isError));
  }

  @override
  Widget build(BuildContext context) {
    // Selector punto 7 — solo escucha isValidating del SetupProvider
    final isValidating = context.select<SetupProvider, bool>(
      (s) => s.isValidating,
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _AppLogo(),
                const SizedBox(height: 40),
                const _SectionLabel('CONFIGURACIÓN'),
                const SizedBox(height: 14),
                _InputField(
                  controller: _ownerCtrl,
                  label: 'Owner / Username',
                  hint: 'ej: octocat',
                  icon: Icons.person_outline_rounded,
                  validator: _required,
                ),
                const SizedBox(height: 10),
                _InputField(
                  controller: _repoCtrl,
                  label: 'Repositorio',
                  hint: 'ej: mi-proyecto',
                  icon: Icons.folder_outlined,
                  validator: _required,
                ),
                const SizedBox(height: 10),
                // Punto 5 — campo branch
                _InputField(
                  controller: _branchCtrl,
                  label: 'Branch de dispatch',
                  hint: 'ej: main',
                  icon: Icons.account_tree_outlined,
                  validator: _required,
                ),
                const SizedBox(height: 10),
                // Token con toggle visibilidad
                TextFormField(
                  controller: _tokenCtrl,
                  obscureText: _obscureToken,
                  style: const TextStyle(
                    color: _C.text,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Personal Access Token',
                    hintText: 'ghp_…',
                    prefixIcon: const Icon(
                      Icons.key_outlined,
                      color: _C.muted,
                      size: 18,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _C.muted,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (!v.trim().startsWith('gh')) {
                      return 'El token debe comenzar con "gh"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: _C.textDim,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cifrado en el dispositivo. Nunca se transmite.',
                      style: TextStyle(color: _C.textDim, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: isValidating ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: _C.surfaceHi,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.8,
                        fontFamily: 'monospace',
                      ),
                    ),
                    child: isValidating
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _C.muted,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'VALIDANDO TOKEN…',
                                style: TextStyle(color: _C.muted),
                              ),
                            ],
                          )
                        : const Text('GUARDAR Y CONTINUAR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Selector punto 7 — solo reconstruye AppBar cuando cambia el repo
    final repoName = context.select<SetupProvider, String>(
      (s) => s.credentials != null
          ? '${s.credentials!.owner}/${s.credentials!.repo}'
          : 'GHA Panel',
    );

    final branch = context.select<SetupProvider, String>(
      (s) => s.credentials?.branch ?? 'main',
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GHA PANEL',
              style: TextStyle(
                fontSize: 10,
                color: _C.muted,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              repoName,
              style: const TextStyle(
                fontSize: 14,
                color: _C.text,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          // Indicador de branch
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _C.accentDim,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 11,
                  color: _C.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  branch,
                  style: const TextStyle(
                    color: _C.accent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Logout
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: _DashboardBody(),
    );
  }

  void _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmLogoutDialog(),
    );
    if (confirm == true && context.mounted) {
      context.read<SetupProvider>().logout(context.read<WorkflowsProvider>());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD BODY — separado para Selector granular (punto 7)
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final creds = context.select<SetupProvider, GithubCredentials?>(
      (s) => s.credentials,
    );

    // Selector solo para estados de carga
    final initState = context.select<WorkflowsProvider, InitState>(
      (w) => w.initState,
    );
    final rateLimited = context.select<WorkflowsProvider, bool>(
      (w) => w.isRateLimited,
    );
    final error = context.select<WorkflowsProvider, String?>((w) => w.error);

    Widget body;

    if (initState == InitState.loading) {
      body = const _LoadingView();
    } else if (initState == InitState.error) {
      body = _ErrorView(
        message: error ?? 'Error desconocido.',
        isRateLimit: rateLimited,
        onRetry: creds != null
            ? () => context.read<WorkflowsProvider>().load(creds)
            : null,
      );
    } else {
      body = _WorkflowList(creds: creds);
    }

    return RefreshIndicator(
      color: _C.accent,
      backgroundColor: _C.surface,
      onRefresh: () {
        if (creds != null) {
          return context.read<WorkflowsProvider>().refresh(creds);
        }
        return Future.value();
      },
      child: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW LIST — usa Selector para no reconstruir toda la lista
// ─────────────────────────────────────────────────────────────────────────────

class _WorkflowList extends StatelessWidget {
  final GithubCredentials? creds;
  const _WorkflowList({required this.creds});

  @override
  Widget build(BuildContext context) {
    final workflows = context.select<WorkflowsProvider, List<Workflow>>(
      (w) => w.workflows,
    );

    if (workflows.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.30),
          const _EmptyView(),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: workflows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final wf = workflows[i];
        // Selector por workflow individual — evita rebuilds de tarjetas vecinas
        return Selector<WorkflowsProvider, (WorkflowRun?, bool)>(
          selector: (_, p) => (p.runFor(wf.id), p.isDispatching(wf.id)),
          builder: (context, data, _) => _WorkflowCard(
            workflow: wf,
            run: data.$1,
            dispatching: data.$2,
            onDispatch: creds == null
                ? null
                : () async {
                    final err = await context
                        .read<WorkflowsProvider>()
                        .dispatch(creds!, wf.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      _buildSnack(
                        err ?? '▶ Workflow iniciado en ${creds!.branch}.',
                        isError: err != null,
                      ),
                    );
                  },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WorkflowCard extends StatelessWidget {
  final Workflow workflow;
  final WorkflowRun? run;
  final bool dispatching;
  final VoidCallback? onDispatch;

  const _WorkflowCard({
    required this.workflow,
    required this.run,
    required this.dispatching,
    required this.onDispatch,
  });

  ({Color color, IconData icon, String label}) _runMeta() {
    if (run == null) {
      return (
        color: _C.textDim,
        icon: Icons.circle_outlined,
        label: 'Sin runs',
      );
    }
    if (run!.isRunning) {
      return (
        color: _C.warn,
        icon: Icons.pending_outlined,
        label: run!.status == 'queued' ? 'En cola' : 'En progreso',
      );
    }
    return switch (run!.conclusion) {
      'success' => (
        color: _C.accent,
        icon: Icons.check_circle_outline_rounded,
        label: 'Exitoso',
      ),
      'failure' => (
        color: _C.danger,
        icon: Icons.cancel_outlined,
        label: 'Fallido',
      ),
      'cancelled' => (
        color: _C.muted,
        icon: Icons.remove_circle_outline_rounded,
        label: 'Cancelado',
      ),
      'skipped' => (
        color: _C.textDim,
        icon: Icons.skip_next_outlined,
        label: 'Omitido',
      ),
      _ => (
        color: _C.textDim,
        icon: Icons.help_outline_rounded,
        label: run!.conclusion ?? '—',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final meta = _runMeta();

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _C.accent, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  workflow.name,
                  style: const TextStyle(
                    color: _C.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Badge si tiene inputs (punto 6)
              if (workflow.hasInputs)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _C.warn.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _C.warn.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'inputs',
                    style: TextStyle(
                      color: _C.warn,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            workflow.path,
            style: const TextStyle(
              color: _C.textDim,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // Estado del run
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _C.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.border),
            ),
            child: Row(
              children: [
                Icon(meta.icon, size: 13, color: meta.color),
                const SizedBox(width: 7),
                Text(
                  'Último run: ${meta.label}',
                  style: TextStyle(
                    color: meta.color,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (run != null)
                  Text(
                    run!.duration,
                    style: const TextStyle(
                      color: _C.textDim,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                if (run != null && run!.isRunning) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: _C.warn,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Botón ejecutar
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: (dispatching || onDispatch == null)
                  ? null
                  : onDispatch,
              style: FilledButton.styleFrom(
                backgroundColor: dispatching ? _C.surfaceHi : _C.accentDim,
                foregroundColor: _C.accent,
                disabledForegroundColor: _C.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                  color: dispatching
                      ? _C.border
                      : _C.accent.withValues(alpha: 0.6),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  fontFamily: 'monospace',
                ),
              ),
              icon: dispatching
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _C.muted,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(dispatching ? 'EJECUTANDO…' : 'EJECUTAR'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISTAS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _C.accent),
        ),
        SizedBox(height: 16),
        Text(
          'Cargando workflows…',
          style: TextStyle(
            color: _C.muted,
            fontSize: 12,
            fontFamily: 'monospace',
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final bool isRateLimit;
  final VoidCallback? onRetry;

  const _ErrorView({
    required this.message,
    required this.isRateLimit,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRateLimit
                    ? Icons.hourglass_empty_rounded
                    : Icons.wifi_off_rounded,
                color: isRateLimit ? _C.warn : _C.danger,
                size: 36,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _C.muted,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (!isRateLimit && onRetry != null)
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: _C.accent,
                  ),
                  label: const Text(
                    'Reintentar',
                    style: TextStyle(
                      color: _C.accent,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _C.accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inbox_outlined, color: _C.textDim, size: 38),
        SizedBox(height: 14),
        Text(
          'Sin workflows activos',
          style: TextStyle(
            color: _C.muted,
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Crea un workflow en tu repositorio.',
          style: TextStyle(
            color: _C.textDim,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS REUTILIZABLES
// ─────────────────────────────────────────────────────────────────────────────

class _AppLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _C.accentDim,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.accent.withValues(alpha: 0.5), width: 1),
        ),
        child: const Icon(Icons.bolt_rounded, color: _C.accent, size: 24),
      ),
      const SizedBox(width: 12),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GHA Panel',
            style: TextStyle(
              color: _C.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'GitHub Actions Runner',
            style: TextStyle(
              color: _C.muted,
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _C.muted,
      fontSize: 10,
      letterSpacing: 2.0,
      fontWeight: FontWeight.w600,
      fontFamily: 'monospace',
    ),
  );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    style: const TextStyle(
      color: _C.text,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _C.muted, size: 18),
    ),
    validator: validator,
  );
}

class _ConfirmLogoutDialog extends StatelessWidget {
  const _ConfirmLogoutDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _C.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: _C.border),
    ),
    title: const Text(
      'Cerrar sesión',
      style: TextStyle(
        color: _C.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    ),
    content: const Text(
      'Se borrarán las credenciales del dispositivo.',
      style: TextStyle(
        color: _C.muted,
        fontSize: 13,
        fontFamily: 'monospace',
        height: 1.5,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text(
          'Cancelar',
          style: TextStyle(color: _C.muted, fontSize: 13),
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(
          backgroundColor: _C.danger,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Salir',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER SNACKBAR
// ─────────────────────────────────────────────────────────────────────────────

SnackBar _buildSnack(String msg, {bool isError = false}) => SnackBar(
  content: Text(
    msg,
    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
  ),
  backgroundColor: isError ? _C.danger : _C.accent,
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  duration: Duration(seconds: isError ? 5 : 3),
);
