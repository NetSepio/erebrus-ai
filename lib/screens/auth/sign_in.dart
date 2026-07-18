import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/spark_logo.dart';

/// Opens the sign-in surface appropriate to the current form factor:
/// full page on desktop, bottom sheet on mobile. Every entry point keeps a
/// visible "continue as guest" escape — login is only for private org models
/// and workspace sharing.
void openSignIn(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  if (wide) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const SignInPage()));
  } else {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF050507).withValues(alpha: 0.7),
      builder: (_) => const SignInSheet(),
    );
  }
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
  const _AuthButton({required this.label, this.icon, this.monoGlyph, this.compact = false, this.onTap, this.loading = false});

  final String label;
  final IconData? icon;
  final String? monoGlyph;
  final bool compact;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: EdgeInsets.all(compact ? 14 : 15),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: AppColors.strokeHi),
          borderRadius: BorderRadius.circular(compact ? 13 : 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: compact ? 18 : 19,
                height: compact ? 18 : 19,
                child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              )
            else if (icon != null)
              Icon(icon, size: compact ? 18 : 19, color: AppColors.accent)
            else if (monoGlyph != null)
              Text(monoGlyph!,
                  style: AppText.mono(compact ? 16 : 17,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1)),
            SizedBox(width: compact ? 10 : 11),
            Text(label,
                style: AppText.grotesk(compact ? 14.5 : 15, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _WalletDivider extends StatelessWidget {
  const _WalletDivider({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1, color: AppColors.stroke)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
            child: Text('CONNECT A WALLET',
                style: AppText.mono(compact ? 10 : 11,
                    weight: FontWeight.w500, color: AppColors.textFaint, lsEm: 0.15)),
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
    this.compact = false,
    this.onTap,
  });

  final String name;
  final String wallets;
  final Gradient gradient;
  final bool primary;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 13)
            : const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent.withA(0.07) : AppColors.surface,
          border: Border.all(
              color: primary ? AppColors.accent.withA(0.45) : Colors.white.withA(0.1)),
          borderRadius: BorderRadius.circular(compact ? 13 : 14),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 32 : 34,
              height: compact ? 32 : 34,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            SizedBox(width: compact ? 12 : 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppText.grotesk(compact ? 14.5 : 15,
                          weight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(wallets,
                      style: AppText.mono(compact ? 10 : 11,
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
                    style: AppText.mono(compact ? 9.5 : 10,
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
            Positioned(
              top: 18,
              left: 22,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Row(
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

// ─── Mobile bottom sheet ─────────────────────────────────────────────────────

class SignInSheet extends StatelessWidget {
  const SignInSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final auth = app.auth;
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
        ),
        padding: EdgeInsets.only(
          top: 14,
          left: 22,
          right: 22,
          bottom: 34 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withA(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const LogoTile(size: 40, radius: 12),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sign in to Erebrus',
                        style: AppText.grotesk(18, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Only needed for private workspace models.',
                        style: AppText.grotesk(12.5, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _AuthButton(
                label: 'Continue with Email',
                icon: Symbols.mail,
                compact: true,
                loading: auth.isAuthenticating || auth.awaitingWebCallback,
                onTap: () => _doSignIn(context, auth, method: 'email')),
            const SizedBox(height: 10),
            _AuthButton(
                label: 'Continue with Google',
                monoGlyph: 'G',
                compact: true,
                loading: auth.isAuthenticating,
                onTap: () => _doSignIn(context, auth, method: 'google')),
            const _WalletDivider(compact: true),
            _WalletCard(
              name: 'Solana',
              wallets: 'SEED VAULT · PHANTOM · SOLFLARE',
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.solanaA, AppColors.solanaB]),
              primary: true,
              compact: true,
              onTap: () => _doSignIn(context, auth, method: 'solana'),
            ),
            const SizedBox(height: 10),
            _WalletCard(
              name: 'Ethereum',
              wallets: 'METAMASK · WALLETCONNECT',
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.ethereumA, AppColors.ethereumB]),
              compact: true,
              onTap: () => _doSignIn(context, auth, method: 'ethereum'),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: Text('NOT NOW — KEEP USING AS GUEST',
                    style: AppText.mono(11,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted,
                        lsEm: 0.08)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
