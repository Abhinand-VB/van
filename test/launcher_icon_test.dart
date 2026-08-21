import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The densities Android expects, and the pixel size each one wants.
const densities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Deep forest green: `ic_launcher_background` in `values/colors.xml`.
const brandBackground = (0x14, 0x34, 0x2A);

File iconFor(String density) =>
    File('android/app/src/main/res/mipmap-$density/ic_launcher.png');

({int width, int height}) pngSize(Uint8List bytes) => (
  width: ByteData.sublistView(bytes, 16, 20).getUint32(0),
  height: ByteData.sublistView(bytes, 20, 24).getUint32(0),
);

/// The top-left pixel, decoded out of a filter-type-0 truecolour PNG.
///
/// Narrow on purpose: it only understands the PNGs
/// `tool/generate_launcher_icons.py` writes, and throws rather than guessing
/// at anything else.
(int, int, int) topLeftPixel(Uint8List bytes) {
  // IHDR payload starts at byte 16: width, height, then depth and type.
  expect(bytes[24], 8, reason: 'expected 8-bit channels');
  expect(bytes[25], 2, reason: 'expected truecolour RGB');

  var offset = 8;
  while (offset < bytes.length) {
    final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    final tag = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (tag == 'IDAT') {
      final data = bytes.sublist(offset + 8, offset + 8 + length);
      final raw = zlib.decode(data);
      expect(raw[0], 0, reason: 'expected filter type 0 on the first row');
      return (raw[1], raw[2], raw[3]);
    }
    offset += 12 + length;
  }
  throw StateError('no IDAT chunk');
}

void main() {
  group('the legacy launcher icons', () {
    test('exist at every density Android asks for', () {
      for (final density in densities.keys) {
        expect(
          iconFor(density).existsSync(),
          isTrue,
          reason: 'mipmap-$density/ic_launcher.png is missing',
        );
      }
    });

    test('are the size their density expects', () {
      densities.forEach((density, expected) {
        final size = pngSize(iconFor(density).readAsBytesSync());
        expect(size.width, expected, reason: '$density width');
        expect(size.height, expected, reason: '$density height');
      });
    });

    test('are Van, not Flutter', () {
      // The check that matters. These shipped as Flutter's default logo for
      // the whole life of the project because nothing ever looked at them.
      // Flutter's icon is white in the corner; Van's is forest green.
      for (final density in densities.keys) {
        expect(
          topLeftPixel(iconFor(density).readAsBytesSync()),
          brandBackground,
          reason:
              'mipmap-$density/ic_launcher.png does not start with the brand '
              'background - has it been overwritten by `flutter create`? '
              'Re-run tool/generate_launcher_icons.py',
        );
      }
    });

    test('the adaptive icon still points at the vector mark', () {
      // Above API 26 this is what actually draws, and it is the source the
      // PNGs are generated from.
      final adaptive = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(
        File(
          'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
        ).existsSync(),
        isTrue,
      );
    });
  });
}
