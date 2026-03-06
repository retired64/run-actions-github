import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'provider.dart';
import 'artifacts_provider.dart';
import 'services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLORES
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _C {
  static const bg         = Color(0xFF0D0D0F);
  static const surface    = Color(0xFF1C1C1E);
  static const surfaceHi  = Color(0xFF242428);
  static const surfaceHi2 = Color(0xFF2C2C30);
  static const border     = Color(0xFF2C2C2E);
  static const accent     = Color(0xFF00D084);
  static const accentDim  = Color(0xFF00D08420);
  static const danger     = Color(0xFFFF453A);
  static const warn       = Color(0xFFFFD60A);
  static const warnDim    = Color(0xFFFFD60A20);
  static const blue       = Color(0xFF0A84FF);
  static const muted      = Color(0xFF8E8E93);
  static const text       = Color(0xFFEEEEF0);
  static const textDim    = Color(0xFF6E6E73);
}

// ─────────────────────────────────────────────────────────────────────────────
// TEMA
// ─────────────────────────────────────────────────────────────────────────────

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
      drawerTheme: const DrawerThemeData(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        ChangeNotifierProvider(create: (_) => AccountsProvider()..init()),
        ChangeNotifierProvider(create: (_) => WorkflowsProvider()),
        ChangeNotifierProvider(create: (_) => ArtifactsProvider()),
      ],
      child: const GhaPanelApp(),
    ),
  );
}

class GhaPanelApp extends StatelessWidget {
  const GhaPanelApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GHA Panel',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const _RootRouter(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTER RAÍZ — FIX #3: la carga se dispara desde AccountsProvider
// ─────────────────────────────────────────────────────────────────────────────

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  String? _lastLoadedRepoId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accounts = context.watch<AccountsProvider>();
    if (!accounts.initialized) return;

    final activeRepo = accounts.activeRepo;
    if (activeRepo == null) return;

    // Recargar cuando cambia el repo activo (fix #3: usa id en vez de bool)
    if (_lastLoadedRepoId != activeRepo.id) {
      _lastLoadedRepoId = activeRepo.id;
      final creds = accounts.credentialsFor(activeRepo);
      if (creds != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<WorkflowsProvider>().load(creds);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.select<AccountsProvider, AccountsProvider>(
        (a) => a);
    if (!accounts.initialized) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _C.accent),
          ),
        ),
      );
    }
    return accounts.hasActiveRepo
        ? const DashboardScreen()
        : const WelcomeScreen();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WELCOME SCREEN — primera vez sin cuentas
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();
    final hasAccounts = accounts.accounts.isNotEmpty;
    // Si hay cuentas pero no repos, mostrar paso 2
    final pendingAccount = hasAccounts ? accounts.accounts.first : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const _AppLogo(),
              const SizedBox(height: 48),

              // Indicador de pasos
              Row(
                children: [
                  _StepDot(active: true, done: hasAccounts, number: 1),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: hasAccounts ? _C.accent : _C.border,
                    ),
                  ),
                  _StepDot(active: hasAccounts, done: false, number: 2),
                ],
              ),
              const SizedBox(height: 32),

              Text(
                hasAccounts ? 'Añade un repositorio' : 'Bienvenido',
                style: const TextStyle(
                  color: _C.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                hasAccounts
                    ? 'La cuenta @${pendingAccount!.owner} está lista.\nAhora añade el repositorio que quieres gestionar.'
                    : 'Añade tu primera cuenta de GitHub\npara empezar a gestionar tus workflows.',
                style: const TextStyle(
                  color: _C.muted,
                  fontSize: 14,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              if (hasAccounts) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          _RepoFormSheet(accountId: pendingAccount!.id),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('AÑADIR REPOSITORIO'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const _AccountFormSheet(),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    icon: const Icon(Icons.person_add_outlined,
                        size: 16, color: _C.muted),
                    label: const Text('Añadir otra cuenta',
                        style: TextStyle(color: _C.muted)),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const _AccountFormSheet(),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('AÑADIR CUENTA'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final int number;
  const _StepDot(
      {required this.active, required this.done, required this.number});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? _C.accent
              : active
                  ? _C.accentDim
                  : _C.surfaceHi,
          border: Border.all(
            color: active || done ? _C.accent : _C.border,
            width: 1.5,
          ),
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.black)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: active ? _C.accent : _C.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN — con Drawer lateral
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final activeRepo = context.select<AccountsProvider, GithubRepo?>(
        (a) => a.activeRepo);
    final accounts = context.select<AccountsProvider, AccountsProvider>(
        (a) => a);

    String repoLabel = 'GHA Panel';
    String branch    = 'main';
    if (activeRepo != null) {
      final acc = accounts.accounts.firstWhere(
        (a) => a.id == activeRepo.accountId,
        orElse: () => const GithubAccount(id:'', owner:'?', token:'', label:'?'),
      );
      repoLabel = '${acc.owner}/${activeRepo.repo}';
      branch    = activeRepo.branch;
    }

    return Scaffold(
      drawer: const _AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 22),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GHA PANEL',
              style: TextStyle(
                fontSize: 9,
                color: _C.muted,
                letterSpacing: 2.5,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              repoLabel,
              style: const TextStyle(
                fontSize: 13,
                color: _C.text,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          _BranchBadge(branch: branch),
          const SizedBox(width: 8),
          _RateLimitIndicator(),
          const SizedBox(width: 4),
        ],
      ),
      body: _DashboardBody(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAWER
// ─────────────────────────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const _AppLogo(),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _C.muted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Cuerpo scrollable
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Sección repos agrupados por cuenta
                  for (final account in accounts.accounts) ...[
                    _DrawerAccountSection(account: account),
                  ],

                  // Añadir cuenta
                  const SizedBox(height: 8),
                  _DrawerActionTile(
                    icon: Icons.person_add_outlined,
                    label: 'Añadir cuenta',
                    color: _C.accent,
                    onTap: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _AccountFormSheet(),
                      );
                    },
                  ),

                  const Divider(height: 24),

                  // Artefactos ← NUEVO
                  _DrawerActionTile(
                    icon: Icons.inventory_2_outlined,
                    label: 'Artefactos',
                    color: _C.blue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ArtifactsScreen(),
                        ),
                      );
                    },
                  ),

                  // Ajustes
                  _DrawerActionTile(
                    icon: Icons.settings_outlined,
                    label: 'Configuración',
                    color: _C.muted,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer
            const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: _C.accent, size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'GHA Panel v2.0',
                    style: TextStyle(
                      color: _C.textDim,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerAccountSection extends StatelessWidget {
  final GithubAccount account;
  const _DrawerAccountSection({required this.account});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();
    final workflows = context.read<WorkflowsProvider>();
    final repos     = accounts.reposForAccount(account.id);
    final activeId  = accounts.activeRepo?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera de cuenta
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _C.accentDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    account.owner.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: _C.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label,
                      style: const TextStyle(
                        color: _C.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      '@${account.owner}',
                      style: const TextStyle(
                        color: _C.textDim,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // Editar cuenta
              IconButton(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 18, color: _C.muted),
                onPressed: () =>
                    _showAccountMenu(context, account, accounts, workflows),
              ),
            ],
          ),
        ),

        // Repos de la cuenta
        for (final repo in repos)
          _DrawerRepoTile(
            repo: repo,
            isActive: repo.id == activeId,
            onTap: () async {
              await accounts.setActiveRepo(repo);
              workflows.reset();
              final creds = accounts.credentialsFor(repo);
              if (creds != null) workflows.load(creds);
              if (context.mounted) Navigator.pop(context);
            },
          ),

        // Añadir repo a esta cuenta
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _RepoFormSheet(accountId: account.id),
              );
            },
            icon: const Icon(Icons.add_rounded, size: 14, color: _C.blue),
            label: const Text(
              'Añadir repositorio',
              style: TextStyle(
                color: _C.blue,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }

  void _showAccountMenu(
    BuildContext context,
    GithubAccount account,
    AccountsProvider accounts,
    WorkflowsProvider workflows,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _C.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: _C.muted, size: 20),
              title: const Text('Editar cuenta',
                  style: TextStyle(color: _C.text, fontFamily: 'monospace', fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _AccountFormSheet(existing: account),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: _C.danger, size: 20),
              title: const Text('Eliminar cuenta',
                  style: TextStyle(color: _C.danger, fontFamily: 'monospace', fontSize: 14)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => _ConfirmDeleteDialog(
                    title: 'Eliminar cuenta',
                    body:
                        'Se eliminarán todos los repos de "${account.label}". Esta acción no se puede deshacer.',
                  ),
                );
                if (confirm == true && context.mounted) {
                  await accounts.deleteAccount(account.id, workflows);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerRepoTile extends StatelessWidget {
  final GithubRepo repo;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerRepoTile({
    required this.repo,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? _C.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? _C.accent.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.folder_outlined,
            size: 16,
            color: isActive ? _C.accent : _C.muted,
          ),
          title: Text(
            repo.label,
            style: TextStyle(
              color: isActive ? _C.accent : _C.text,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${repo.repo} · ${repo.branch}',
            style: const TextStyle(
              color: _C.textDim,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          trailing: isActive
              ? const Icon(Icons.check_rounded,
                  size: 16, color: _C.accent)
              : null,
          onTap: onTap,
          onLongPress: () => _showRepoMenu(context),
        ),
      );

  void _showRepoMenu(BuildContext context) {
    final accounts   = context.read<AccountsProvider>();
    final workflows  = context.read<WorkflowsProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                repo.label,
                style: const TextStyle(
                  color: _C.muted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: _C.muted, size: 20),
              title: const Text('Editar repositorio',
                  style: TextStyle(color: _C.text, fontFamily: 'monospace', fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _RepoFormSheet(
                    accountId: repo.accountId,
                    existing: repo,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: _C.danger, size: 20),
              title: const Text('Eliminar repositorio',
                  style: TextStyle(color: _C.danger, fontFamily: 'monospace', fontSize: 14)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => _ConfirmDeleteDialog(
                    title: 'Eliminar repositorio',
                    body:
                        'Se eliminará "${repo.label}" de la configuración.',
                  ),
                );
                if (confirm == true && context.mounted) {
                  await accounts.deleteRepo(repo.id, workflows);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DrawerActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
        onTap: onTap,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RATE LIMIT INDICATOR — FIX #5 countdown visible
// ─────────────────────────────────────────────────────────────────────────────

class _RateLimitIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isRL    = context.select<WorkflowsProvider, bool>(
        (w) => w.isRateLimited);
    final seconds = context.select<WorkflowsProvider, int?>(
        (w) => w.rateLimitSecondsLeft);
    if (!isRL) return const SizedBox.shrink();

    final label = seconds != null
        ? '${_fmtSeconds(seconds)}'
        : 'RL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _C.warnDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _C.warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_bottom_rounded,
              size: 11, color: _C.warn),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: _C.warn,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _fmtSeconds(int s) {
    if (s >= 60) return '${s ~/ 60}m ${s % 60}s';
    return '${s}s';
  }
}

class _BranchBadge extends StatelessWidget {
  final String branch;
  const _BranchBadge({required this.branch});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _C.accentDim,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 11, color: _C.accent),
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
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD BODY
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accounts = context.select<AccountsProvider, AccountsProvider>(
        (a) => a);
    final creds    = accounts.activeCredentials;

    final initState  = context.select<WorkflowsProvider, InitState>(
        (w) => w.initState);
    final rateLimited = context.select<WorkflowsProvider, bool>(
        (w) => w.isRateLimited);
    final error = context.select<WorkflowsProvider, String?>((w) => w.error);

    Widget body;
    if (initState == InitState.loading) {
      body = const _LoadingView();
    } else if (initState == InitState.error) {
      body = _ErrorView(
        message: error ?? 'Error desconocido.',
        isRateLimit: rateLimited,
        onRetry:
            creds != null ? () => context.read<WorkflowsProvider>().load(creds) : null,
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
// WORKFLOW LIST
// ─────────────────────────────────────────────────────────────────────────────

class _WorkflowList extends StatelessWidget {
  final GithubCredentials? creds;
  const _WorkflowList({required this.creds});

  @override
  Widget build(BuildContext context) {
    final workflows = context.select<WorkflowsProvider, List<Workflow>>(
        (w) => w.workflows);

    if (workflows.isEmpty) {
      return ListView(children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
        const _EmptyView(),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: workflows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final wf = workflows[i];
        return Selector<WorkflowsProvider, (WorkflowRun?, bool, bool)>(
          selector: (_, p) =>
              (p.runFor(wf.id), p.isDispatching(wf.id), p.isAwaitingRun(wf.id)),
          builder: (context, data, _) => _WorkflowCard(
            workflow: wf,
            run: data.$1,
            dispatching: data.$2,
            awaitingRun: data.$3,
            onDispatch: creds == null
                ? null
                : () async {
                    if (wf.hasInputs) {
                      await _showInputsDialog(context, wf, creds!);
                    } else {
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
                    }
                  },
          ),
        );
      },
    );
  }

  Future<void> _showInputsDialog(
    BuildContext context,
    Workflow wf,
    GithubCredentials creds,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkflowInputsSheet(
        workflow: wf,
        creds: creds,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW CARD — FIX #6 (awaiting run) + FIX #7 (live duration)
// ─────────────────────────────────────────────────────────────────────────────

class _WorkflowCard extends StatefulWidget {
  final Workflow workflow;
  final WorkflowRun? run;
  final bool dispatching;
  final bool awaitingRun;
  final VoidCallback? onDispatch;

  const _WorkflowCard({
    required this.workflow,
    required this.run,
    required this.dispatching,
    required this.awaitingRun,
    required this.onDispatch,
  });

  @override
  State<_WorkflowCard> createState() => _WorkflowCardState();
}

class _WorkflowCardState extends State<_WorkflowCard> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTickerIfNeeded();
  }

  @override
  void didUpdateWidget(_WorkflowCard old) {
    super.didUpdateWidget(old);
    _startTickerIfNeeded();
  }

  void _startTickerIfNeeded() {
    final running = widget.run?.isRunning ?? false;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  ({Color color, IconData icon, String label}) _runMeta() {
    if (widget.awaitingRun) {
      return (
        color: _C.blue,
        icon: Icons.schedule_rounded,
        label: 'Esperando run…',
      );
    }
    final run = widget.run;
    if (run == null) {
      return (color: _C.textDim, icon: Icons.circle_outlined, label: 'Sin runs');
    }
    if (run.isRunning) {
      return (
        color: _C.warn,
        icon: Icons.pending_outlined,
        label: run.status == 'queued' ? 'En cola' : 'En progreso',
      );
    }
    return switch (run.conclusion) {
      'success'   => (color: _C.accent, icon: Icons.check_circle_outline_rounded, label: 'Exitoso'),
      'failure'   => (color: _C.danger, icon: Icons.cancel_outlined, label: 'Fallido'),
      'cancelled' => (color: _C.muted, icon: Icons.remove_circle_outline_rounded, label: 'Cancelado'),
      'skipped'   => (color: _C.textDim, icon: Icons.skip_next_outlined, label: 'Omitido'),
      _           => (color: _C.textDim, icon: Icons.help_outline_rounded, label: run.conclusion ?? '—'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final meta = _runMeta();
    final run  = widget.run;

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.awaitingRun
              ? _C.blue.withValues(alpha: 0.4)
              : _C.border,
        ),
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
                  widget.workflow.name,
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
              if (widget.workflow.hasInputs)
                _Badge(label: 'inputs', color: _C.warn),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            widget.workflow.path,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _C.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.border),
            ),
            child: Row(
              children: [
                if (widget.awaitingRun || (run?.isRunning ?? false))
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: widget.awaitingRun ? _C.blue : _C.warn,
                    ),
                  )
                else
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
                // FIX #7 — duración live
                if (run != null)
                  Text(
                    run.duration(now: _now),
                    style: const TextStyle(
                      color: _C.textDim,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Botón ejecutar
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed:
                  (widget.dispatching || widget.onDispatch == null)
                      ? null
                      : widget.onDispatch,
              style: FilledButton.styleFrom(
                backgroundColor:
                    widget.dispatching ? _C.surfaceHi : _C.accentDim,
                foregroundColor: _C.accent,
                disabledForegroundColor: _C.muted,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: BorderSide(
                  color: widget.dispatching
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
              icon: widget.dispatching
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: _C.muted),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(widget.dispatching ? 'EJECUTANDO…' : 'EJECUTAR'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW INPUTS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _WorkflowInputsSheet extends StatefulWidget {
  final Workflow workflow;
  final GithubCredentials creds;

  const _WorkflowInputsSheet({
    required this.workflow,
    required this.creds,
  });

  @override
  State<_WorkflowInputsSheet> createState() =>
      _WorkflowInputsSheetState();
}

class _WorkflowInputsSheetState extends State<_WorkflowInputsSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _choiceValues = {};
  final Map<String, bool> _boolValues = {};

  @override
  void initState() {
    super.initState();
    for (final input in widget.workflow.inputs) {
      if (input.type == 'boolean') {
        _boolValues[input.key] = input.defaultValue == 'true';
      } else if (input.type == 'choice') {
        _choiceValues[input.key] =
            input.defaultValue ?? (input.options?.first ?? '');
      } else {
        _controllers[input.key] =
            TextEditingController(text: input.defaultValue ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildInputs() {
    final result = <String, dynamic>{};
    for (final input in widget.workflow.inputs) {
      if (input.type == 'boolean') {
        result[input.key] = _boolValues[input.key] ?? false;
      } else if (input.type == 'choice') {
        result[input.key] = _choiceValues[input.key] ?? '';
      } else {
        result[input.key] = _controllers[input.key]?.text ?? '';
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      color: _C.warn, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.workflow.name,
                      style: const TextStyle(
                        color: _C.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _C.muted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  for (final input in widget.workflow.inputs)
                    _buildInputWidget(input),
                  const SizedBox(height: 16),
                  Selector<WorkflowsProvider, bool>(
                    selector: (_, p) =>
                        p.isDispatching(widget.workflow.id),
                    builder: (context, dispatching, _) => SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: dispatching
                            ? null
                            : () async {
                                final inputs = _buildInputs();
                                Navigator.pop(context);
                                final err = await context
                                    .read<WorkflowsProvider>()
                                    .dispatch(
                                      widget.creds,
                                      widget.workflow.id,
                                      inputs: inputs,
                                    );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  _buildSnack(
                                    err ??
                                        '▶ Workflow iniciado en ${widget.creds.branch}.',
                                    isError: err != null,
                                  ),
                                );
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _C.accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('EJECUTAR'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputWidget(WorkflowInput input) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                input.key,
                style: const TextStyle(
                  color: _C.text,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (input.required)
                const Text(' *',
                    style:
                        TextStyle(color: _C.danger, fontFamily: 'monospace')),
            ],
          ),
          if (input.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                input.description,
                style: const TextStyle(
                  color: _C.textDim,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            )
          else
            const SizedBox(height: 6),
          if (input.type == 'boolean')
            _BoolToggle(
              value: _boolValues[input.key] ?? false,
              onChanged: (v) =>
                  setState(() => _boolValues[input.key] = v),
            )
          else if (input.type == 'choice' &&
              input.options != null &&
              input.options!.isNotEmpty)
            _ChoiceDropdown(
              value: _choiceValues[input.key] ?? input.options!.first,
              options: input.options!,
              onChanged: (v) =>
                  setState(() => _choiceValues[input.key] = v),
            )
          else
            TextFormField(
              controller: _controllers[input.key],
              style: const TextStyle(
                color: _C.text,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: input.defaultValue ?? '',
              ),
            ),
        ],
      ),
    );
  }
}

class _BoolToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BoolToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: value ? _C.accentDim : _C.surfaceHi,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  value ? _C.accent.withValues(alpha: 0.5) : _C.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                color: value ? _C.accent : _C.muted,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                value ? 'true' : 'false',
                style: TextStyle(
                  color: value ? _C.accent : _C.muted,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      );
}

class _ChoiceDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _ChoiceDropdown(
      {required this.value,
      required this.options,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _C.surfaceHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: _C.surfaceHi2,
            style: const TextStyle(
              color: _C.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            items: options
                .map((o) =>
                    DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración',
            style: TextStyle(fontFamily: 'monospace', fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          const _SettingsSection('DESCARGAS'),
          _SettingsActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'Artefactos de workflows',
            color: _C.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArtifactsScreen()),
            ),
          ),
          const Divider(height: 32),
          const _SettingsSection('CUENTAS Y REPOSITORIOS'),
          for (final acc in accounts.accounts)
            _AccountSettingsTile(account: acc),
          _SettingsActionTile(
            icon: Icons.person_add_outlined,
            label: 'Añadir cuenta de GitHub',
            color: _C.accent,
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _AccountFormSheet(),
            ),
          ),
          const Divider(height: 32),
          const _SettingsSection('INFORMACIÓN'),
          _SettingsInfoTile(
            icon: Icons.info_outline_rounded,
            label: 'Versión',
            value: '2.0.0',
          ),
          _SettingsInfoTile(
            icon: Icons.lock_outline_rounded,
            label: 'Almacenamiento',
            value: 'Cifrado en dispositivo',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _AccountSettingsTile extends StatelessWidget {
  final GithubAccount account;
  const _AccountSettingsTile({required this.account});

  @override
  Widget build(BuildContext context) {
    final accounts  = context.read<AccountsProvider>();
    final workflows = context.read<WorkflowsProvider>();
    final repos     = accounts.reposForAccount(account.id);

    return ExpansionTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _C.accentDim,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            account.owner.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: _C.accent,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
      title: Text(
        account.label,
        style: const TextStyle(
          color: _C.text,
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '@${account.owner} · ${repos.length} repo${repos.length != 1 ? 's' : ''}',
        style: const TextStyle(
          color: _C.textDim,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
      iconColor: _C.muted,
      collapsedIconColor: _C.muted,
      children: [
        // Repos de la cuenta
        for (final repo in repos)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
            leading: const Icon(Icons.folder_outlined,
                size: 16, color: _C.muted),
            title: Text(
              repo.label,
              style: const TextStyle(
                color: _C.text,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            subtitle: Text(
              '${repo.repo} · ${repo.branch}',
              style: const TextStyle(
                color: _C.textDim,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: _C.muted),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _RepoFormSheet(
                      accountId: account.id,
                      existing: repo,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 16, color: _C.danger),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => _ConfirmDeleteDialog(
                        title: 'Eliminar repositorio',
                        body: 'Se eliminará "${repo.label}".',
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await accounts.deleteRepo(repo.id, workflows);
                    }
                  },
                ),
              ],
            ),
          ),

        // Añadir repo
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
          child: TextButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _RepoFormSheet(accountId: account.id),
            ),
            icon: const Icon(Icons.add_rounded,
                size: 14, color: _C.blue),
            label: const Text('Añadir repositorio',
                style: TextStyle(
                    color: _C.blue, fontSize: 12, fontFamily: 'monospace')),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ),

        // Acciones cuenta
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _AccountFormSheet(existing: account),
                ),
                icon: const Icon(Icons.edit_outlined,
                    size: 14, color: _C.muted),
                label: const Text('Editar cuenta',
                    style: TextStyle(
                        color: _C.muted,
                        fontSize: 12,
                        fontFamily: 'monospace')),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => _ConfirmDeleteDialog(
                      title: 'Eliminar cuenta',
                      body:
                          'Se eliminarán la cuenta "${account.label}" y todos sus repos.',
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await accounts.deleteAccount(account.id, workflows);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 14, color: _C.danger),
                label: const Text('Eliminar',
                    style: TextStyle(
                        color: _C.danger,
                        fontSize: 12,
                        fontFamily: 'monospace')),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String text;
  const _SettingsSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: _C.muted,
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      );
}

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SettingsActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(label,
            style: TextStyle(
                color: color, fontSize: 14, fontFamily: 'monospace')),
        onTap: onTap,
      );
}

class _SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SettingsInfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: _C.muted, size: 20),
        title: Text(label,
            style: const TextStyle(
                color: _C.text, fontSize: 14, fontFamily: 'monospace')),
        trailing: Text(value,
            style: const TextStyle(
                color: _C.muted, fontSize: 12, fontFamily: 'monospace')),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNT FORM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AccountFormSheet extends StatefulWidget {
  final GithubAccount? existing;
  const _AccountFormSheet({this.existing});

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  final _formKey     = GlobalKey<FormState>();
  late final _ownerCtrl = TextEditingController(
      text: widget.existing?.owner ?? '');
  late final _tokenCtrl = TextEditingController(
      text: widget.existing?.token ?? '');
  late final _labelCtrl = TextEditingController(
      text: widget.existing?.label ?? '');
  bool _obscureToken = true;

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _tokenCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isNew = widget.existing == null;
    final err = await context.read<AccountsProvider>().saveAccount(
          existingId: widget.existing?.id,
          owner: _ownerCtrl.text,
          token: _tokenCtrl.text,
          label: _labelCtrl.text,
        );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_buildSnack(err, isError: true));
    } else {
      final savedAccountId =
          context.read<AccountsProvider>().lastSavedAccountId;
      Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnack(isNew
            ? '✓ Cuenta añadida. Ahora añade un repositorio.'
            : '✓ Cuenta actualizada.'),
      );
      // Si es cuenta nueva, abrir inmediatamente el sheet de añadir repo
      if (isNew && savedAccountId != null) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _RepoFormSheet(accountId: savedAccountId),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing   = widget.existing != null;
    final validating  = context.select<AccountsProvider, bool>(
        (a) => a.isValidating);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      color: _C.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? 'Editar cuenta' : 'Nueva cuenta',
                    style: const TextStyle(
                      color: _C.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _C.muted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InputField(
                        controller: _ownerCtrl,
                        label: 'Owner / Username',
                        hint: 'ej: retired64',
                        icon: Icons.alternate_email_rounded,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _InputField(
                        controller: _labelCtrl,
                        label: 'Alias (opcional)',
                        hint: 'ej: Cuenta personal',
                        icon: Icons.label_outline_rounded,
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 10),
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
                          prefixIcon: const Icon(Icons.key_outlined,
                              color: _C.muted, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureToken
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _C.muted,
                              size: 18,
                            ),
                            onPressed: () => setState(
                                () => _obscureToken = !_obscureToken),
                          ),
                        ),
                        validator: (v) {
                          if (isEditing && (v == null || v.trim().isEmpty)) {
                            return null; // edición: token vacío = no cambiar
                          }
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
                          const Icon(Icons.lock_outline_rounded,
                              size: 12, color: _C.textDim),
                          const SizedBox(width: 6),
                          const Text(
                            'Cifrado en el dispositivo.',
                            style:
                                TextStyle(color: _C.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: validating ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _C.accent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: _C.surfaceHi,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          child: validating
                              ? const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _C.muted),
                                    ),
                                    SizedBox(width: 10),
                                    Text('VALIDANDO TOKEN…',
                                        style: TextStyle(color: _C.muted)),
                                  ],
                                )
                              : Text(isEditing
                                  ? 'GUARDAR CAMBIOS'
                                  : 'AÑADIR CUENTA'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// REPO FORM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _RepoFormSheet extends StatefulWidget {
  final String accountId;
  final GithubRepo? existing;

  const _RepoFormSheet({required this.accountId, this.existing});

  @override
  State<_RepoFormSheet> createState() => _RepoFormSheetState();
}

class _RepoFormSheetState extends State<_RepoFormSheet> {
  final _formKey   = GlobalKey<FormState>();
  late final _repoCtrl   = TextEditingController(
      text: widget.existing?.repo ?? '');
  late final _branchCtrl = TextEditingController(
      text: widget.existing?.branch ?? 'main');
  late final _labelCtrl  = TextEditingController(
      text: widget.existing?.label ?? '');

  @override
  void dispose() {
    _repoCtrl.dispose();
    _branchCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final err = await context.read<AccountsProvider>().saveRepo(
          existingId: widget.existing?.id,
          accountId: widget.accountId,
          repoName: _repoCtrl.text,
          branch: _branchCtrl.text,
          label: _labelCtrl.text,
        );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_buildSnack(err, isError: true));
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        _buildSnack(widget.existing == null
            ? '✓ Repositorio añadido.'
            : '✓ Repositorio actualizado.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing  = widget.existing != null;
    final validating = context.select<AccountsProvider, bool>(
        (a) => a.isValidating);

    // Nombre de cuenta padre
    final accounts = context.read<AccountsProvider>();
    final acc = accounts.accounts.firstWhere(
      (a) => a.id == widget.accountId,
      orElse: () =>
          const GithubAccount(id: '', owner: '?', token: '', label: '?'),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined,
                      color: _C.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing
                              ? 'Editar repositorio'
                              : 'Nuevo repositorio',
                          style: const TextStyle(
                            color: _C.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '@${acc.owner}',
                          style: const TextStyle(
                            color: _C.muted,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _C.muted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _InputField(
                        controller: _repoCtrl,
                        label: 'Nombre del repositorio',
                        hint: 'ej: mi-proyecto',
                        icon: Icons.code_rounded,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _InputField(
                        controller: _branchCtrl,
                        label: 'Branch de dispatch',
                        hint: 'ej: main',
                        icon: Icons.account_tree_outlined,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      _InputField(
                        controller: _labelCtrl,
                        label: 'Alias (opcional)',
                        hint: 'ej: Producción',
                        icon: Icons.label_outline_rounded,
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: validating ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _C.blue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _C.surfaceHi,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          child: validating
                              ? const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white70),
                                    ),
                                    SizedBox(width: 10),
                                    Text('VERIFICANDO…',
                                        style: TextStyle(
                                            color: Colors.white70)),
                                  ],
                                )
                              : Text(isEditing
                                  ? 'GUARDAR CAMBIOS'
                                  : 'AÑADIR REPOSITORIO'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
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
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _C.accent),
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
                  // FIX #5 — countdown en la vista de error también
                  if (isRateLimit)
                    Selector<WorkflowsProvider, int?>(
                      selector: (_, w) => w.rateLimitSecondsLeft,
                      builder: (_, seconds, __) => Column(
                        children: [
                          if (seconds != null)
                            Text(
                              'Disponible en: ${_fmtSeconds(seconds)}',
                              style: const TextStyle(
                                color: _C.warn,
                                fontSize: 18,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
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
                      icon: const Icon(Icons.refresh_rounded,
                          size: 16, color: _C.accent),
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
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );

  String _fmtSeconds(int s) {
    if (s >= 60) return '${s ~/ 60}m ${s % 60}s';
    return '${s}s';
  }
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
// ARTIFACTS SCREEN ← NUEVA PANTALLA
// ─────────────────────────────────────────────────────────────────────────────

class ArtifactsScreen extends StatefulWidget {
  const ArtifactsScreen({super.key});

  @override
  State<ArtifactsScreen> createState() => _ArtifactsScreenState();
}

class _ArtifactsScreenState extends State<ArtifactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final accounts  = context.read<AccountsProvider>();
    final workflows = context.read<WorkflowsProvider>();
    final arts      = context.read<ArtifactsProvider>();
    final creds     = accounts.activeCredentials;
    if (creds == null) return;
    arts.load(creds, workflows.workflows);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();
    final arts     = context.watch<ArtifactsProvider>();
    final creds    = accounts.activeCredentials;

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        title: const Text('Artefactos',
            style: TextStyle(
                color: _C.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _C.muted, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!arts.isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _C.muted, size: 20),
              tooltip: 'Recargar',
              onPressed: creds == null
                  ? null
                  : () => arts.load(
                        creds,
                        context.read<WorkflowsProvider>().workflows,
                      ),
            ),
        ],
      ),
      body: _buildBody(arts, accounts, creds),
    );
  }

  Widget _buildBody(
    ArtifactsProvider arts,
    AccountsProvider accounts,
    GithubCredentials? creds,
  ) {
    if (creds == null) {
      return const _ArtCenteredMsg(
        icon: Icons.account_circle_outlined,
        title: 'Sin cuenta activa',
        subtitle: 'Configura una cuenta para ver artefactos.',
      );
    }

    if (arts.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: _C.accent),
            ),
            SizedBox(height: 14),
            Text('Cargando artefactos…',
                style: TextStyle(
                    color: _C.muted, fontSize: 13, fontFamily: 'monospace')),
          ],
        ),
      );
    }

    if (arts.state == ArtifactsState.error) {
      return _ArtCenteredMsg(
        icon: Icons.error_outline_rounded,
        title: 'Error al cargar',
        subtitle: arts.error ?? 'Error desconocido.',
        action: TextButton.icon(
          onPressed: () => arts.load(
              creds, context.read<WorkflowsProvider>().workflows),
          icon: const Icon(Icons.refresh_rounded, size: 16, color: _C.accent),
          label: const Text('Reintentar',
              style: TextStyle(
                  color: _C.accent, fontSize: 13, fontFamily: 'monospace')),
        ),
      );
    }

    if (arts.artifacts.isEmpty) {
      return const _ArtCenteredMsg(
        icon: Icons.inbox_outlined,
        title: 'Sin artefactos',
        subtitle:
            'No se encontraron artefactos recientes\nen los últimos 3 runs completados.',
      );
    }

    final byWorkflow = arts.byWorkflow;
    final owner  = accounts.activeCredentials!.owner;
    final repo   = accounts.activeRepo!.repo;
    final branch = accounts.activeCredentials!.branch;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header resumen
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _C.accentDim,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _C.accent, size: 18),
              const SizedBox(width: 10),
              Text(
                '${arts.artifacts.length} artefacto${arts.artifacts.length != 1 ? 's' : ''} · ${byWorkflow.length} workflow${byWorkflow.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    color: _C.accent,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Secciones por workflow
        for (final entry in byWorkflow.entries) ...[
          _ArtWorkflowSection(
            workflowName: entry.key,
            artifacts: entry.value,
            owner: owner,
            repo: repo,
            branch: branch,
            artsProvider: arts,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ArtWorkflowSection extends StatelessWidget {
  final String workflowName;
  final List<WorkflowArtifact> artifacts;
  final String owner;
  final String repo;
  final String branch;
  final ArtifactsProvider artsProvider;

  const _ArtWorkflowSection({
    required this.workflowName,
    required this.artifacts,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.artsProvider,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: _C.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(workflowName,
                        style: const TextStyle(
                            color: _C.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace')),
                  ),
                  Text(
                    '${artifacts.length} archivo${artifacts.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: _C.textDim, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const Divider(color: _C.border, height: 1),
            ...artifacts.asMap().entries.map((e) => _ArtifactTile(
                  artifact: e.value,
                  owner: owner,
                  repo: repo,
                  branch: branch,
                  artsProvider: artsProvider,
                  isLast: e.key == artifacts.length - 1,
                )),
          ],
        ),
      );
}

class _ArtifactTile extends StatelessWidget {
  final WorkflowArtifact artifact;
  final String owner;
  final String repo;
  final String branch;
  final ArtifactsProvider artsProvider;
  final bool isLast;

  const _ArtifactTile({
    required this.artifact,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.artsProvider,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final progress    = artsProvider.downloadProgress(artifact.id);
    final downloading = artsProvider.isDownloading(artifact.id);
    final done        = artsProvider.isDownloaded(artifact.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _C.surfaceHi2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.folder_zip_outlined,
                    color: _C.muted, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artifact.name,
                      style: const TextStyle(
                          color: _C.text,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(_fmtSize(artifact.sizeInBytes),
                            style: const TextStyle(
                                color: _C.textDim,
                                fontSize: 11,
                                fontFamily: 'monospace')),
                        const Text(' · ',
                            style: TextStyle(
                                color: _C.textDim, fontSize: 11)),
                        Text(_fmtDate(artifact.createdAt),
                            style: const TextStyle(
                                color: _C.textDim,
                                fontSize: 11,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _C.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _C.blue.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'run #${artifact.runId}',
                            style: const TextStyle(
                                color: _C.blue,
                                fontSize: 9,
                                fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    if (downloading && progress != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: _C.border,
                        color: _C.accent,
                        minHeight: 2,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: _C.accent,
                            fontSize: 10,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botón descarga
              if (downloading)
                const SizedBox(
                  width: 36, height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _C.accent),
                    ),
                  ),
                )
              else if (done)
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _C.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: _C.accent, size: 18),
                )
              else
                GestureDetector(
                  onTap: () => _download(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _C.surfaceHi2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.border),
                    ),
                    child: const Icon(Icons.download_rounded,
                        color: _C.accent, size: 18),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(color: _C.border, height: 1, indent: 62),
      ],
    );
  }

  void _download(BuildContext context) {
    artsProvider.downloadArtifact(
      artifact: artifact,
      owner: owner,
      repo: repo,
      branch: branch,
      onSuccess: (path) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          _buildSnack('✓ ${artifact.name}.zip guardado en Descargas'),
        );
      },
      onError: (err) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(_buildSnack('Error: $err', isError: true));
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _fmtDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'hace ${diff.inDays}d';
    if (diff.inHours > 0) return 'hace ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'hace ${diff.inMinutes}m';
    return 'ahora';
  }
}

class _ArtCenteredMsg extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _ArtCenteredMsg({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _C.textDim, size: 42),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(
                      color: _C.muted,
                      fontSize: 15,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _C.textDim,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.5)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS REUTILIZABLES
// ─────────────────────────────────────────────────────────────────────────────

class _AppLogo extends StatelessWidget {
  const _AppLogo();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _C.accentDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _C.accent.withValues(alpha: 0.5), width: 1),
            ),
            child:
                const Icon(Icons.bolt_rounded, color: _C.accent, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GHA Panel',
                style: TextStyle(
                  color: _C.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'GitHub Actions Runner',
                style: TextStyle(
                  color: _C.muted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
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

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      );
}

class _ConfirmDeleteDialog extends StatelessWidget {
  final String title;
  final String body;

  const _ConfirmDeleteDialog({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _C.border),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: _C.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(
            color: _C.muted,
            fontSize: 13,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: _C.muted, fontSize: 13)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _C.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER SNACKBAR
// ─────────────────────────────────────────────────────────────────────────────

SnackBar _buildSnack(String msg, {bool isError = false}) => SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      backgroundColor: isError ? _C.danger : _C.accent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: Duration(seconds: isError ? 5 : 3),
    );
