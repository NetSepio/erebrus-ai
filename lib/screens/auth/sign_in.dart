import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/spark_logo.dart';

/// Opens the sign-in as a full-screen page on every form factor.
/// Every entry point keeps a visible "continue as guest" escape — login is
/// only for private org models and workspace sharing.
void openSignIn(BuildContext context) {
  Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const SignInPage()));
}

Future<void> _doSignIn(BuildContext context, WalletAuthController auth, {String method = 'reown'}) async {
  if (method == 'solana') {
    await auth.openSignIn();
  } else if (method == 'ethereum') {
    await auth.openWalletModal();
  } else if (method == 'google' || method == 'apple' || method == 'email') {
    // Use Reown socials until native OIDC is fully wired; the social wrappers
    // return id tokens the gateway can verify.
    await auth.openWalletModal();
  } else {
    await auth.openSignIn();
  }
  if (auth.isAuthenticated && context.mounted) {
    Navigator.of(context).pop();
  }
}

// ─── Shared pieces ───────────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, this.icon, this.monoGlyph, this.onTap, this.loading = false});

  final String label;
  final IconData? icon;
  final String? monoGlyph;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.strokeHi),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              )
            else if (icon != null)
              Icon(icon, size: 19, color: AppColors.accent)
            else if (monoGlyph != null)
              Text(monoGlyph!,
                  style: AppText.mono(17,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1)),
            const SizedBox(width: 11),
            Text(label,
                style: AppText.grotesk(15, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _WalletDivider extends StatelessWidget {
  const _WalletDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1, color: AppColors.stroke)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('CONNECT A WALLET',
                style: AppText.mono(11,
                    weight: FontWeight.w500,
                    color: AppColors.textFaint,
                    lsEm: 0.15)),
          ),
          const Expanded(child: Divider(height: 1, color: AppColors.stroke)),
        ],
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.name,
    required this.wallets,
    required this.gradient,
    this.primary = false,
    this.onTap,
  });

  final String name;
  final String wallets;
  final Gradient gradient;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent.withA(0.07) : AppColors.surface,
          border: Border.all(
              color: primary ? AppColors.accent.withA(0.45) : Colors.white.withA(0.1)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppText.grotesk(15,
                          weight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(wallets,
                      style: AppText.mono(11,
                          color: AppColors.textTertiary)),
                ],
              ),
            ),
            if (primary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withA(0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('PRIMARY',
                    style: AppText.mono(10,
                        weight: FontWeight.w600,
                        color: AppColors.accent,
                        lsEm: 0.08)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Desktop page ────────────────────────────────────────────────────────────

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final auth = app.auth;
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) => Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmRadial),
        child: Stack(
          children: [
            SafeArea(
              minimum: const EdgeInsets.only(top: 8, left: 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Symbols.arrow_back,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('CONTINUE AS GUEST',
                            style: AppText.mono(11,
                                weight: FontWeight.w500,
                                color: AppColors.textSecondary,
                                lsEm: 0.08)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                          child: LogoTile(size: 56, radius: 16, glow: true)),
                      const SizedBox(height: 18),
                      Center(
                        child: Text('Welcome to Erebrus AI',
                            style: AppText.grotesk(26,
                                weight: FontWeight.w600, lsEm: -0.02)),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'Sign in to access private workspace models and share yours with your team.',
                            textAlign: TextAlign.center,
                            style: AppText.grotesk(14,
                                color: AppColors.textTertiary, height: 1.45),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _AuthButton(
                          label: 'Continue with Email',
                          icon: Symbols.mail,
                          loading: auth.isAuthenticating || auth.awaitingWebCallback,
                          onTap: () => _doSignIn(context, auth, method: 'email')),
                      const SizedBox(height: 11),
                      _AuthButton(
                          label: 'Continue with Google',
                          monoGlyph: 'G',
                          loading: auth.isAuthenticating,
                          onTap: () => _doSignIn(context, auth, method: 'google')),
                      const _WalletDivider(),
                      _WalletCard(
                        name: 'Solana',
                        wallets: 'Phantom · Solflare · Backpack',
                        gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.solanaA, AppColors.solanaB]),
                        primary: true,
                        onTap: () => _doSignIn(context, auth, method: 'solana'),
                      ),
                      const SizedBox(height: 11),
                      _WalletCard(
                        name: 'Ethereum',
                        wallets: 'MetaMask · WalletConnect',
                        gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.ethereumA, AppColors.ethereumB]),
                        onTap: () => _doSignIn(context, auth, method: 'ethereum'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'By continuing you agree to Erebrus’s\nTerms of Service & Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: AppText.grotesk(11.5,
                            color: AppColors.textFaint, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

