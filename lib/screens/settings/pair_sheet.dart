import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/local_server_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

/// QR pairing sheet — encodes host + port + API key so another device can
/// connect instantly when multicast/mDNS is blocked.
void showPairSheet(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  const content = _PairContent();
  if (wide) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withA(0.6),
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.strokeHi),
        ),
        child: const SizedBox(width: 360, child: content),
      ),
    );
  } else {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black.withA(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const SafeArea(child: content),
    );
  }
}

class _PairContent extends StatelessWidget {
  const _PairContent();

  String _maskKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 6)}••••••${key.substring(key.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalServerService.instance,
      builder: (context, _) {
        final server = LocalServerService.instance;
        final url = server.baseUrl;
        return FutureBuilder<String>(
          future: server.apiKey,
          builder: (context, keySnapshot) {
            final key = keySnapshot.data ?? '';
            final ready = url != null && key.isNotEmpty;
            final payload = ready ? jsonEncode({'url': url, 'key': key}) : '';
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('PAIR A DEVICE', style: AppText.sectionHeader()),
                  const SizedBox(height: 6),
                  Text(
                    'Scan from Erebrus AI on another device to connect to this node instantly.',
                    textAlign: TextAlign.center,
                    style: AppText.grotesk(
                      12.5,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFBF9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ready
                        ? QrImageView(
                            data: payload,
                            size: 180,
                            backgroundColor: const Color(0xFFFCFBF9),
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0A0A0C),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0A0A0C),
                            ),
                          )
                        : const SizedBox(
                            width: 180,
                            height: 180,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    url?.toUpperCase() ?? 'NODE NOT SERVING',
                    style: AppText.mono(
                      12,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    key.isEmpty ? 'KEY UNAVAILABLE' : 'KEY ${_maskKey(key)}',
                    style: AppText.mono(11, color: AppColors.textMuted),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
