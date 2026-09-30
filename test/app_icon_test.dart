import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/theme/app_theme.dart';

/// The launcher icon is drawn in `tool/icon/*.svg` and rasterised into
/// `android/app/src/main/res/mipmap-*/`.
///
/// The SVGs are in the repo so the icon can be regenerated rather than redrawn
/// blind, and so these tests have something to read. Regenerate with:
///
///   rsvg-convert -w 48  -h 48  tool/icon/backpack.svg \
///       -o android/app/src/main/res/mipmap-mdpi/ic_launcher.png
///   rsvg-convert -w 108 -h 108 tool/icon/backpack_foreground.svg \
///       -o android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png
///
/// (and the same for hdpi 72/162, xhdpi 96/216, xxhdpi 144/324, xxxhdpi 192/432)

Set<String> _coloursIn(String path) {
  final svg = File(path).readAsStringSync();
  return RegExp(r'#[0-9A-Fa-f]{6}')
      .allMatches(svg)
      .map((m) => m.group(0)!.toUpperCase())
      .toSet();
}

/// `#RRGGBB` for a [Color].
///
/// [Color.r] and friends are normalised 0-1 doubles, so each channel has to be
/// scaled back to 0-255 *and* converted to base 16. Skipping the radix
/// conversion produces the decimal digits instead of hex — 240 became "240"
/// rather than "f0" — which then matches nothing in the SVG.
String _hex(Color c) {
  String channel(double v) => (v * 255)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0')
      .toUpperCase();
  return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}

void main() {
  group('the launcher icon stays in the app palette', () {
    test('the legacy icon uses only palette colours', () {
      final palette = {
        _hex(AppColors.carafe),
        _hex(AppColors.cream),
        _hex(AppColors.jet),
        _hex(AppColors.khaki),
        _hex(AppColors.parchment),
        _hex(AppColors.latte),
        _hex(AppColors.mocha),
        _hex(AppColors.sand),
        _hex(AppColors.creamLight),
      };

      final used = _coloursIn('tool/icon/backpack.svg');

      expect(used, isNotEmpty, reason: 'no colours found — is the path right?');
      final offPalette = used.difference(palette);
      expect(
        offPalette,
        isEmpty,
        reason:
            'the icon drifted out of the app palette: ${offPalette.join(', ')}',
      );
    });

    test('the adaptive foreground uses only palette colours', () {
      final palette = {
        _hex(AppColors.carafe),
        _hex(AppColors.cream),
        _hex(AppColors.jet),
        _hex(AppColors.khaki),
      };

      final used = _coloursIn('tool/icon/backpack_foreground.svg');
      expect(used.difference(palette), isEmpty);
    });

    test('it really is the three colours the app is built from', () {
      // Pinned deliberately. If someone repaints the icon and this fails, the
      // new colours are almost certainly not from the palette.
      expect(_coloursIn('tool/icon/backpack.svg'), {
        '#F0E1CA', // cream  — background and front pocket
        '#4B392F', // carafe — the body
        '#2B2722', // jet   — handle, straps, rolled top
      });
    });

    test('the adaptive background matches the icon, not a default blue', () {
      final colours = File('android/app/src/main/res/values/colors.xml')
          .readAsStringSync();
      // Android will happily use a default blue here, which would make the
      // launcher icon disagree with the app entirely.
      expect(colours, contains(_hex(AppColors.cream)));
      expect(colours.toLowerCase(), isNot(contains('3f51b5')));
    });

    test('an adaptive icon exists for Android 8+', () {
      // Without mipmap-anydpi-v26 the launcher masks the legacy PNG, which
      // double-rounds the rounded square already drawn into it.
      expect(
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
            .existsSync(),
        isTrue,
      );
    });

    test('every density has both the icon and the foreground layer', () {
      const sizes = {
        'mdpi': ['48', '108'],
        'hdpi': ['72', '162'],
        'xhdpi': ['96', '216'],
        'xxhdpi': ['144', '324'],
        'xxxhdpi': ['192', '432'],
      };

      for (final entry in sizes.entries) {
        final dir = Directory('android/app/src/main/res/mipmap-${entry.key}');
        expect(dir.existsSync(), isTrue, reason: 'missing mipmap-${entry.key}');
        for (final name in ['ic_launcher.png', 'ic_launcher_foreground.png']) {
          final file = File('${dir.path}/$name');
          expect(
            file.existsSync(),
            isTrue,
            reason: 'missing ${entry.key}/$name',
          );
          expect(
            file.lengthSync(),
            greaterThan(0),
            reason: '${entry.key}/$name is empty',
          );
        }
      }
    });
  });

  group('the phone-visible app name', () {
    test('the launcher label is TBRN', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:label="TBRN"'));
      // The name used to leak the template name.
      expect(manifest, isNot(contains('flutter_application_1"')));
    });

    test('the recent-apps title is TBRN too', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("title: 'TBRN'"));
    });
  });
}
