import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van/platform/model_file.dart';
import 'package:van/ui/model_screen.dart';

/// A weights file Van can be pointed at without one existing.
class _FakeModelFile implements ModelFile {
  bool present = false;
  int installs = 0;
  int removes = 0;

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
}

void main() {
  late _FakeModelFile model;

  setUp(() => model = _FakeModelFile());

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

    testWidgets('explains why there is no download button', (tester) async {
      await show(tester);

      // Two reasons, both real, and the page says them rather than leaving
      // the missing button as a puzzle: Van has no network access at all, and
      // the licence is the user's to accept.
      expect(find.textContaining('will not download it for you'), findsWidgets);
      expect(find.textContaining('licence-gated'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Choose the file'),
        findsOneWidget,
      );
    });

    testWidgets('names the exact file and where it goes', (tester) async {
      await show(tester);

      expect(find.text('gemma-e2b-int4.litertlm'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(FilledButton, 'Choose the file'));
      await tester.pumpAndSettle();

      expect(model.installs, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      model.picks = null;

      await show(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Choose the file'));
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
      await tester.tap(find.text('Remove it'));
      await tester.pumpAndSettle();

      expect(find.text('Remove the model file?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(model.removes, 0);
      expect(find.textContaining('Installed'), findsOneWidget);
    });

    testWidgets('and removes it when confirmed', (tester) async {
      await show(tester);
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
