import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout targets used by the widget tests.
///
/// The app was originally exercised at 1400x1800, a size no phone has. Every
/// layout bug below would therefore have stayed invisible until the app ran on
/// a real device. These are the sizes a phone actually reports, so the tests
/// fail here instead of in someone's hand.
class TestViewports {
  TestViewports._();

  /// Working layout target. A typical modern phone in portrait, in logical
  /// pixels.
  static const Size phonePortrait = Size(412, 915);

  /// Worst realistic case: a small or older phone, and the tightest vertical
  /// room. Anything that fits everywhere fits here.
  static const Size phoneSmall = Size(360, 640);

  /// Phone turned sideways. Height is the scarce axis, so this catches
  /// vertical overflow that portrait hides.
  static const Size phoneLandscape = Size(915, 412);

  /// The original oversized target, kept only so a test that genuinely needs
  /// room (a very wide legend, a stress test) can say so explicitly rather
  /// than by accident.
  static const Size oversized = Size(1400, 1800);
}

/// Applies [size] to the test view and registers the teardown.
///
/// Always call this instead of assigning `tester.view.physicalSize` inline:
/// a test that sets the size and forgets to reset it leaks into every later
/// test in the file, which is how a "passing" suite can be measuring a layout
/// nobody ships.
void useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  // devicePixelRatio 1.0 makes physicalSize and logical size identical, so
  // these constants can be read directly as logical pixels.
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.reset());
}

/// Records the "overflowed by N pixels" reports raised during a test.
///
/// Flutter already fails a `testWidgets` body when a `RenderFlex` overflows,
/// but it does so one frame at a time, and the report is easy to lose track of
/// in a long suite. This keeps the messages so [expectNoOverflow] can name
/// them all at once. Reports are always forwarded to the previous handler, so
/// nothing that currently fails stops failing.
class OverflowWatch {
  OverflowWatch._(this._messages);

  final List<String> _messages;

  /// The "…overflowed by N pixels…" lines reported during this test, newest
  /// last. Empty when nothing overflowed.
  List<String> get messages => List.unmodifiable(_messages);

  /// Installs the recorder for the current test. Restores the previous handler
  /// in a teardown, so it cannot leak into another test.
  static OverflowWatch install() {
    final messages = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        messages.add(_firstLine(text));
      }
      // Always forward. The framework's own failure must never be swallowed.
      previous?.call(details);
    };
    final watch = OverflowWatch._(messages);
    addTearDown(() => FlutterError.onError = previous);
    return watch;
  }

  static String _firstLine(String text) => text.split('\n').first.trim();
}

/// Fails the test if any flex in the render tree is overflowing.
///
/// This walks the tree rather than relying on the framework's paint-time
/// report, because that report only covers what was actually laid out: a row
/// below the fold in a lazy list, or a widget hidden behind a tab, is never
/// painted and so never complains. [watch] contributes the exact pixel counts
/// for anything the framework did report.
///
/// Detection relies on [RenderObject.toStringShort], which RenderFlex extends
/// with ` OVERFLOWING` outside release mode. That is a public API, unlike the
/// `_hasOverflow` field behind it.
void expectNoOverflow(
  WidgetTester tester, {
  OverflowWatch? watch,
  String? because,
}) {
  final overflowing = <String>[];

  for (final element in tester.allElements) {
    final render = element.renderObject;
    if (render == null) continue;
    if (render.toStringShort().contains('OVERFLOWING')) {
      overflowing.add('${element.toStringShort()} (${render.runtimeType})');
    }
  }

  if (overflowing.isEmpty) return;

  final reported = watch == null || watch.messages.isEmpty
      ? ''
      : '\n  reported: ${watch.messages.join('\n  reported: ')}';

  fail(
    'Layout overflow at the test viewport.\n'
    '  ${overflowing.join('\n  ')}$reported\n'
    '${because == null ? '' : '  $because\n'}'
    'Overflow is invisible in a widget test unless it is asserted, and it '
    'reaches the user as a black-and-yellow stripe.',
  );
}

/// Sets the viewport and makes an overflow anywhere in the tree a test failure.
///
/// One call per widget test, so no test can forget the check. The assertion
/// runs as a teardown, which means it covers whatever the test body left on
/// screen without having to be repeated at the end of every test.
void usePhoneLayout(WidgetTester tester, Size size, {String? because}) {
  useViewport(tester, size);
  final watch = OverflowWatch.install();
  addTearDown(() => expectNoOverflow(tester, watch: watch, because: because));
}
