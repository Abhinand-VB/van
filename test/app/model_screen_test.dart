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

  /// A finished download sitting in external storage, unclaimed.
  bool pending = false;

  ModelFileStatus get _status => ModelFileStatus(
    present: present,
    path: '/data/user/0/dev.van.app/files/models/gemma-e2b-int4.litertlm',
    bytes: present ? 3221225472 : 0,
    expectedName: 'gemma-e2b-int4.litertlm',
    pendingDownload: pending,
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

  /// What the next progress poll reports. Drives every download state the
  /// page can be in without a network or a system service.
  DownloadProgress progress = DownloadProgress.idle;
  int downloads = 0;
  int cancels = 0;
  int adopts = 0;

  @override
  Future<DownloadProgress> startDownload() async {
    downloads++;
    return progress = const DownloadProgress(
      state: DownloadState.running,
      bytes: 0,
      total: 2588147712,
    );
  }

  @override
  Future<DownloadProgress> downloadProgress() async => progress;

  @override
  Future<DownloadProgress> cancelDownload() async {
    cancels++;
    return progress = DownloadProgress.idle;
  }

  @override
  Future<ModelFileStatus> adoptDownload() async {
    adopts++;
    present = true;
    pending = false;
    progress = DownloadProgress.idle;
    return _status;
  }
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

    testWidgets('offers one button that downloads it', (tester) async {
      await show(tester);

      // The previous version refused to download and told the user to find a
      // 2.6 GB file themselves. The rule it cited - no network dependency -
      // never meant "no button": Android's DownloadManager does the fetching
      // in its own process, exactly as a browser would.
      expect(
        find.widgetWithText(FilledButton, 'Download the model'),
        findsOneWidget,
      );
      expect(find.textContaining('Gemma 4 E2B, about 2.6 GB'), findsWidgets);
      expect(find.textContaining('works offline'), findsOneWidget);
    });

    testWidgets('pressing it starts a download and shows progress', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Download the model'),
      );
      await tester.pump();

      expect(model.downloads, 1);
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Said out loud, because a phone download that dies when the app is
      // backgrounded is the thing people expect and this one does not.
      expect(
        find.textContaining('carries on if you leave the app'),
        findsOneWidget,
      );
    });

    testWidgets('waiting for Wi-Fi is explained, not left looking stuck', (
      tester,
    ) async {
      model.progress = const DownloadProgress(
        state: DownloadState.paused,
        bytes: 100,
        total: 2588147712,
      );

      await show(tester);

      // A download that has stopped moving is indistinguishable from a broken
      // one unless it says why. 2.6 GB of someone's mobile data is a bill,
      // not a convenience, so waiting is the deliberate behaviour.
      expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
      expect(find.textContaining('mobile data'), findsOneWidget);
    });

    testWidgets('a download can be abandoned', (tester) async {
      model.progress = const DownloadProgress(
        state: DownloadState.running,
        bytes: 100,
        total: 2588147712,
      );

      await show(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(model.cancels, 1);
      expect(
        find.widgetWithText(FilledButton, 'Download the model'),
        findsOneWidget,
      );
    });

    testWidgets('a failed download says so and offers another go', (
      tester,
    ) async {
      model.progress = const DownloadProgress(state: DownloadState.failed);

      await show(tester);

      expect(find.textContaining('That download stopped'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Download the model'),
        findsOneWidget,
      );
    });

    testWidgets('a download finished while the page was shut is claimed', (
      tester,
    ) async {
      // The bug this exists for, reported from the phone: 2,588,147,712 bytes
      // sitting in external storage, `files/models/` not even created, and
      // the page offering to download it again. The only record of the
      // download was a variable on a page that had been disposed.
      model.pending = true;

      await show(tester);

      expect(model.adopts, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Download the model'),
        findsNothing,
      );
    });

    testWidgets('an already-installed model is not re-adopted', (tester) async {
      model
        ..present = true
        ..pending = true;

      await show(tester);

      expect(model.adopts, 0);
    });

    testWidgets('the manual route is still there underneath', (tester) async {
      await show(tester);

      // A computer and a cable is often the better way to move 2.6 GB, and a
      // phone that already has the file should not be made to fetch it twice.
      expect(find.text('Or do it yourself'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Choose a file'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Model page'),
        findsOneWidget,
      );
    });

    testWidgets('the model page still opens in a browser', (tester) async {
      await show(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Model page'));
      await tester.pumpAndSettle();

      expect(model.opened, 1);
    });

    testWidgets('says the download can be called anything', (tester) async {
      await show(tester);

      // Van copies whatever is picked to its own name, so a page that showed
      // its internal filename as "what to look for" would send someone
      // hunting for a name the vendor does not use.
      expect(
        find.textContaining('the download can be called'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a file installs it', (tester) async {
      await show(tester);
      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();

      expect(model.installs, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      model.picks = null;

      await show(tester);
      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();

      expect(find.text('Not installed'), findsOneWidget);
    });

    testWidgets('there is nothing to remove', (tester) async {
      await show(tester);

      expect(find.text('Remove it'), findsNothing);
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
