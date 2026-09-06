import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/ui/model_screen.dart';

/// A weights file Van can be pointed at without one existing.
class _FakeModelFile implements ModelFile {
  bool present = false;
  int installs = 0;
  int removes = 0;
  int opened = 0;

  /// What the picker "returns" on the next install. Null means the user
  /// cancelled, which must leave the status exactly as it was.
  bool? picks = true;

  ModelFileStatus get _status => ModelFileStatus(
    present: present,
    path: '/data/user/0/dev.van.app/files/models/gemma-e2b-int4.litertlm',
    bytes: present ? 3221225472 : 0,
    expectedName: 'gemma-e2b-int4.litertlm',
  );

  @override
  Future<ModelFileStatus> status() async => _status;

  @override
  Future<ModelFileStatus> install() async {
    installs++;
    if (picks ?? false) present = true;
    return _status;
  }

  @override
  Future<ModelFileStatus> remove() async {
    removes++;
    present = false;
    return _status;
  }

  @override
  Future<void> openSourcePage() async => opened++;
}

void main() {
  late _FakeModelFile model;

  setUp(() => model = _FakeModelFile());

  /// Scrolls [finder] into view. The page is a two-step flow now and the
  /// things below step two are genuinely off the bottom of a phone, which
  /// means they are not built until they are reached.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ModelScreen(modelFile: model)),
    );
    await tester.pumpAndSettle();
  }

  group('with no weights installed', () {
    testWidgets('says so, and says Van still works', (tester) async {
      await show(tester);

      expect(find.text('Not installed'), findsOneWidget);
      // The line that matters most. Running without a model is the shipped
      // configuration, not a broken one, and a page that implied otherwise
      // would be lying about the product.
      expect(find.textContaining('works fully without this'), findsOneWidget);
    });

    testWidgets('gives two numbered steps, not a filename to go hunt', (
      tester,
    ) async {
      await show(tester);

      // "Download it yourself" with no link is an obstacle, not a rule. Van
      // still makes no request - the browser does - but a tap gets you to the
      // exact page instead of a search.
      expect(find.text('Get the file'), findsOneWidget);
      expect(find.text('Point Van at it'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Open the model page'),
        findsOneWidget,
      );
      expect(find.textContaining('.litertlm'), findsWidgets);
    });

    testWidgets('says the browser does the downloading, not Van', (
      tester,
    ) async {
      await show(tester);

      // The honest version of the constraint. Van has no HTTP client, so it
      // hands a URI to the OS and the vendor's own page presents the licence
      // - which is the only place it can be accepted by the person it binds.
      expect(
        find.textContaining('Van makes no network request of its own'),
        findsOneWidget,
      );
      expect(find.textContaining('Accept the licence there'), findsOneWidget);
    });

    testWidgets('the first step opens the source page', (tester) async {
      await show(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Open the model page'),
      );
      await tester.pumpAndSettle();

      expect(model.opened, 1);
    });

    testWidgets('the URL is on screen even if no browser opens', (
      tester,
    ) async {
      await show(tester);

      // The button is a convenience over the address, not a replacement for
      // it: a phone with no browser, or an intent that is refused, still
      // leaves something to copy.
      expect(
        find.textContaining('huggingface.co/litert-community'),
        findsOneWidget,
      );
    });

    testWidgets('says the download can be called anything', (tester) async {
      await show(tester);

      // Van copies whatever is picked to its own name, so a page that showed
      // its internal filename as "what to look for" would send someone
      // hunting for a name the vendor does not use.
      expect(
        find.textContaining('does not matter what the download is called'),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.textContaining('files/models/gemma-e2b-int4.litertlm'),
      );
      expect(
        find.textContaining('files/models/gemma-e2b-int4.litertlm'),
        findsOneWidget,
      );
    });

    testWidgets('there is nothing to remove', (tester) async {
      await show(tester);

      expect(find.text('Remove it'), findsNothing);
    });

    testWidgets('choosing a file installs it', (tester) async {
      await show(tester);
      await tester.tap(
        find.text('Choose the file'),
      );
      await tester.pumpAndSettle();

      expect(model.installs, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      model.picks = null;

      await show(tester);
      await tester.tap(find.text('Choose the file'));
      await tester.pumpAndSettle();

      expect(find.text('Not installed'), findsOneWidget);
    });
  });

  group('with weights installed', () {
    setUp(() => model.present = true);

    testWidgets('says installed, with a size a person can read', (
      tester,
    ) async {
      await show(tester);

      expect(find.textContaining('Installed'), findsOneWidget);
      expect(find.textContaining('3.0 GB'), findsOneWidget);
    });

    testWidgets('is explicit that nothing is routed to it yet', (tester) async {
      await show(tester);

      // A file on disk is not a model in use. Routing stays at "none" in the
      // config asset until the golden set says otherwise, and a page that let
      // someone assume otherwise would make Van look broken when the
      // deterministic answer arrived.
      expect(
        find.textContaining('nothing is routed to the model'),
        findsOneWidget,
      );
    });

    testWidgets('removing asks first, and says what is lost', (tester) async {
      await show(tester);
      await reveal(tester, find.text('Remove it'));
      await tester.tap(find.text('Remove it'));
      await tester.pumpAndSettle();

      expect(find.text('Remove the model file?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(model.removes, 0);
      // Still there to be tapped again. Asserted on the button rather than
      // the status card, which is now scrolled off the top of the page.
      expect(find.text('Remove it'), findsOneWidget);
    });

    testWidgets('and removes it when confirmed', (tester) async {
      await show(tester);
      await reveal(tester, find.text('Remove it'));
      await tester.tap(find.text('Remove it'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(model.removes, 1);
      expect(find.text('Not installed'), findsOneWidget);
    });
  });

  group('a build with nowhere to put one', () {
    testWidgets('does not throw, and offers nothing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ModelScreen(modelFile: UnsupportedModelFile()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not installed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
