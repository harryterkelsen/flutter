// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_e2e_tests/hit_test_proxy_main.dart' as app;

/// How long to wait for a click to reach (or not reach) a platform view.
const Duration _clickSettleTime = Duration(milliseconds: 500);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Asks the host driver to perform a real WebDriver click at [position],
  /// in viewport (CSS pixel) coordinates.
  ///
  /// The request travels over the integration_test WebDriver command channel;
  /// the host's `onScreenshot` callback performs the click and completes the
  /// request once the browser has dispatched the pointer events.
  Future<void> realClick(WidgetTester tester, String name, Offset position) async {
    await binding.takeScreenshot(name, <String, Object?>{
      'x': position.dx.round(),
      'y': position.dy.round(),
    });
    await Future<void>.delayed(_clickSettleTime);
    await tester.pumpAndSettle();
  }

  // Semantics stay off, as in an app without assistive technology: with
  // semantics on, the dialog's ARIA nodes intercept clicks above every
  // platform view (including PV2), which hides what this test checks.
  testWidgets(
    'real clicks over a platform view under a dialog reach Flutter, not the platform view',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      // Browser pointer events must reach the app, not just the test binding.
      binding.shouldPropagateDevicePointerEvents = true;
      addTearDown(() => binding.shouldPropagateDevicePointerEvents = false);

      app.main();
      await tester.pumpAndSettle();
      await app.pv1Loaded.timeout(const Duration(seconds: 10));

      // Control: with nothing painted over it, PV1 receives a real click.
      final Offset pv1Point = tester.getCenter(find.byType(HtmlElementView));
      await realClick(tester, 'click_pv1_uncovered', pv1Point);
      expect(app.pv1Clicks, 1, reason: 'A real click on uncovered PV1 must reach its document.');

      app.openDialog();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await app.pv2Loaded.timeout(const Duration(seconds: 10));

      final Offset pv2Center = tester.getCenter(find.byKey(app.pv2Key));
      final Offset dialogBodyPoint = tester.getCenter(find.byKey(app.dialogTitleKey));
      const barrierPoint = Offset(20, 20);
      // The dialog's surface, not the full-screen Dialog widget (which includes
      // its insets), must leave the barrier point uncovered.
      final Finder dialogSurface = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first;
      expect(tester.getRect(dialogSurface).contains(barrierPoint), isFalse);

      // 1. A real click at PV2's center increments PV2's counter.
      await realClick(tester, 'click_pv2_center', pv2Center);
      final int pv2ClicksAfterPv2Click = app.pv2Clicks;

      // 2. A click on the dialog body over PV1 doesn't increment PV1's counter.
      await realClick(tester, 'click_dialog_body', dialogBodyPoint);
      final int pv1ClicksAfterDialogBodyClick = app.pv1Clicks;
      final bool dialogOpenAfterDialogBodyClick = find.byType(Dialog).evaluate().isNotEmpty;

      // 3. A real click on the barrier over PV1 closes the dialog, and PV1's
      // counter is unchanged.
      await realClick(tester, 'click_barrier', barrierPoint);
      final int pv1ClicksAfterBarrierClick = app.pv1Clicks;
      final bool dialogOpenAfterBarrierClick = find.byType(Dialog).evaluate().isNotEmpty;

      // Compared together so that every failed expectation is reported at once.
      expect(
        <String, Object>{
          '1. PV2 clicks after clicking PV2 center': pv2ClicksAfterPv2Click,
          '2. PV1 clicks after clicking the dialog body': pv1ClicksAfterDialogBodyClick,
          '2. dialog open after clicking the dialog body': dialogOpenAfterDialogBodyClick,
          '3. PV1 clicks after clicking the barrier': pv1ClicksAfterBarrierClick,
          '3. dialog open after clicking the barrier': dialogOpenAfterBarrierClick,
        },
        <String, Object>{
          '1. PV2 clicks after clicking PV2 center': 1,
          '2. PV1 clicks after clicking the dialog body': 1,
          '2. dialog open after clicking the dialog body': true,
          '3. PV1 clicks after clicking the barrier': 1,
          '3. dialog open after clicking the barrier': false,
        },
      );
    },
  );
}
