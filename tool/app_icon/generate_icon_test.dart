// Renders the ClockMate app icon to PNG for iOS and the Android legacy mipmaps.
// Android 8+ uses the vector adaptive icon in res/drawable/ic_launcher_*.xml,
// which draws the same shapes; keep the two in sync.
//
// Run from the project root:
//   flutter test tool/app_icon/generate_icon_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const purpleLight = ui.Color(0xFFA855F7);
const purpleDark = ui.Color(0xFF5B21B6);
const mint = ui.Color(0xFF5EEAD4);
const white = ui.Color(0xFFFFFFFF);

/// Draws the artwork on the 108-unit adaptive-icon grid.
void paintArtwork(ui.Canvas canvas) {
  final ring = ui.Paint()
    ..color = white
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 5;
  canvas.drawCircle(const ui.Offset(54, 57), 22, ring);

  // Alarm bells: half-discs above the ring, tilted outwards.
  final bell = ui.Paint()..color = white;
  for (final angle in const [-135.0, -45.0]) {
    final rad = angle * math.pi / 180;
    canvas
      ..save()
      ..translate(54 + 27 * math.cos(rad), 57 + 27 * math.sin(rad))
      ..rotate((angle + 90) * math.pi / 180)
      ..drawArc(ui.Rect.fromCircle(center: ui.Offset.zero, radius: 7.5), math.pi, math.pi, true, bell)
      ..restore();
  }

  final check = ui.Path()
    ..moveTo(44, 57.5)
    ..lineTo(51, 64.5)
    ..lineTo(64.5, 50);
  canvas.drawPath(
    check,
    ui.Paint()
      ..color = mint
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round,
  );
}

/// The full icon at [size] px. iOS icons are square (the system rounds them);
/// [rounded] gives Android's pre-8.0 launchers a rounded square.
Future<Uint8List> renderIcon(int size, {bool rounded = false, bool opaque = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  final bounds = ui.Rect.fromLTWH(0, 0, s, s);
  final background = ui.Paint()
    ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(s, s), [purpleLight, purpleDark]);
  if (rounded) {
    canvas.drawRRect(ui.RRect.fromRectAndRadius(bounds, ui.Radius.circular(s * 0.22)), background);
  } else {
    canvas.drawRect(bounds, background);
  }
  // Show the middle 80 units of the 108 grid: what an adaptive mask shows.
  canvas
    ..scale(s / 80)
    ..translate(-14, -14);
  paintArtwork(canvas);

  final image = await recorder.endRecording().toImage(size, size);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  return encodePng(rgba.buffer.asUint8List(), size, size, alpha: !opaque);
}

/// Minimal PNG encoder, so the App Store icon can be saved without an alpha
/// channel (Apple rejects icons that have one).
Uint8List encodePng(Uint8List rgba, int width, int height, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // no filter
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw.add(rgba.sublist(i, i + channels));
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw.takeBytes()))))
    ..add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return Uint8List.fromList([...length.buffer.asUint8List(), ...typeBytes, ...data, ...crc.buffer.asUint8List()]);
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void main() {
  testWidgets('generate app icons', (tester) async {
    await tester.runAsync(() async {
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      const iosIcons = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
      };
      for (final MapEntry(key: name, value: size) in iosIcons.entries) {
        File('$ios/$name').writeAsBytesSync(await renderIcon(size));
      }

      const android = 'android/app/src/main/res';
      const androidIcons = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final MapEntry(key: density, value: size) in androidIcons.entries) {
        File('$android/mipmap-$density/ic_launcher.png')
            .writeAsBytesSync(await renderIcon(size, rounded: true, opaque: false));
      }
      // Preview for docs and stores.
      File('tool/app_icon/icon_preview.png').writeAsBytesSync(await renderIcon(512, rounded: true, opaque: false));
    });
  });
}
