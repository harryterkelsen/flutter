// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// These tests drive the hit-test region pass through real widgets (routes,
// showGeneralDialog and its barrier) under the flutter_test binding. The
// geometry, claim rules and bookkeeping are covered in
// test/rendering/hit_test_regions_test.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fake_platform_views.dart';
import 'two_dimensional_utils.dart';

// Widgets are positioned in logical pixels but regions are in physical
// pixels; a ratio other than 1 checks the conversion.
const double _devicePixelRatio = 2.0;

/// The regions computed by the last frame: for each platform view, in paint
/// order, the distinct rects claimed over it, in logical pixels.
///
/// Rects are deduplicated because some widgets, such as [ModalBarrier], are
/// built from several nested boxes that each claim the same rect.
Map<int, Set<Rect>> _lastRegions() {
  final Float64List payload = RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions!;
  double at(int i) => payload[i] / _devicePixelRatio;
  final regions = <int, Set<Rect>>{};
  for (var i = 0; i < payload.length;) {
    final Set<Rect> rects = regions[payload[i].toInt()] = <Rect>{};
    final int end = i + 2 + 4 * payload[i + 1].toInt();
    for (i += 2; i < end; i += 4) {
      rects.add(Rect.fromLTRB(at(i), at(i + 1), at(i + 2), at(i + 3)));
    }
  }
  return regions;
}

Widget _platformView(int viewId) {
  return PlatformViewSurface(
    controller: FakePlatformViewController(viewId),
    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
  );
}

Widget _buildPlatformView(int viewId) => _platformView(viewId);

Widget _app(Widget home) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (BuildContext context, _, _) => builder(context),
    ),
    home: home,
  );
}

Widget _buildApp(Widget home) => _app(home);

void configureTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
    tester.view.reset();
  });
}

class _PaintCounter extends CustomPainter {
  int count = 0;

  @override
  void paint(Canvas canvas, Size size) => count += 1;

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}

/// Keeps [child] alive when it is scrolled out of view.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

void main() {
  // Must reset through addTearDown: the binding verifies that debug variables
  // are unset before tearDown callbacks run.
  void enablePass(WidgetTester tester) {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
    tester.view.devicePixelRatio = _devicePixelRatio;
    tester.view.physicalSize = const Size(800, 600) * _devicePixelRatio;
    addTearDown(() {
      RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
      debugEnableHitTestRegionsOnAllPlatforms = false;
      tester.view.reset();
    });
  }

  testWidgets('PV1 under a dismissible showGeneralDialog that contains PV2', (
    WidgetTester tester,
  ) async {
    enablePass(tester);
    const homeButton = Rect.fromLTWH(20, 30, 80, 40);
    const barrier = Rect.fromLTWH(0, 0, 800, 600);
    const dialogHeader = Rect.fromLTWH(100, 100, 200, 40);
    const dialogButton = Rect.fromLTWH(250, 150, 40, 40);
    late BuildContext homeContext;

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) {
            homeContext = context;
            return Stack(
              children: <Widget>[
                // Painted below PV1, so it claims nothing.
                Positioned.fromRect(
                  rect: const Rect.fromLTWH(0, 0, 150, 150),
                  child: const ColoredBox(color: Color(0xFF112233)),
                ),
                Positioned.fromRect(
                  rect: const Rect.fromLTWH(0, 0, 500, 500),
                  child: _platformView(1),
                ),
                Positioned.fromRect(
                  rect: homeButton,
                  child: const Listener(behavior: HitTestBehavior.opaque),
                ),
              ],
            );
          },
        ),
      ),
    );
    showGeneralDialog<void>(
      context: homeContext,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      pageBuilder: (_, _, _) => Stack(
        children: <Widget>[
          Positioned.fromRect(
            rect: dialogHeader,
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
          Positioned.fromRect(
            rect: const Rect.fromLTWH(100, 140, 200, 200),
            child: _platformView(2),
          ),
          Positioned.fromRect(
            rect: dialogButton,
            child: const Listener(behavior: HitTestBehavior.opaque),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // PV1's group has exactly the claims painted between PV1 and PV2,
    // including the barrier; PV2's group has only what is painted after PV2.
    final Map<int, Set<Rect>> regions = _lastRegions();
    expect(regions.keys, <int>[1, 2]);
    expect(regions, <int, Set<Rect>>{
      1: <Rect>{homeButton, barrier, dialogHeader},
      2: <Rect>{dialogButton},
    });

    // The view hosting the dialog receives exactly the payload asserted above.
    expect(
      tester.view.lastHitTestRegions,
      equals(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions),
    );
  });

  testWidgets('delivers hit-test regions to the view of an explicit View widget', (
    WidgetTester tester,
  ) async {
    enablePass(tester);

    Widget buildView({required bool withPlatformView}) {
      return View(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              if (withPlatformView)
                Positioned.fromRect(
                  rect: const Rect.fromLTWH(0, 0, 400, 400),
                  child: _platformView(1),
                ),
              Positioned.fromRect(
                rect: const Rect.fromLTWH(10, 20, 100, 50),
                child: const Listener(behavior: HitTestBehavior.opaque),
              ),
            ],
          ),
        ),
      );
    }

    // The View widget owns its PipelineOwner instead of using the binding's.
    await tester.pumpWidget(wrapWithView: false, buildView(withPlatformView: true));
    expect(
      tester.view.lastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          1.0,
          10.0 * _devicePixelRatio,
          20.0 * _devicePixelRatio,
          110.0 * _devicePixelRatio,
          70.0 * _devicePixelRatio,
        ]),
      ),
    );

    await tester.pumpWidget(wrapWithView: false, buildView(withPlatformView: false));
    expect(tester.view.lastHitTestRegions, equals(Float64List(0)));
  });

  testWidgets('a closing dialog stops claiming as soon as its exit animation starts', (
    WidgetTester tester,
  ) async {
    enablePass(tester);
    final homePainter = _PaintCounter();
    late BuildContext homeContext;

    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          child: CustomPaint(
            painter: homePainter,
            child: Builder(
              builder: (BuildContext context) {
                homeContext = context;
                return _platformView(1);
              },
            ),
          ),
        ),
      ),
    );
    showGeneralDialog<void>(
      context: homeContext,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    await tester.pumpAndSettle();
    expect(_lastRegions(), <int, Set<Rect>>{
      1: <Rect>{const Rect.fromLTWH(0, 0, 800, 600)},
    });

    final int homePaintCount = homePainter.count;
    Navigator.of(homeContext).pop();
    await tester.pump(const Duration(milliseconds: 50));

    // The barrier's IgnorePointer flips to ignoring while the home route
    // (with the platform view) is not repainted, so a region pass driven by
    // paint would miss it.
    expect(homePainter.count, homePaintCount);
    expect(_lastRegions(), <int, Set<Rect>>{1: <Rect>{}});
    expect(
      tester.view.lastHitTestRegions,
      equals(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions),
    );
  });

  testWidgets('platform view in a sliver scrolled out of view starts no group', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    final controller = ScrollController(initialScrollOffset: 300);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          cacheExtent: 0,
          slivers: <Widget>[
            // Occupies scroll offsets 0 to 200, entirely above the viewport.
            SliverToBoxAdapter(child: SizedBox(height: 200, child: _buildPlatformView(1))),
            SliverToBoxAdapter(child: SizedBox(height: 1000, child: _buildPlatformView(2))),
          ],
        ),
      ),
    );

    // The first sliver is laid out but not visible, so the viewport does not
    // paint it.
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[2.0, 0.0])),
    );
  });

  testWidgets('kept-alive platform view scrolled out of a list starts no group', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: controller,
          cacheExtent: 0,
          itemExtent: 200,
          itemCount: 20,
          itemBuilder: (BuildContext context, int index) {
            return switch (index) {
              0 => _KeepAlive(child: _buildPlatformView(1)),
              5 => _buildPlatformView(2),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0])),
    );

    // Item 0 scrolls out of view and is kept alive (laid out earlier, still
    // attached, but not painted); item 5 is now at the top of the viewport.
    controller.jumpTo(1000);
    await tester.pump();
    expect(find.byType(PlatformViewSurface, skipOffstage: false), findsNWidgets(2));
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[2.0, 0.0])),
    );
  });

  testWidgets(
    'kept-alive platform view scrolled out of a two-dimensional viewport starts no group',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      final controller = ScrollController();
      addTearDown(controller.dispose);
      final delegate = TwoDimensionalChildBuilderDelegate(
        maxXIndex: 0,
        maxYIndex: 9,
        builder: (BuildContext context, ChildVicinity vicinity) {
          return switch (vicinity.yIndex) {
            0 => _KeepAlive(child: _buildPlatformView(1)),
            5 => _buildPlatformView(2),
            _ => const SizedBox.shrink(),
          };
        },
      );
      addTearDown(delegate.dispose);

      await tester.pumpWidget(
        simpleBuilderTest(
          verticalDetails: ScrollableDetails.vertical(controller: controller),
          delegate: delegate,
        ),
      );
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 0.0])),
      );

      // Row 0 scrolls out of view and is kept alive; row 5 (200 pixels tall) is
      // now at the top of the viewport.
      controller.jumpTo(1000);
      await tester.pump();
      expect(find.byType(PlatformViewSurface, skipOffstage: false), findsNWidgets(2));
      final Float64List? scrolledAwayRegions =
          RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions;

      // Scroll row 0 back into view before asserting: unmounting a
      // two-dimensional viewport while it holds kept-alive children fails
      // framework assertions unrelated to hit-test regions.
      controller.jumpTo(0);
      await tester.pump();
      expect(scrolledAwayRegions, equals(Float64List.fromList(<double>[2.0, 0.0])));
    },
  );

  testWidgets('route below an opaque route is offstage and contributes nothing', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    late BuildContext savedContext;

    await tester.pumpWidget(
      _buildApp(
        Builder(
          builder: (BuildContext context) {
            savedContext = context;
            return Stack(
              children: <Widget>[
                Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
                Positioned(
                  left: 10,
                  top: 20,
                  width: 100,
                  height: 50,
                  child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
    );

    Navigator.of(savedContext).push(
      PageRouteBuilder<void>(
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) {
              return Stack(
                children: <Widget>[
                  Positioned(
                    left: 100,
                    top: 100,
                    width: 200,
                    height: 200,
                    child: _buildPlatformView(2),
                  ),
                  Positioned(
                    left: 150,
                    top: 150,
                    width: 40,
                    height: 40,
                    child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
                  ),
                ],
              );
            },
      ),
    );
    await tester.pumpAndSettle();

    // The home route is kept in the overlay (maintainState) but is offstage
    // below the opaque route, so neither platform view 1 nor the hit target
    // over it contributes.
    expect(find.byType(PlatformViewSurface, skipOffstage: false), findsNWidgets(2));
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[2.0, 1.0, 150.0, 150.0, 190.0, 190.0])),
    );
  });

  testWidgets(
    'CompositedTransformFollower claims its rect at the target position of the current frame',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      final link = LayerLink();
      Widget build({required double targetLeft}) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
              Positioned(
                left: targetLeft,
                top: 50,
                width: 60,
                height: 30,
                child: CompositedTransformTarget(link: link, child: const SizedBox.expand()),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: 100,
                height: 50,
                child: CompositedTransformFollower(
                  link: link,
                  showWhenUnlinked: false,
                  offset: const Offset(0, 30),
                  child: const ColoredBox(color: Color(0xFF00FF00)),
                ),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(build(targetLeft: 20));
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 20.0, 80.0, 120.0, 130.0])),
      );

      // The follower is only told about the target's new position while the
      // scene is composited, so the rect must come from this frame's transform.
      await tester.pumpWidget(build(targetLeft: 200));
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 200.0, 80.0, 300.0, 130.0])),
      );
    },
  );

  testWidgets(
    'pinned header claims its rect only when the viewport paints it over platform views',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      final controller = ScrollController(initialScrollOffset: 150);
      addTearDown(controller.dispose);

      Widget build(SliverPaintOrder paintOrder) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            controller: controller,
            cacheExtent: 0,
            paintOrder: paintOrder,
            slivers: <Widget>[
              const PinnedHeaderSliver(
                child: SizedBox(height: 100, child: ColoredBox(color: Color(0xFF0000FF))),
              ),
              SliverFixedExtentList(
                itemExtent: 250,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) => _buildPlatformView(index + 1),
                  childCount: 10,
                ),
              ),
            ],
          ),
        );
      }

      // The list starts below the 100 pixel header and is scrolled by 150, so
      // platform view 1 is at -50 to 200 (under the header), platform view 2 at
      // 200 to 450 and platform view 3 at 450 to 700.
      //
      // With the last sliver on top, the pinned header is painted first, under
      // platform view 1, so it claims nothing.
      await tester.pumpWidget(build(SliverPaintOrder.lastIsTop));
      expect(tester.getRect(find.byType(ColoredBox)), const Rect.fromLTWH(0, 0, 800, 100));
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0, 3.0, 0.0])),
      );

      // With the first sliver on top (the default), the pinned header is painted
      // over every list item; its rect lands in the group of the last platform
      // view painted before it.
      await tester.pumpWidget(build(SliverPaintOrder.firstIsTop));
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(
          Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0, 3.0, 1.0, 0.0, 0.0, 800.0, 100.0]),
        ),
      );
    },
  );

  testWidgets('platform view laid out in the cache extent of a reversed list starts no group', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    final controller = ScrollController(initialScrollOffset: 100);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ListView.builder(
                controller: controller,
                reverse: true,
                cacheExtent: 250,
                itemExtent: 200,
                itemCount: 20,
                itemBuilder: (BuildContext context, int index) => _buildPlatformView(index + 1),
              ),
            ),
            Positioned(
              left: 10,
              top: 20,
              width: 100,
              height: 50,
              child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
            ),
          ],
        ),
      ),
    );

    // The list grows upwards from the bottom and is scrolled by 100: platform
    // views 1 to 4 are (partially) visible, from the bottom up, and platform
    // view 5 (at -300 to -100) is laid out in the cache extent but not painted.
    expect(find.byType(PlatformViewSurface, skipOffstage: false), findsNWidgets(5));
    expect(
      tester.getRect(find.byType(PlatformViewSurface, skipOffstage: false).at(3)),
      const Rect.fromLTWH(0, -100, 800, 200),
    );
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          0.0,
          2.0,
          0.0,
          3.0,
          0.0,
          4.0,
          1.0,
          10.0,
          20.0,
          110.0,
          70.0,
        ]),
      ),
    );
  });

  testWidgets('platform view overflowing an unclipped viewport is covered beyond its bounds', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    final controller = ScrollController(initialScrollOffset: 50);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 100,
              width: 400,
              height: 300,
              child: CustomScrollView(
                controller: controller,
                cacheExtent: 0,
                clipBehavior: Clip.none,
                slivers: <Widget>[
                  SliverToBoxAdapter(child: SizedBox(height: 200, child: _buildPlatformView(1))),
                  const SliverToBoxAdapter(child: SizedBox(height: 1000)),
                ],
              ),
            ),
            // Above the viewport, but over the part of platform view 1 that
            // the unclipped viewport paints above its top edge.
            Positioned(
              left: 10,
              top: 55,
              width: 100,
              height: 40,
              child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
            ),
          ],
        ),
      ),
    );

    expect(tester.getRect(find.byType(PlatformViewSurface)), const Rect.fromLTWH(0, 50, 400, 200));
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 55.0, 110.0, 95.0])),
    );
  });

  testWidgets(
    'platform view laid out in the cache extent of a two-dimensional viewport starts no group',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      final delegate = TwoDimensionalChildBuilderDelegate(
        maxXIndex: 0,
        maxYIndex: 9,
        builder: (BuildContext context, ChildVicinity vicinity) {
          return switch (vicinity.yIndex) {
            1 => _buildPlatformView(1),
            3 => _buildPlatformView(2),
            _ => const SizedBox.shrink(),
          };
        },
      );
      addTearDown(delegate.dispose);

      await tester.pumpWidget(
        simpleBuilderTest(delegate: delegate, useCacheExtent: true, cacheExtent: 200),
      );

      // Rows are 200 pixels tall in a 600 pixel viewport: row 1 is visible and
      // row 3 (at 600 to 800) is laid out in the cache extent but not painted.
      expect(find.byType(PlatformViewSurface, skipOffstage: false), findsNWidgets(2));
      expect(
        tester.getRect(find.byType(PlatformViewSurface, skipOffstage: false).last),
        const Rect.fromLTWH(0, 600, 200, 200),
      );
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 0.0])),
      );
    },
  );
}
