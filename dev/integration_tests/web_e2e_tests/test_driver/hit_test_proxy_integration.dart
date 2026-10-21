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

  /// A point over PV1 that the overlays opened by the scenarios below leave
  /// uncovered, so that a click there lands on their modal barrier.
  const barrierPoint = Offset(20, 20);

  /// Lets browser pointer events reach the app, not just the test binding,
  /// for the rest of the current test.
  void propagateBrowserPointerEvents() {
    binding.shouldPropagateDevicePointerEvents = true;
    addTearDown(() => binding.shouldPropagateDevicePointerEvents = false);
  }

  /// Starts the app with the full-screen PV1, and checks that a real click on
  /// PV1 reaches it while nothing is painted over it.
  Future<void> startPv1App(WidgetTester tester) async {
    propagateBrowserPointerEvents();

    app.main();
    await tester.pumpAndSettle();
    await app.pv1Loaded.timeout(const Duration(seconds: 10));

    final Offset pv1Point = tester.getCenter(find.byType(HtmlElementView));
    await realClick(tester, 'click_pv1_uncovered', pv1Point);
    expect(app.pv1Clicks, 1, reason: 'A real click on uncovered PV1 must reach its document.');
  }

  // Semantics stay off, as in an app without assistive technology: with
  // semantics on, the dialog's ARIA nodes intercept clicks above every
  // platform view (including PV2), which hides what this test checks.
  testWidgets(
    'real clicks over a platform view under a dialog reach Flutter, not the platform view',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      // Control: with nothing painted over it, PV1 receives a real click.
      await startPv1App(tester);

      app.openDialog();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await app.pv2Loaded.timeout(const Duration(seconds: 10));

      final Offset pv2Center = tester.getCenter(find.byKey(app.pv2Key));
      final Offset dialogBodyPoint = tester.getCenter(find.byKey(app.dialogTitleKey));
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

  testWidgets(
    'real clicks over a platform view under a modal bottom sheet reach Flutter',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      await startPv1App(tester);

      app.openBottomSheet();
      await tester.pumpAndSettle();
      final Finder sheet = find.byKey(app.bottomSheetKey);
      expect(sheet, findsOneWidget);
      expect(tester.getRect(find.byType(BottomSheet)).contains(barrierPoint), isFalse);

      // 1. A click on the sheet over PV1 keeps the sheet open and doesn't
      // reach PV1.
      await realClick(tester, 'click_bottom_sheet_body', tester.getCenter(sheet));
      final int pv1ClicksAfterSheetClick = app.pv1Clicks;
      final bool sheetOpenAfterSheetClick = sheet.evaluate().isNotEmpty;

      // 2. A click on the barrier over PV1 dismisses the sheet and doesn't
      // reach PV1.
      await realClick(tester, 'click_bottom_sheet_barrier', barrierPoint);
      final int pv1ClicksAfterBarrierClick = app.pv1Clicks;
      final bool sheetOpenAfterBarrierClick = sheet.evaluate().isNotEmpty;

      expect(
        <String, Object>{
          '1. PV1 clicks after clicking the sheet': pv1ClicksAfterSheetClick,
          '1. sheet open after clicking the sheet': sheetOpenAfterSheetClick,
          '2. PV1 clicks after clicking the barrier': pv1ClicksAfterBarrierClick,
          '2. sheet open after clicking the barrier': sheetOpenAfterBarrierClick,
        },
        <String, Object>{
          '1. PV1 clicks after clicking the sheet': 1,
          '1. sheet open after clicking the sheet': true,
          '2. PV1 clicks after clicking the barrier': 1,
          '2. sheet open after clicking the barrier': false,
        },
      );
    },
  );

  testWidgets(
    'real clicks over a platform view under a popup menu select items and dismiss it',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      await startPv1App(tester);

      app.openMenu();
      await tester.pumpAndSettle();
      final Finder betaItem = find.text('Beta');
      expect(betaItem, findsOneWidget);

      // 1. A click on a menu item over PV1 selects it and doesn't reach PV1.
      await realClick(tester, 'click_menu_item', tester.getCenter(betaItem));
      final int pv1ClicksAfterItemClick = app.pv1Clicks;
      final bool menuOpenAfterItemClick = betaItem.evaluate().isNotEmpty;
      final int menuClosedCountAfterItemClick = app.menuClosedCount;
      final selectionAfterItemClick = '${app.lastMenuSelection}';

      // 2. A click on the barrier over PV1 dismisses the menu without a
      // selection and doesn't reach PV1.
      app.openMenu();
      await tester.pumpAndSettle();
      expect(betaItem, findsOneWidget);
      expect(
        tester.getRect(find.byType(PopupMenuItem<String>).first).contains(barrierPoint),
        isFalse,
      );
      await realClick(tester, 'click_menu_barrier', barrierPoint);
      final int pv1ClicksAfterBarrierClick = app.pv1Clicks;
      final bool menuOpenAfterBarrierClick = betaItem.evaluate().isNotEmpty;
      final int menuClosedCountAfterBarrierClick = app.menuClosedCount;
      final selectionAfterBarrierClick = '${app.lastMenuSelection}';

      expect(
        <String, Object>{
          '1. PV1 clicks after clicking the item': pv1ClicksAfterItemClick,
          '1. menu open after clicking the item': menuOpenAfterItemClick,
          '1. menu closed count after clicking the item': menuClosedCountAfterItemClick,
          '1. selection after clicking the item': selectionAfterItemClick,
          '2. PV1 clicks after clicking the barrier': pv1ClicksAfterBarrierClick,
          '2. menu open after clicking the barrier': menuOpenAfterBarrierClick,
          '2. menu closed count after clicking the barrier': menuClosedCountAfterBarrierClick,
          '2. selection after clicking the barrier': selectionAfterBarrierClick,
        },
        <String, Object>{
          '1. PV1 clicks after clicking the item': 1,
          '1. menu open after clicking the item': false,
          '1. menu closed count after clicking the item': 1,
          '1. selection after clicking the item': 'Beta',
          '2. PV1 clicks after clicking the barrier': 1,
          '2. menu open after clicking the barrier': false,
          '2. menu closed count after clicking the barrier': 2,
          '2. selection after clicking the barrier': 'null',
        },
      );
    },
  );

  testWidgets(
    'real clicks over a platform view open a DropdownButton and select an item',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      await startPv1App(tester);

      // 1. A click on the dropdown button over PV1 opens its menu and doesn't
      // reach PV1.
      final Offset buttonPoint = tester.getCenter(find.text('Selected: One'));
      await realClick(tester, 'click_dropdown_button', buttonPoint);
      final int pv1ClicksAfterButtonClick = app.pv1Clicks;
      final Finder twoItem = find.text('Two');
      final bool menuOpenAfterButtonClick = twoItem.evaluate().isNotEmpty;

      // 2. A click on a menu item over PV1 selects it and doesn't reach PV1.
      // This step needs the menu that step 1 opens.
      Object pv1ClicksAfterItemClick = 'not run: the menu did not open';
      Object menuOpenAfterItemClick = 'not run: the menu did not open';
      if (menuOpenAfterButtonClick) {
        await realClick(tester, 'click_dropdown_item', tester.getCenter(twoItem));
        pv1ClicksAfterItemClick = app.pv1Clicks;
        menuOpenAfterItemClick = twoItem.evaluate().isNotEmpty;
      }
      final String valueAfterItemClick = app.dropdownValue.value;

      expect(
        <String, Object>{
          '1. PV1 clicks after clicking the button': pv1ClicksAfterButtonClick,
          '1. menu open after clicking the button': menuOpenAfterButtonClick,
          '2. PV1 clicks after clicking the item': pv1ClicksAfterItemClick,
          '2. menu open after clicking the item': menuOpenAfterItemClick,
          '2. value after clicking the item': valueAfterItemClick,
        },
        <String, Object>{
          '1. PV1 clicks after clicking the button': 1,
          '1. menu open after clicking the button': true,
          '2. PV1 clicks after clicking the item': 1,
          '2. menu open after clicking the item': false,
          '2. value after clicking the item': 'Two',
        },
      );
    },
  );

  testWidgets(
    'real clicks over a platform view under a general dialog reach Flutter',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      await startPv1App(tester);

      app.openGeneralDialog();
      await tester.pumpAndSettle();
      final Finder dialog = find.byKey(app.generalDialogKey);
      expect(dialog, findsOneWidget);
      final Rect dialogRect = tester.getRect(dialog);
      expect(dialogRect.contains(barrierPoint), isFalse);
      // A point on the dialog's background, away from its text and button.
      final Offset dialogBodyPoint = dialogRect.topLeft + const Offset(10, 10);

      // 1. A click on the dialog's background over PV1 keeps it open and
      // doesn't reach PV1.
      await realClick(tester, 'click_general_dialog_body', dialogBodyPoint);
      final int pv1ClicksAfterBodyClick = app.pv1Clicks;
      final bool dialogOpenAfterBodyClick = dialog.evaluate().isNotEmpty;

      // 2. A click on the dialog's button over PV1 presses it and doesn't
      // reach PV1.
      await realClick(
        tester,
        'click_general_dialog_button',
        tester.getCenter(find.byKey(app.generalDialogButtonKey)),
      );
      final int pv1ClicksAfterButtonClick = app.pv1Clicks;
      final int buttonPressesAfterButtonClick = app.generalDialogButtonPresses;
      final bool dialogOpenAfterButtonClick = dialog.evaluate().isNotEmpty;

      // 3. A click on the barrier over PV1 dismisses the dialog and doesn't
      // reach PV1.
      await realClick(tester, 'click_general_dialog_barrier', barrierPoint);
      final int pv1ClicksAfterBarrierClick = app.pv1Clicks;
      final bool dialogOpenAfterBarrierClick = dialog.evaluate().isNotEmpty;

      expect(
        <String, Object>{
          '1. PV1 clicks after clicking the dialog body': pv1ClicksAfterBodyClick,
          '1. dialog open after clicking the dialog body': dialogOpenAfterBodyClick,
          '2. PV1 clicks after clicking the button': pv1ClicksAfterButtonClick,
          '2. button presses after clicking the button': buttonPressesAfterButtonClick,
          '2. dialog open after clicking the button': dialogOpenAfterButtonClick,
          '3. PV1 clicks after clicking the barrier': pv1ClicksAfterBarrierClick,
          '3. dialog open after clicking the barrier': dialogOpenAfterBarrierClick,
        },
        <String, Object>{
          '1. PV1 clicks after clicking the dialog body': 1,
          '1. dialog open after clicking the dialog body': true,
          '2. PV1 clicks after clicking the button': 1,
          '2. button presses after clicking the button': 1,
          '2. dialog open after clicking the button': true,
          '3. PV1 clicks after clicking the barrier': 1,
          '3. dialog open after clicking the barrier': false,
        },
      );
    },
  );

  testWidgets(
    'real clicks on a pinned app bar and a FAB over scrolled platform views reach Flutter',
    semanticsEnabled: false,
    (WidgetTester tester) async {
      propagateBrowserPointerEvents();

      app.mainScrolledList();
      await tester.pumpAndSettle();
      final builtItems = <int>[
        for (var index = 0; index < app.listItemCount; index++)
          if (find.byKey(app.listItemKey(index)).evaluate().isNotEmpty) index,
      ];
      await Future.wait(<Future<void>>[
        for (final int index in builtItems) app.listItemLoaded(index),
      ]).timeout(const Duration(seconds: 10));
      int itemClicks(int index) => app.listItemClicks[index] ?? 0;

      final Rect appBarRect = tester.getRect(find.byType(AppBar));
      final Rect item0Rect = tester.getRect(find.byKey(app.listItemKey(0)));
      final Rect actionRect = tester.getRect(find.byKey(app.appBarActionKey));
      final Offset actionPoint = actionRect.center;
      // The middle of the app bar, between its title and its action.
      final Offset appBarPoint = appBarRect.center;
      expect(actionRect.contains(appBarPoint), isFalse);
      // The first item is scrolled partially under the pinned app bar.
      expect(item0Rect.contains(actionPoint), isTrue);
      expect(item0Rect.contains(appBarPoint), isTrue);
      expect(item0Rect.bottom, greaterThan(appBarRect.bottom));
      final item0UncoveredPoint = Offset(
        item0Rect.center.dx,
        (appBarRect.bottom + item0Rect.bottom) / 2,
      );

      final Offset fabPoint = tester.getCenter(find.byType(FloatingActionButton));
      final int fabItem = builtItems.firstWhere(
        (int index) => tester.getRect(find.byKey(app.listItemKey(index))).contains(fabPoint),
      );
      final Rect fabItemRect = tester.getRect(find.byKey(app.listItemKey(fabItem)));
      // A point on the item under the FAB, away from the FAB.
      final fabItemUncoveredPoint = Offset(fabItemRect.left + fabItemRect.width / 4, fabPoint.dy);
      expect(
        tester.getRect(find.byType(FloatingActionButton)).contains(fabItemUncoveredPoint),
        isFalse,
      );

      // 1. Control: a click on the first item's uncovered part reaches it.
      await realClick(tester, 'click_item0_uncovered', item0UncoveredPoint);
      final int item0ClicksAfterUncoveredClick = itemClicks(0);

      // 2. A click on the pinned app bar's action over the first item presses
      // the action and doesn't reach the item.
      await realClick(tester, 'click_app_bar_action', actionPoint);
      final int actionPressesAfterActionClick = app.appBarActionPresses;
      final int item0ClicksAfterActionClick = itemClicks(0);

      // 3. A click on the pinned app bar's background over the first item
      // doesn't reach the item.
      await realClick(tester, 'click_app_bar_background', appBarPoint);
      final int item0ClicksAfterAppBarClick = itemClicks(0);

      // 4. A click on the FAB over an item presses the FAB and doesn't reach
      // the item.
      await realClick(tester, 'click_fab', fabPoint);
      final int fabPressesAfterFabClick = app.fabPresses;
      final int fabItemClicksAfterFabClick = itemClicks(fabItem);

      // 5. A click elsewhere on the item under the FAB still reaches it.
      await realClick(tester, 'click_fab_item_uncovered', fabItemUncoveredPoint);
      final int fabItemClicksAfterUncoveredClick = itemClicks(fabItem);

      expect(
        <String, Object>{
          '1. item 0 clicks after clicking its uncovered part': item0ClicksAfterUncoveredClick,
          '2. app bar action presses after clicking the action': actionPressesAfterActionClick,
          '2. item 0 clicks after clicking the app bar action': item0ClicksAfterActionClick,
          '3. item 0 clicks after clicking the app bar background': item0ClicksAfterAppBarClick,
          '4. FAB presses after clicking the FAB': fabPressesAfterFabClick,
          '4. item $fabItem clicks after clicking the FAB': fabItemClicksAfterFabClick,
          '5. item $fabItem clicks after clicking it away from the FAB':
              fabItemClicksAfterUncoveredClick,
        },
        <String, Object>{
          '1. item 0 clicks after clicking its uncovered part': 1,
          '2. app bar action presses after clicking the action': 1,
          '2. item 0 clicks after clicking the app bar action': 1,
          '3. item 0 clicks after clicking the app bar background': 1,
          '4. FAB presses after clicking the FAB': 1,
          '4. item $fabItem clicks after clicking the FAB': 0,
          '5. item $fabItem clicks after clicking it away from the FAB': 1,
        },
      );
    },
  );
}
