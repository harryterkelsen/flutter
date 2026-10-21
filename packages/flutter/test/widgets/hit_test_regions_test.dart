// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fake_platform_views.dart';
import 'two_dimensional_utils.dart';

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

Widget _buildApp(Widget home) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    debugShowCheckedModeBanner: false,
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
      return PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => builder(context),
      );
    },
    home: home,
  );
}

class _PaintCountingPainter extends CustomPainter {
  _PaintCountingPainter(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
  }

  @override
  bool shouldRepaint(_PaintCountingPainter oldDelegate) => false;
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
  setUp(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
  });

  tearDown(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
  });

  void configureTestView(WidgetTester tester, {double devicePixelRatio = 1.0}) {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = Size(800.0 * devicePixelRatio, 600.0 * devicePixelRatio);
    addTearDown(() {
      debugEnableHitTestRegionsOnAllPlatforms = false;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
      tester.view.reset();
    });
  }

  testWidgets('does not compute hit-test regions when flag is off or not on web without override', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);

    final widget = Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
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
      ),
    );

    // 1. Flag off -> debugLastHitTestRegions is null and the view never
    // receives a payload.
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
    await tester.pumpWidget(widget);
    expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);
    expect(tester.view.lastHitTestRegions, isNull);

    // 2. Flag on, debug override off (when not on web) -> debugLastHitTestRegions is null.
    if (!kIsWeb) {
      debugEnableHitTestRegionsOnAllPlatforms = false;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
      await tester.pump();
      expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);
    }
  });

  testWidgets(
    'returns null when no platform view is present and clears when last platform view is removed',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      // No platform view -> null.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
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
      expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);

      // Add a platform view -> non-null payload.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
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
          ),
        ),
      );
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );
      // The same payload is delivered to the view that hosts the render tree.
      expect(
        tester.view.lastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Remove the platform view -> debugLastHitTestRegions returns to null and
      // the view receives an empty payload that clears its proxies.
      await tester.pumpWidget(
        const Directionality(textDirection: TextDirection.ltr, child: Stack()),
      );
      expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);
      expect(tester.view.lastHitTestRegions, equals(Float64List(0)));
    },
  );

  testWidgets('delivers hit-test regions to the view of an explicit View widget', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    Widget buildView({required bool withPlatformView}) {
      return View(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              if (withPlatformView)
                Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
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
    }

    // The View widget owns its PipelineOwner instead of using the binding's.
    await tester.pumpWidget(wrapWithView: false, buildView(withPlatformView: true));
    expect(
      tester.view.lastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
    );

    await tester.pumpWidget(wrapWithView: false, buildView(withPlatformView: false));
    expect(tester.view.lastHitTestRegions, equals(Float64List(0)));
  });

  testWidgets(
    'home route content painted before platform view produces no rects and overlay button produces physical rect at DPR 1.0 and 3.0',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      final widget = Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            // Content painted before the platform view -> produces no rects.
            const Positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 200,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
            Positioned(
              left: 20,
              top: 30,
              width: 80,
              height: 40,
              child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
            ),
            // Platform view.
            Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
            // Button positioned over the platform view.
            Positioned(
              left: 10,
              top: 20,
              width: 100,
              height: 50,
              child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
            ),
          ],
        ),
      );

      await tester.pumpWidget(widget);
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Change DPR to 3.0 -> physical coordinates scale by 3.0.
      configureTestView(tester, devicePixelRatio: 3.0);
      await tester.pump();
      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 30.0, 60.0, 330.0, 210.0])),
      );
    },
  );

  testWidgets(
    'PV1 under showGeneralDialog (barrierDismissible) containing PV2 partitions claims into PV1 and PV2 groups',
    (WidgetTester tester) async {
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
                  // Home route content painted before PV1 -> produces no rects.
                  const Positioned(
                    left: 0,
                    top: 0,
                    width: 150,
                    height: 150,
                    child: ColoredBox(color: Color(0xFF112233)),
                  ),
                  // PV1 on home route.
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 500,
                    height: 500,
                    child: _buildPlatformView(1),
                  ),
                  // Floating button over PV1 on home route (painted between PV1 and PV2).
                  Positioned(
                    left: 20,
                    top: 30,
                    width: 80,
                    height: 40,
                    child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // Open a dismissible dialog containing dialog chrome before PV2, PV2 itself, and a close button after PV2.
      showGeneralDialog<void>(
        context: savedContext,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) {
              return Stack(
                children: <Widget>[
                  // Dialog header painted before PV2 (overlaps PV1).
                  const Positioned(
                    left: 100,
                    top: 100,
                    width: 200,
                    height: 40,
                    child: ColoredBox(color: Color(0xFFFFFFFF)),
                  ),
                  // PV2 inside the dialog.
                  Positioned(
                    left: 100,
                    top: 140,
                    width: 200,
                    height: 200,
                    child: _buildPlatformView(2),
                  ),
                  // Close button inside the dialog painted after PV2.
                  Positioned(
                    left: 250,
                    top: 150,
                    width: 40,
                    height: 40,
                    child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
                  ),
                ],
              );
            },
      );
      await tester.pumpAndSettle();

      final Float64List? payload =
          RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions;
      expect(payload, isNotNull);

      final List<_HitTestRegionGroup> groups = _decodePayload(payload!);
      expect(groups, hasLength(2));
      expect(groups[0].viewId, 1);
      expect(groups[1].viewId, 2);

      // PV1's group contains the home button over PV1, the full-screen modal barrier rect,
      // and the dialog header painted before PV2. It does NOT contain the home background
      // painted before PV1 or the dialog close button painted after PV2.
      const homeButtonRect = Rect.fromLTWH(20, 30, 80, 40);
      const barrierRect = Rect.fromLTWH(0, 0, 800, 600);
      const dialogHeaderRect = Rect.fromLTWH(100, 100, 200, 40);
      const dialogCloseButtonRect = Rect.fromLTWH(250, 150, 40, 40);

      expect(groups[0].rects, containsAll(<Rect>[homeButtonRect, barrierRect, dialogHeaderRect]));
      for (final Rect rect in groups[0].rects) {
        expect(
          rect == homeButtonRect || rect == barrierRect || rect == dialogHeaderRect,
          isTrue,
          reason: 'Unexpected rect $rect in PV1 group',
        );
      }

      // PV2's group contains ONLY the close button painted after PV2; no rect painted
      // before PV2 (barrier, home button, or dialog header) lands in PV2's group.
      expect(groups[1].rects, equals(<Rect>[dialogCloseButtonRect]));

      // The view hosting the dialog receives exactly the payload asserted above.
      expect(tester.view.lastHitTestRegions, equals(payload));
    },
  );

  testWidgets(
    'dialog exit animation toggles barrier IgnorePointer and removes barrier rect without repainting underlying content',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      late BuildContext savedContext;
      var homePaintCount = 0;

      await tester.pumpWidget(
        _buildApp(
          RepaintBoundary(
            child: CustomPaint(
              painter: _PaintCountingPainter(() {
                homePaintCount += 1;
              }),
              child: Builder(
                builder: (BuildContext context) {
                  savedContext = context;
                  return Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 400,
                        height: 400,
                        child: _buildPlatformView(1),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(homePaintCount, 1);

      showGeneralDialog<void>(
        context: savedContext,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) {
              return const Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: ColoredBox(color: Color(0xFFFFFFFF)),
                ),
              );
            },
      );
      await tester.pumpAndSettle();

      const barrierRect = Rect.fromLTWH(0, 0, 800, 600);
      final List<_HitTestRegionGroup> openGroups = _decodePayload(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions!,
      );
      expect(openGroups, hasLength(1));
      expect(openGroups.single.viewId, 1);
      expect(openGroups.single.rects, contains(barrierRect));

      final paintCountBeforePop = homePaintCount;

      // Start popping the dialog and pump a single frame mid-exit animation.
      Navigator.of(savedContext).pop();
      await tester.pump(const Duration(milliseconds: 50));

      // Underlying home content did not repaint.
      expect(homePaintCount, equals(paintCountBeforePop));

      // The barrier IgnorePointer toggled to ignoring: true, so the barrier rect
      // disappears from the payload immediately during the exit animation.
      final List<_HitTestRegionGroup> exitingGroups = _decodePayload(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions!,
      );
      expect(exitingGroups, hasLength(1));
      expect(exitingGroups.single.viewId, 1);
      expect(exitingGroups.single.rects, isEmpty);
    },
  );

  testWidgets(
    'IgnorePointer overlay produces no rect, AbsorbPointer produces one rect and no descendants, translucent GestureDetector produces no rect, and Offstage is skipped',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
              // 1. IgnorePointer overlay -> no rect.
              const Positioned(
                left: 10,
                top: 10,
                width: 100,
                height: 50,
                child: IgnorePointer(child: ColoredBox(color: Color(0xFFFF0000))),
              ),
              // 2. AbsorbPointer -> claims its own rect; nothing in its subtree claims.
              Positioned(
                left: 40,
                top: 50,
                width: 120,
                height: 80,
                child: AbsorbPointer(
                  child: Stack(
                    children: <Widget>[
                      const Positioned(
                        left: 0,
                        top: 0,
                        width: 60,
                        height: 30,
                        child: ColoredBox(color: Color(0xFF00FF00)),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        width: 40,
                        height: 20,
                        child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) {}),
                      ),
                    ],
                  ),
                ),
              ),
              // 3. Translucent GestureDetector -> no rect.
              Positioned(
                left: 20,
                top: 20,
                width: 100,
                height: 50,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: const SizedBox(width: 100, height: 50),
                ),
              ),
              // 4. Offstage -> skipped completely.
              const Positioned(
                left: 30,
                top: 30,
                width: 100,
                height: 50,
                child: Offstage(child: ColoredBox(color: Color(0xFF0000FF))),
              ),
            ],
          ),
        ),
      );

      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 40.0, 50.0, 160.0, 130.0])),
      );
    },
  );

  testWidgets(
    'PlatformViewSurface inside IgnorePointer(ignoring: true) is discovered while non-platform-view content inside IgnorePointer does not claim rects',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                width: 300,
                height: 300,
                child: IgnorePointer(
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 300,
                        height: 300,
                        child: _buildPlatformView(3),
                      ),
                      const Positioned(
                        left: 10,
                        top: 10,
                        width: 80,
                        height: 80,
                        child: ColoredBox(color: Color(0xFFFF0000)),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 15,
                top: 25,
                width: 90,
                height: 45,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ],
          ),
        ),
      );

      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[3.0, 1.0, 15.0, 25.0, 105.0, 70.0])),
      );
    },
  );

  testWidgets(
    'PlatformViewSurface inside AbsorbPointer painted after another platform view still starts its own group',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(left: 0, top: 0, width: 400, height: 400, child: _buildPlatformView(1)),
              Positioned(
                left: 100,
                top: 100,
                width: 200,
                height: 200,
                child: AbsorbPointer(
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 200,
                        height: 200,
                        child: _buildPlatformView(2),
                      ),
                      const Positioned(
                        left: 10,
                        top: 10,
                        width: 40,
                        height: 40,
                        child: ColoredBox(color: Color(0xFFFF0000)),
                      ),
                    ],
                  ),
                ),
              ),
              // A barrier painted last, over both platform views.
              const Positioned.fill(child: ColoredBox(color: Color(0x80000000))),
            ],
          ),
        ),
      );

      final List<_HitTestRegionGroup> groups = _decodePayload(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions!,
      );
      expect(groups, hasLength(2));
      expect(groups[0].viewId, 1);
      expect(groups[0].rects, <Rect>[const Rect.fromLTRB(100, 100, 300, 300)]);
      expect(groups[1].viewId, 2);
      expect(groups[1].rects, <Rect>[const Rect.fromLTRB(0, 0, 800, 600)]);
    },
  );

  testWidgets(
    'applies ClipRect and Transform and keeps partially overlapping overlay unclipped to platform view bounds',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              // Small platform view at (100, 100) to (150, 150).
              Positioned(left: 100, top: 100, width: 50, height: 50, child: _buildPlatformView(1)),
              // Larger overlay at (0, 0) to (250, 250) partially overlapping PV -> unclipped to PV.
              const Positioned(
                left: 0,
                top: 0,
                width: 250,
                height: 250,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
              // Clipped and translated overlay -> [120, 120, 160, 160].
              Positioned(
                left: 0,
                top: 0,
                width: 40,
                height: 40,
                child: Transform.translate(
                  offset: const Offset(120, 120),
                  child: const ClipRect(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: ColoredBox(color: Color(0xFFFF0000)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(
          Float64List.fromList(<double>[
            1.0,
            2.0,
            0.0,
            0.0,
            250.0,
            250.0,
            120.0,
            120.0,
            160.0,
            160.0,
          ]),
        ),
      );
    },
  );

  testWidgets(
    'toggling automaticPointerInterceptorsEnabled from true to false at runtime immediately clears debugLastHitTestRegions',
    (WidgetTester tester) async {
      configureTestView(tester);
      debugEnableHitTestRegionsOnAllPlatforms = true;
      RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(left: 0, top: 0, width: 300, height: 300, child: _buildPlatformView(1)),
              const Positioned(
                left: 10,
                top: 20,
                width: 100,
                height: 50,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ],
          ),
        ),
      );

      expect(
        RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );
      expect(
        tester.view.lastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Toggle off at runtime -> immediately clears debugLastHitTestRegions before next frame.
      RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
      expect(RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions, isNull);
      // The view receives the empty clearing payload synchronously, without a frame.
      expect(tester.view.lastHitTestRegions, equals(Float64List(0)));
    },
  );

  testWidgets('overlay painted after PV2 that overlaps disjoint PV1 is appended to PV2 group', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            // PV1 at (0, 0) to (100, 100).
            Positioned(left: 0, top: 0, width: 100, height: 100, child: _buildPlatformView(1)),
            // Overlay A painted between PV1 and PV2, overlapping PV1.
            const Positioned(
              left: 10,
              top: 10,
              width: 50,
              height: 50,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
            // PV2 at (300, 300) to (400, 400), disjoint from PV1.
            Positioned(left: 300, top: 300, width: 100, height: 100, child: _buildPlatformView(2)),
            // Overlay B painted after PV2, physically overlapping PV1 (at index 0) but disjoint from PV2.
            const Positioned(
              left: 20,
              top: 20,
              width: 40,
              height: 40,
              child: ColoredBox(color: Color(0xFF00FF00)),
            ),
          ],
        ),
      ),
    );

    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          1.0,
          10.0,
          10.0,
          60.0,
          60.0,
          2.0,
          1.0,
          20.0,
          20.0,
          60.0,
          60.0,
        ]),
      ),
    );
  });

  testWidgets('pinned header painted over platform view list items claims its rect', (
    WidgetTester tester,
  ) async {
    configureTestView(tester);
    debugEnableHitTestRegionsOnAllPlatforms = true;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;

    final controller = ScrollController(initialScrollOffset: 150);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          cacheExtent: 0,
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
      ),
    );

    // The list starts below the 100 pixel header and is scrolled by 150, so
    // platform view 1 is at -50 to 200 (under the header), platform view 2 at
    // 200 to 450 and platform view 3 at 450 to 700.
    expect(tester.getRect(find.byType(ColoredBox)), const Rect.fromLTWH(0, 0, 800, 100));
    // The viewport paints its first sliver last, so the pinned header is
    // painted over every list item; its rect lands in the group of the last
    // platform view painted before it.
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0, 3.0, 1.0, 0.0, 0.0, 800.0, 100.0])),
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

  testWidgets('viewport painting its last sliver on top walks its slivers first to last', (
    WidgetTester tester,
  ) async {
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

    // The pinned header is painted first, under platform view 1 (at -50 to
    // 200), so it claims nothing.
    await tester.pumpWidget(build(SliverPaintOrder.lastIsTop));
    expect(tester.getRect(find.byType(ColoredBox)), const Rect.fromLTWH(0, 0, 800, 100));
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0, 3.0, 0.0])),
    );

    // Switching the paint order puts the header back on top of the list.
    await tester.pumpWidget(build(SliverPaintOrder.firstIsTop));
    expect(
      RendererBinding.instance.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0, 3.0, 1.0, 0.0, 0.0, 800.0, 100.0])),
    );
  });

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
