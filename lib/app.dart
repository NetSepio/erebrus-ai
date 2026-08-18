import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/wallet_auth_controller.dart';
import 'org/org_state.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/app_colors.dart';

class ErebrusApp extends StatefulWidget {
  const ErebrusApp({super.key, required this.auth, required this.orgState});

  final WalletAuthController auth;
  final OrgState orgState;

  @override
  State<ErebrusApp> createState() => _ErebrusAppState();
}

class _ErebrusAppState extends State<ErebrusApp> with WidgetsBindingObserver {
  late final AppState _state;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late int _sessionExpiredRevision;

  @override
  void initState() {
    super.initState();
    _state = AppState(auth: widget.auth, orgState: widget.orgState);
    _sessionExpiredRevision = 0;
    widget.auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.auth.sessionExpiredRevision > 0) _onAuthChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_onAuthChanged);
    _state.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.auth.revalidateSession();
    }
  }

  void _onAuthChanged() {
    final revision = widget.auth.sessionExpiredRevision;
    if (revision == _sessionExpiredRevision) return;
    _sessionExpiredRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _messengerKey.currentState;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(kSessionExpiredMessage)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        scaffoldMessengerKey: _messengerKey,
        title: 'Erebrus AI',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: _buildTheme(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: AppColors.bg,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _RootGate(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Space Grotesk',
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.white.withA(0.03),
      dividerColor: AppColors.stroke,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.accentHi,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withA(0.3),
        selectionHandleColor: AppColors.accent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.bgElevated,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// Every platform completes onboarding and configures a default local model
/// before entering the shell.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.localSettingsLoaded) {
      return const ColoredBox(color: AppColors.bg);
    }
    if (!app.onboarded || !app.hasConfiguredDefaultModel) {
      return const OnboardingFlow();
    }
    return Shell(initialTab: app.onboardingTargetTab);
  }
}
