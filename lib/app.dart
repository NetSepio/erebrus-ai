import 'package:flutter/material.dart';

import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/app_colors.dart';

class ErebrusApp extends StatefulWidget {
  const ErebrusApp({super.key});

  @override
  State<ErebrusApp> createState() => _ErebrusAppState();
}

class _ErebrusAppState extends State<ErebrusApp> {
  final _state = AppState();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Erebrus AI',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
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

/// First launch on a phone-sized layout shows onboarding; desktop goes straight
/// to the shell. Onboarding is skippable everywhere — guest-first.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kDesktopBreakpoint;
        if (!wide && !app.onboarded) return const OnboardingFlow();
        return const Shell();
      },
    );
  }
}
