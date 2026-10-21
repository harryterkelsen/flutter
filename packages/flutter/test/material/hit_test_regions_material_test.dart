// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fake_platform_views.dart';

typedef _HitTestRegionGroup = ({int viewId, List<Rect> rects});

List<_HitTestRegionGroup> _decodePayload(Float64List payload) {
  final groups = <_HitTestRegionGroup>[];
  var i = 0;
  while (i < payload.length) {
    final int viewId = payload[i].toInt();
    final int count = payload[i + 1].toInt();
    i += 2;
    final rects = <Rect>[];
    for (var j = 0; j < count; j++) {
      rects.add(Rect.fromLTRB(payload[i], payload[i + 1], payload[i + 2], payload[i + 3]));
      i += 4;
    }
    groups.add((viewId: viewId, rects: rects));
  }
  return groups;
}

Widget _buildPlatformView(int viewId) {
  return PlatformViewSurface(
    controller: FakePlatformViewController(viewId),
    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
  );
}

/// Turns the hit-test region pass on for this test, with a 1200x800 view at a
/// device pixel ratio of 1 so that physical and logical pixels coincide.
void _enableHitTestRegions(WidgetTester tester) {
  debugEnableHitTestRegionsOnAllPlatforms = true;
  RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
    tester.view.reset();
  });
}

List<_HitTestRegionGroup> _lastGroups() {
  final Float64List? payload = RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions;
  expect(payload, isNotNull, reason: 'a platform view is on screen, so a payload is expected');
  return _decodePayload(payload!);
}

Rect _boundingRect(List<Rect> rects) {
  return rects.reduce((Rect value, Rect rect) => value.expandToInclude(rect));
}

bool _contains(Rect outer, Rect inner) => outer.intersect(inner) == inner;

/// The single platform view group contains no rects.
void _expectNoRegions(WidgetTester tester, List<_HitTestRegionGroup> groups) {
  expect(groups, hasLength(1));
  expect(groups.single.viewId, 1);
  expect(groups.single.rects, isEmpty);
}

/// The single platform view group contains a rect that covers the whole
/// platform view (a modal barrier).
void _expectFullyCovered(WidgetTester tester, List<_HitTestRegionGroup> groups) {
  final Rect platformViewRect = tester.getRect(find.byType(PlatformViewSurface));
  expect(groups, hasLength(1));
  expect(groups.single.viewId, 1);
  expect(
    groups.single.rects.any((Rect rect) => _contains(rect, platformViewRect)),
    isTrue,
    reason:
        'expected a rect covering the platform view $platformViewRect in ${groups.single.rects}',
  );
}

/// The single platform view group's rects lie within, and together span
/// exactly, the rect of [finder]. No rect covers the whole platform view.
void Function(WidgetTester, List<_HitTestRegionGroup>) _expectRegionsSpanning(Finder finder) {
  return (WidgetTester tester, List<_HitTestRegionGroup> groups) {
    final Rect expected = tester.getRect(finder);
    expect(groups, hasLength(1));
    expect(groups.single.viewId, 1);
    final List<Rect> rects = groups.single.rects;
    expect(rects, isNotEmpty);
    for (final rect in rects) {
      expect(_contains(expected, rect), isTrue, reason: '$rect lies outside $expected');
    }
    expect(_boundingRect(rects), expected);
  };
}

typedef _MaterialScenario = ({
  String description,
  Widget Function() body,
  PreferredSizeWidget Function()? appBar,
  bool floatingActionButton,
  Future<void> Function(WidgetTester tester)? open,
  void Function(WidgetTester tester, List<_HitTestRegionGroup> groups) verify,
});

final GlobalKey _bodyKey = GlobalKey();

// Hit-test proxies matter on the web, where desktop browsers are the most
// common hosts of platform views such as iframes.
const TargetPlatformVariant _desktopPlatforms = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.linux,
  TargetPlatform.macOS,
});

Future<void> _openFromBody(WidgetTester tester, void Function(BuildContext context) open) async {
  open(_bodyKey.currentContext!);
  await tester.pumpAndSettle();
}

Widget _overPlatformView(Widget child) {
  return Stack(
    children: <Widget>[
      Positioned.fill(child: _buildPlatformView(1)),
      Positioned(left: 100, top: 100, child: child),
    ],
  );
}

final List<_MaterialScenario> _scenarios = <_MaterialScenario>[
  (
    description: 'platform view filling the body below an app bar has no regions',
    body: () => _buildPlatformView(1),
    appBar: () => AppBar(title: const Text('title')),
    floatingActionButton: false,
    open: null,
    verify: _expectNoRegions,
  ),
  (
    description: 'button positioned over the platform view claims exactly the button rect',
    body: () => _overPlatformView(ElevatedButton(onPressed: () {}, child: const Text('over'))),
    appBar: null,
    floatingActionButton: false,
    open: null,
    verify: _expectRegionsSpanning(find.byType(ElevatedButton)),
  ),
  (
    description: 'showDialog barrier covers the platform view',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) => _openFromBody(
      tester,
      (BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('dialog')),
      ),
    ),
    verify: _expectFullyCovered,
  ),
  (
    description: 'non-dismissible showDialog barrier covers the platform view',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) => _openFromBody(
      tester,
      (BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(title: Text('dialog')),
      ),
    ),
    verify: _expectFullyCovered,
  ),
  (
    description: 'showGeneralDialog barrier covers the platform view',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) => _openFromBody(
      tester,
      (BuildContext context) => showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        pageBuilder: (_, _, _) =>
            const Center(child: SizedBox(width: 200, height: 100, child: Text('dialog'))),
      ),
    ),
    verify: _expectFullyCovered,
  ),
  (
    description: 'showModalBottomSheet barrier covers the platform view',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) => _openFromBody(
      tester,
      (BuildContext context) =>
          showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 200)),
    ),
    verify: _expectFullyCovered,
  ),
  (
    description: 'showMenu barrier covers the platform view',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) => _openFromBody(
      tester,
      (BuildContext context) => showMenu<int>(
        context: context,
        position: const RelativeRect.fromLTRB(100, 100, 100, 100),
        items: const <PopupMenuEntry<int>>[PopupMenuItem<int>(value: 1, child: Text('one'))],
      ),
    ),
    verify: _expectFullyCovered,
  ),
  (
    description: 'open DropdownButton barrier covers the platform view',
    body: () => _overPlatformView(
      DropdownButton<int>(
        value: 1,
        onChanged: (_) {},
        items: const <DropdownMenuItem<int>>[
          DropdownMenuItem<int>(value: 1, child: Text('one')),
          DropdownMenuItem<int>(value: 2, child: Text('two')),
        ],
      ),
    ),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) async {
      await tester.tap(find.text('one'));
      await tester.pumpAndSettle();
    },
    verify: _expectFullyCovered,
  ),
  (
    description: 'open DropdownMenu claims the field and menu rects without a barrier',
    body: () => _overPlatformView(
      const DropdownMenu<int>(
        initialSelection: 1,
        dropdownMenuEntries: <DropdownMenuEntry<int>>[
          DropdownMenuEntry<int>(value: 1, label: 'one'),
          DropdownMenuEntry<int>(value: 2, label: 'two'),
        ],
      ),
    ),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) async {
      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
    },
    verify: (WidgetTester tester, List<_HitTestRegionGroup> groups) {
      final Rect platformViewRect = tester.getRect(find.byType(PlatformViewSurface));
      final Rect fieldRect = tester.getRect(find.byType(TextField));
      expect(groups, hasLength(1));
      expect(groups.single.viewId, 1);
      final List<Rect> rects = groups.single.rects;
      // A menu anchored to the field has no modal barrier, so nothing covers
      // the whole platform view.
      expect(rects.any((Rect rect) => _contains(rect, platformViewRect)), isFalse);
      // The field and every menu item are claimed.
      final claimedTargets = <Rect>[
        fieldRect,
        for (final Element item in find.byType(MenuItemButton).hitTestable().evaluate())
          tester.getRect(find.byWidget(item.widget)),
      ];
      expect(claimedTargets, hasLength(3));
      for (final target in claimedTargets) {
        expect(
          rects.any((Rect rect) => _contains(rect, target)),
          isTrue,
          reason: '$target is not covered by $rects',
        );
      }
      // The menu opens below the field with the field's width.
      final Rect bounds = _boundingRect(rects);
      expect(bounds.left, fieldRect.left);
      expect(bounds.top, fieldRect.top);
      expect(bounds.right, fieldRect.right);
      expect(bounds.bottom, greaterThan(claimedTargets.last.bottom));
      expect(bounds.bottom, lessThan(platformViewRect.bottom));
    },
  ),
  (
    description: 'Tooltip shown over the platform view ignores pointers and has no regions',
    body: () => _buildPlatformView(1),
    appBar: () => AppBar(
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.info),
          tooltip: 'A long tooltip message',
          onPressed: () {},
        ),
      ],
    ),
    floatingActionButton: false,
    open: (WidgetTester tester) async {
      final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byIcon(Icons.info)));
      await tester.pumpAndSettle();
      expect(find.text('A long tooltip message'), findsOneWidget);
    },
    verify: _expectNoRegions,
  ),
  (
    description: 'SnackBar over the platform view claims exactly the snack bar rect',
    body: () => _buildPlatformView(1),
    appBar: null,
    floatingActionButton: false,
    open: (WidgetTester tester) async {
      ScaffoldMessenger.of(_bodyKey.currentContext!).showSnackBar(
        SnackBar(
          content: const Text('saved'),
          action: SnackBarAction(label: 'UNDO', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
    },
    verify: _expectRegionsSpanning(find.byType(SnackBar)),
  ),
  (
    description: 'IgnorePointer overlay over the platform view has no regions',
    body: () => Stack(
      children: <Widget>[
        Positioned.fill(child: _buildPlatformView(1)),
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Color(0x40FF0000))),
        ),
      ],
    ),
    appBar: null,
    floatingActionButton: false,
    open: null,
    verify: _expectNoRegions,
  ),
  (
    description: 'floating action button over a scrolled list of platform views claims only in the topmost platform view group',
    body: () => ListView.builder(
      itemExtent: 300,
      itemCount: 20,
      itemBuilder: (_, int index) =>
          Padding(padding: const EdgeInsets.all(8), child: _buildPlatformView(index + 1)),
    ),
    appBar: null,
    floatingActionButton: true,
    open: (WidgetTester tester) async {
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(150);
      await tester.pump();
    },
    verify: (WidgetTester tester, List<_HitTestRegionGroup> groups) {
      const viewportRect = Rect.fromLTWH(0, 0, 1200, 800);
      // Items are 300 tall and the list is scrolled by 150, so platform views
      // 1 to 4 are (partially) inside the viewport, in paint order.
      expect(groups.map((_HitTestRegionGroup group) => group.viewId), <int>[1, 2, 3, 4]);
      for (final Element element in find.byType(PlatformViewSurface).evaluate()) {
        expect(tester.getRect(find.byWidget(element.widget)).overlaps(viewportRect), isTrue);
      }
      // The floating action button is painted after every platform view, so
      // its rects land in the group of the last one painted, and nothing else
      // claims a region.
      for (final _HitTestRegionGroup group in groups.take(3)) {
        expect(group.rects, isEmpty, reason: 'platform view ${group.viewId}');
      }
      final Rect fabRect = tester.getRect(find.byType(FloatingActionButton));
      final List<Rect> fabRects = groups.last.rects;
      expect(fabRects, isNotEmpty);
      for (final rect in fabRects) {
        expect(_contains(fabRect, rect), isTrue, reason: '$rect lies outside $fabRect');
      }
      expect(_boundingRect(fabRects), fabRect);
    },
  ),
];

void main() {
  tearDown(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
  });

  for (final _MaterialScenario scenario in _scenarios) {
    testWidgets(scenario.description, (WidgetTester tester) async {
      _enableHitTestRegions(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: scenario.appBar?.call(),
            floatingActionButton: scenario.floatingActionButton
                ? FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add))
                : null,
            body: SizedBox.expand(key: _bodyKey, child: scenario.body()),
          ),
        ),
      );
      await scenario.open?.call(tester);

      scenario.verify(tester, _lastGroups());
      // The view hosting the Material app receives the same payload.
      expect(
        tester.view.lastHitTestRegions,
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      );
    }, variant: _desktopPlatforms);
  }

  testWidgets('pinned SliverAppBar painted over platform view list items claims its rect', (
    WidgetTester tester,
  ) async {
    _enableHitTestRegions(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            cacheExtent: 0,
            slivers: <Widget>[
              const SliverAppBar(pinned: true, title: Text('title')),
              SliverFixedExtentList(
                itemExtent: 300,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => _buildPlatformView(index + 1),
                  childCount: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(200);
    await tester.pump();

    final Rect appBarRect = tester.getRect(find.byType(AppBar));
    // The list starts below the 56 pixel app bar and is scrolled by 200, so
    // platform view 1 (at -144 to 156) slides under the pinned app bar and
    // platform views 1 to 4 are inside the 800 pixel viewport.
    expect(tester.getRect(find.byType(PlatformViewSurface).first).overlaps(appBarRect), isTrue);
    final List<_HitTestRegionGroup> groups = _lastGroups();
    expect(groups.map((_HitTestRegionGroup group) => group.viewId), <int>[1, 2, 3, 4]);
    // The viewport paints its first sliver last, so the pinned app bar is
    // painted over the list items and its rects land in the group of the last
    // platform view painted.
    for (final _HitTestRegionGroup group in groups.take(3)) {
      expect(group.rects, isEmpty, reason: 'platform view ${group.viewId}');
    }
    final List<Rect> appBarRects = groups.last.rects;
    expect(appBarRects, isNotEmpty);
    for (final rect in appBarRects) {
      expect(_contains(appBarRect, rect), isTrue, reason: '$rect lies outside $appBarRect');
    }
    expect(_boundingRect(appBarRects), appBarRect);
  });

  testWidgets('does not compute hit-test regions for a Material app without platform views', (
    WidgetTester tester,
  ) async {
    _enableHitTestRegions(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              const Text('hi'),
              Positioned(
                left: 100,
                top: 100,
                child: ElevatedButton(onPressed: () {}, child: const Text('button')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);
    expect(tester.view.lastHitTestRegions, isNull);
  });
}
