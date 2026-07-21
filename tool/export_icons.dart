import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Exports the app icon + tray icons from the design-source geometry
/// (Erebrus AI Logo.dc.html · option 1b "sliced spark").
///
/// Run with:  flutter test tool/export_icons.dart
///
/// Outputs (all under assets/icons/):
///   erebrus-ai-icon-1024.png          – flutter_launcher_icons source
///   tray/tray_icon.png                – 32px color tile (Linux/Windows tray)
///   tray/tray_icon@2x.png             – 64px color tile (HiDPI)
///   tray/tray_icon_template.png       – 22px black glyph (macOS menu bar)
///   tray/tray_icon_template@2x.png    – 44px black glyph
///   tray/tray_icon.ico                – 16/24/32/48/256 (Windows)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export icon set from design geometry', () async {
    final iconsDir = Directory('assets/icons');
    final trayDir = Directory('assets/icons/tray');
    iconsDir.createSync(recursive: true);
    trayDir.createSync(recursive: true);

    // App icon source — 1024, tile radius 34/150 of size, glyph 82/150.
    final appIcon = await _renderTile(1024);
    File('${iconsDir.path}/erebrus-ai-icon-1024.png').writeAsBytesSync(appIcon);

    // Color tray icons (Linux & generic).
    File(
      '${trayDir.path}/tray_icon.png',
    ).writeAsBytesSync(await _renderTile(32));
    File(
      '${trayDir.path}/tray_icon@2x.png',
    ).writeAsBytesSync(await _renderTile(64));

    // macOS template icons — glyph only, pure black + alpha; macOS recolors.
    File(
      '${trayDir.path}/tray_icon_template.png',
    ).writeAsBytesSync(await _renderGlyph(22, const ui.Color(0xFF000000)));
    File(
      '${trayDir.path}/tray_icon_template@2x.png',
    ).writeAsBytesSync(await _renderGlyph(44, const ui.Color(0xFF000000)));

    // Windows .ico — PNG-compressed entries.
    final icoSizes = [16, 24, 32, 48, 256];
    final icoImages = <Uint8List>[];
    for (final s in icoSizes) {
      icoImages.add(await _renderTile(s));
    }
    File(
      '${trayDir.path}/tray_icon.ico',
    ).writeAsBytesSync(_buildIco(icoSizes, icoImages));
  });
}

// ─── Drawing ─────────────────────────────────────────────────────────────────

const _white = ui.Color(0xFFFCFBF9);

/// The sliced-spark glyph paths in their 64×64 viewBox.
ui.Path _sparkTop() => ui.Path()
  ..moveTo(32, 5)
  ..cubicTo(34.4, 20, 41, 27.5, 55.5, 30)
  ..lineTo(8.5, 30)
  ..cubicTo(23, 27.5, 29.6, 20, 32, 5)
  ..close();

/// Bottom half, with the design file's translate(0,-1) applied.
ui.Path _sparkBottom() => ui.Path()
  ..moveTo(59, 33)
  ..cubicTo(43.5, 35.5, 34.6, 43, 32, 58)
  ..cubicTo(29.4, 43, 20.5, 35.5, 5, 33)
  ..close();

void _drawSpark(ui.Canvas canvas, double box, ui.Color color) {
  final paint = ui.Paint()..color = color;
  canvas.save();
  canvas.scale(box / 64);
  canvas.drawPath(_sparkTop(), paint);
  canvas.drawPath(_sparkBottom(), paint);
  canvas.restore();
}

/// Rounded gradient tile with centered white spark — the app icon.
Future<Uint8List> _renderTile(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();

  // CSS linear-gradient(160deg, …): direction 160° clockwise from up;
  // gradient-line length for a square is s·(|sin| + |cos|).
  const dx = 0.34202, dy = 0.93969; // sin160°, -(-cos160°)
  final half = s * (dx + dy) / 2;
  final center = ui.Offset(s / 2, s / 2);
  final gradient = ui.Gradient.linear(
    center - const ui.Offset(dx, dy) * half,
    center + const ui.Offset(dx, dy) * half,
    const [ui.Color(0xFFFF8A50), ui.Color(0xFFFF7E44), ui.Color(0xFFE0531F)],
    const [0.0, 0.3, 1.0],
  );

  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(0, 0, s, s),
      ui.Radius.circular(s * 34 / 150),
    ),
    ui.Paint()..shader = gradient,
  );

  final glyphBox = s * 82 / 150;
  canvas.translate((s - glyphBox) / 2, (s - glyphBox) / 2);
  _drawSpark(canvas, glyphBox, _white);

  return _encodePng(recorder, size);
}

/// Glyph only (no tile) — used for macOS template tray icons.
Future<Uint8List> _renderGlyph(int size, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  final glyphBox = s * 0.9; // slight breathing room in the menu bar
  canvas.translate((s - glyphBox) / 2, (s - glyphBox) / 2);
  _drawSpark(canvas, glyphBox, color);
  return _encodePng(recorder, size);
}

Future<Uint8List> _encodePng(ui.PictureRecorder recorder, int size) async {
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ─── ICO container (PNG-compressed entries) ──────────────────────────────────

Uint8List _buildIco(List<int> sizes, List<Uint8List> pngs) {
  const headerSize = 6;
  const entrySize = 16;
  final dataOffset = headerSize + entrySize * sizes.length;
  final total = dataOffset + pngs.fold<int>(0, (sum, p) => sum + p.length);
  final out = ByteData(total);

  out.setUint16(0, 0, Endian.little); // reserved
  out.setUint16(2, 1, Endian.little); // type: icon
  out.setUint16(4, sizes.length, Endian.little);

  var offset = dataOffset;
  for (var i = 0; i < sizes.length; i++) {
    final base = headerSize + i * entrySize;
    final s = sizes[i];
    out.setUint8(base, s >= 256 ? 0 : s); // width (0 = 256)
    out.setUint8(base + 1, s >= 256 ? 0 : s); // height
    out.setUint8(base + 2, 0); // palette
    out.setUint8(base + 3, 0); // reserved
    out.setUint16(base + 4, 1, Endian.little); // planes
    out.setUint16(base + 6, 32, Endian.little); // bpp
    out.setUint32(base + 8, pngs[i].length, Endian.little);
    out.setUint32(base + 12, offset, Endian.little);
    offset += pngs[i].length;
  }

  final bytes = out.buffer.asUint8List();
  offset = dataOffset;
  for (final png in pngs) {
    bytes.setRange(offset, offset + png.length, png);
    offset += png.length;
  }
  return bytes;
}
