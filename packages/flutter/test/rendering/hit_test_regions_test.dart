// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/src/rendering/hit_test_regions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fake_platform_views.dart';
import 'rendering_tester.dart';

RenderBox _positioned({
  double? left,
  double? top,
  double? right,
  double? bottom,
  double? width,
  double? height,
  required RenderBox child,
}) {
  child.parentData = StackParentData()
    ..left = left
    ..top = top
    ..right = right
    ..bottom = bottom
    ..width = width
    ..height = height;
  return child;
}

PlatformViewRenderBox _createPlatformView(int viewId) {
  return PlatformViewRenderBox(
    controller: FakePlatformViewController(viewId),
    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
  );
}

RenderBox _createHitTarget({
  double width = 100.0,
  double height = 50.0,
  HitTestBehavior behavior = HitTestBehavior.opaque,
  RenderBox? child,
}) {
  return RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(width: width, height: height),
    child: RenderPointerListener(behavior: behavior, child: child),
  );
}

/// Paints the children of a [RenderFlow] at [offsets], in [paintOrder].
///
/// Children whose index is not in [paintOrder] are not painted at all.
class _PaintOrderFlowDelegate extends FlowDelegate {
  const _PaintOrderFlowDelegate({required this.paintOrder, required this.offsets});

  final List<int> paintOrder;
  final List<Offset> offsets;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    for (final int index in paintOrder) {
      context.paintChild(
        index,
        transform: Matrix4.translationValues(offsets[index].dx, offsets[index].dy, 0.0),
      );
    }
  }

  @override
  bool shouldRepaint(_PaintOrderFlowDelegate oldDelegate) => true;
}

/// A box with custom hit testing that accepts pointer events only within
/// [regions] (in its local coordinates, which may extend beyond its own
/// bounds), and reports exactly those regions as its hit-test regions.
class _RegionHitTestBox extends RenderBox {
  _RegionHitTestBox(this.regions);

  final List<Rect> regions;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (regions.any((Rect region) => region.contains(position))) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  // Under the generic rule this box would claim its whole bounds.
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void visitHitTestRegions(HitTestRegionVisitor visitor) {
    regions.forEach(visitor);
  }
}

/// A sliver that reports [regions] (in its local coordinates) as its
/// hit-test regions.
class _RegionSliver extends RenderSliverToBoxAdapter {
  _RegionSliver(this.regions, {super.child});

  final List<Rect> regions;

  @override
  void visitHitTestRegions(HitTestRegionVisitor visitor) {
    regions.forEach(visitor);
  }
}

/// A hit-target box that counts how many times [visitHitTestRegions] is called.
class _CountingHitTestBox extends RenderBox {
  int visitCount = 0;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void visitHitTestRegions(HitTestRegionVisitor visitor) {
    visitCount += 1;
    super.visitHitTestRegions(visitor);
  }
}

/// A proxy box that reports [clipRect] as its approximate paint clip for [child].
class _TestClipRectBox extends RenderProxyBox {
  _TestClipRectBox({required this.clipRect, RenderBox? child}) : super(child);

  final Rect clipRect;

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => clipRect;
}

ViewConfiguration _createViewConfiguration({
  Size size = const Size(800.0, 600.0),
  double devicePixelRatio = 1.0,
}) {
  final logicalConstraints = BoxConstraints.tight(size);
  return ViewConfiguration(
    logicalConstraints: logicalConstraints,
    physicalConstraints: logicalConstraints * devicePixelRatio,
    devicePixelRatio: devicePixelRatio,
  );
}

void main() {
  final TestRenderingFlutterBinding binding = TestRenderingFlutterBinding.ensureInitialized();
  final bool initialAutomaticPointerInterceptorsEnabled =
      binding.automaticPointerInterceptorsEnabled;
  late ViewConfiguration initialConfiguration;

  setUp(() {
    initialConfiguration = binding.renderView.configuration;
    binding.renderView.configuration = _createViewConfiguration();
    debugEnableHitTestRegionsOnAllPlatforms = false;
    binding.automaticPointerInterceptorsEnabled = initialAutomaticPointerInterceptorsEnabled;
  });

  tearDown(() {
    debugEnableHitTestRegionsOnAllPlatforms = false;
    binding.automaticPointerInterceptorsEnabled = initialAutomaticPointerInterceptorsEnabled;
    binding.renderView.configuration = initialConfiguration;
    final RenderBox emptyBox = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints.tightFor(width: 0.0, height: 0.0),
    );
    layout(emptyBox);
  });

  test('automaticPointerInterceptorsEnabled defaults to true and computes hit-test regions without opt-in', () {
    expect(initialAutomaticPointerInterceptorsEnabled, isTrue);
    expect(binding.automaticPointerInterceptorsEnabled, isTrue);

    debugEnableHitTestRegionsOnAllPlatforms = true;
    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(1)),
        _positioned(left: 10, top: 20, width: 100, height: 50, child: _createHitTarget()),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();
    final expectedRegions = Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0]);
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, equals(expectedRegions));

    // Redundant opt-in when already true by default is a no-op.
    binding.automaticPointerInterceptorsEnabled = true;
    expect(binding.hasScheduledFrame, isFalse);
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, equals(expectedRegions));

    // Opting out clears regions; re-enabling schedules a frame and restores them.
    binding.automaticPointerInterceptorsEnabled = false;
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);
    binding.pumpCompleteFrame();
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);
    binding.automaticPointerInterceptorsEnabled = true;
    expect(binding.hasScheduledFrame, isTrue);
    binding.pumpCompleteFrame();
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, equals(expectedRegions));
  });

  test('does not compute hit-test regions when flag is off or not on web without override', () {
    final PlatformViewRenderBox pv = _createPlatformView(1);
    final RenderBox overlay = _createHitTarget();
    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: pv),
        _positioned(left: 10, top: 20, width: 100, height: 50, child: overlay),
      ],
    );

    // 1. Flag off, debug override on -> null.
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = false;
    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);

    // 2. Flag on, debug override off (when not running on web) -> null.
    if (!kIsWeb) {
      debugEnableHitTestRegionsOnAllPlatforms = false;
      binding.automaticPointerInterceptorsEnabled = true;
      pumpFrame(phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);
    }
  });

  test(
    'returns null when no platform view is present and sends empty list once on last detach',
    () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final updates = <Float64List>[];
      final owner = PipelineOwner(onHitTestRegionsUpdate: updates.add);
      final view = RenderView(
        configuration: _createViewConfiguration(),
        view: binding.platformDispatcher.views.single,
      );
      owner.rootNode = view;
      view.prepareInitialFrame();
      addTearDown(() {
        owner.rootNode = null;
        owner.dispose();
      });

      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 10, top: 20, width: 100, height: 50, child: _createHitTarget()),
        ],
      );
      view.child = stack;
      owner.flushLayout();
      owner.flushCompositingBits();
      owner.flushPaint();
      owner.flushHitTestRegions();

      expect(owner.debugLastHitTestRegions, isNull);
      expect(updates, isEmpty);

      // Attach a platform view below the hit target.
      final PlatformViewRenderBox pv = _createPlatformView(7);
      stack.insert(_positioned(left: 0, top: 0, width: 300, height: 300, child: pv));
      owner.flushLayout();
      owner.flushCompositingBits();
      owner.flushPaint();
      owner.flushHitTestRegions();

      expect(
        owner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[7.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );
      expect(updates, hasLength(1));
      expect(
        updates.single,
        equals(Float64List.fromList(<double>[7.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Remove the last platform view: debugLastHitTestRegions becomes null and
      // an empty Float64List is sent once to clear stale proxy elements.
      stack.remove(pv);
      owner.flushLayout();
      owner.flushCompositingBits();
      owner.flushPaint();
      owner.flushHitTestRegions();

      expect(owner.debugLastHitTestRegions, isNull);
      expect(updates, hasLength(2));
      expect(updates.last, isEmpty);

      // Subsequent flushes with 0 platform views do not keep sending empty updates.
      owner.flushHitTestRegions();
      expect(updates, hasLength(2));
    },
  );

  test(
    'ignores content painted before platform view and scales overlay rect by devicePixelRatio',
    () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final RenderBox beforePv = _createHitTarget(width: 80, height: 40);
      final PlatformViewRenderBox pv = _createPlatformView(1);
      final RenderBox overPv = _createHitTarget(width: 100, height: 50);
      final RenderBox disjointAfterPv = _createHitTarget(width: 50, height: 50);

      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 10, top: 20, width: 80, height: 40, child: beforePv),
          _positioned(left: 0, top: 0, width: 300, height: 300, child: pv),
          _positioned(left: 10, top: 20, width: 100, height: 50, child: overPv),
          _positioned(left: 400, top: 400, width: 50, height: 50, child: disjointAfterPv),
        ],
      );

      // At DPR 1.0: logical (10, 20, 110, 70) -> physical [10, 20, 110, 70].
      layout(stack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // At DPR 3.0: logical (10, 20, 110, 70) -> physical [30, 60, 330, 210].
      binding.renderView.configuration = _createViewConfiguration(devicePixelRatio: 3.0);
      pumpFrame(phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 30.0, 60.0, 330.0, 210.0])),
      );
    },
  );

  test('applies ancestor paint clips and transforms, and keeps claimed rect unclipped to platform view', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    // Small platform view at (100, 100) to (150, 150).
    final PlatformViewRenderBox pv = _createPlatformView(1);
    // Large overlay at (0, 0) to (130, 130) partially overlapping pv -> emitted unclipped to pv.
    final RenderBox largeOverlay = _createHitTarget(width: 130, height: 130);
    // Clipped and translated overlay: ClipRect of 60x60 translated to (110, 110) containing
    // a 200x200 hit target -> clipped to [110, 110, 170, 170].
    final RenderBox clippedAndTranslated = RenderTransform(
      transform: Matrix4.translationValues(110.0, 110.0, 0.0),
      child: RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(width: 60.0, height: 60.0),
        child: RenderClipRect(child: _createHitTarget(width: 200, height: 200)),
      ),
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 100, top: 100, width: 50, height: 50, child: pv),
        _positioned(left: 0, top: 0, width: 130, height: 130, child: largeOverlay),
        _positioned(left: 0, top: 0, width: 60, height: 60, child: clippedAndTranslated),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          2.0,
          0.0,
          0.0,
          130.0,
          130.0,
          110.0,
          110.0,
          170.0,
          170.0,
        ]),
      ),
    );
  });

  test('partitions claims across multiple platform views (PV1 under barrier and dialog containing PV2)', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final RenderBox homeBeforePv1 = _createHitTarget(width: 100, height: 100);
    final PlatformViewRenderBox pv1 = _createPlatformView(10);
    final RenderBox buttonOverPv1 = _createHitTarget(width: 80, height: 40);
    final RenderBox modalBarrier = _createHitTarget(width: 800, height: 600);
    final RenderBox dialogChromeBeforePv2 = _createHitTarget(width: 200, height: 40);
    final PlatformViewRenderBox pv2 = _createPlatformView(20);
    final RenderBox dialogButtonOverPv2 = _createHitTarget(width: 50, height: 30);

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 100, height: 100, child: homeBeforePv1),
        _positioned(left: 0, top: 0, width: 400, height: 400, child: pv1),
        _positioned(left: 20, top: 30, width: 80, height: 40, child: buttonOverPv1),
        _positioned(left: 0, top: 0, width: 800, height: 600, child: modalBarrier),
        _positioned(left: 100, top: 100, width: 200, height: 40, child: dialogChromeBeforePv2),
        _positioned(left: 100, top: 140, width: 200, height: 200, child: pv2),
        _positioned(left: 120, top: 160, width: 50, height: 30, child: dialogButtonOverPv2),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // PV1 group (id 10) receives the modalBarrier rect [0, 0, 800, 600], which
    // subsumes buttonOverPv1 and dialogChromeBeforePv2.
    // PV2 group (id 20) receives only the rect painted after PV2.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          10.0,
          1.0,
          0.0,
          0.0,
          800.0,
          600.0,
          20.0,
          1.0,
          120.0,
          160.0,
          170.0,
          190.0,
        ]),
      ),
    );
  });

  test(
    'toggling barrier RenderIgnorePointer drops barrier rect without repainting underlying content',
    () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final PlatformViewRenderBox pv = _createPlatformView(1);
      final barrierIgnorePointer = RenderIgnorePointer(
        ignoring: false,
        child: _createHitTarget(width: 800, height: 600),
      );

      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 400, height: 400, child: pv),
          _positioned(left: 0, top: 0, width: 800, height: 600, child: barrierIgnorePointer),
        ],
      );

      layout(stack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 0.0, 0.0, 800.0, 600.0])),
      );

      // Simulate dialog exit animation: barrier IgnorePointer flips to ignoring: true.
      barrierIgnorePointer.ignoring = true;
      expect(pv.debugNeedsPaint, isFalse);
      expect(barrierIgnorePointer.debugNeedsPaint, isFalse);

      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 0.0])),
      );
    },
  );

  test(
    'handles RenderIgnorePointer, RenderAbsorbPointer, RenderOffstage, and translucent behavior',
    () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final PlatformViewRenderBox pv = _createPlatformView(1);

      // 1. RenderIgnorePointer overlay -> no rect.
      final ignoredOverlay = RenderIgnorePointer(child: _createHitTarget(width: 100, height: 50));

      // 2. RenderAbsorbPointer -> claims its own rect once; nothing in its subtree claims.
      final absorbingOverlay = RenderAbsorbPointer(
        child: RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 0, top: 0, width: 60, height: 30, child: _createHitTarget()),
            _positioned(left: 10, top: 10, width: 40, height: 20, child: _createHitTarget()),
          ],
        ),
      );

      // 3. Translucent RenderPointerListener -> hitTestSelf is false -> no rect.
      final RenderBox translucentOverlay = _createHitTarget(
        width: 100,
        height: 50,
        behavior: HitTestBehavior.translucent,
      );

      // 4. RenderOffstage(offstage: true) -> skipped completely.
      final offstageOverlay = RenderOffstage(child: _createHitTarget(width: 100, height: 50));
      final offstagePv = RenderOffstage(child: _createPlatformView(99));

      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 400, height: 400, child: pv),
          _positioned(left: 10, top: 10, width: 100, height: 50, child: ignoredOverlay),
          _positioned(left: 50, top: 60, width: 120, height: 80, child: absorbingOverlay),
          _positioned(left: 20, top: 20, width: 100, height: 50, child: translucentOverlay),
          _positioned(left: 30, top: 30, width: 100, height: 50, child: offstageOverlay),
          _positioned(left: 0, top: 0, width: 200, height: 200, child: offstagePv),
        ],
      );

      layout(stack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();

      // Only the RenderAbsorbPointer's own rect [50, 60, 170, 140] is emitted for PV 1;
      // offstage PV 99 is not registered.
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 50.0, 60.0, 170.0, 140.0])),
      );
    },
  );

  test('discovers PlatformViewRenderBox inside RenderIgnorePointer while suppressing sibling claims inside it', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final PlatformViewRenderBox pvInsideIgnore = _createPlatformView(5);
    final RenderBox siblingInsideIgnore = _createHitTarget(width: 80, height: 80);

    final ignoredSubtree = RenderIgnorePointer(
      child: RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 300, height: 300, child: pvInsideIgnore),
          _positioned(left: 10, top: 10, width: 80, height: 80, child: siblingInsideIgnore),
        ],
      ),
    );

    final RenderBox overlayAboveIgnore = _createHitTarget(width: 100, height: 60);

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: ignoredSubtree),
        _positioned(left: 25, top: 35, width: 100, height: 60, child: overlayAboveIgnore),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[5.0, 1.0, 25.0, 35.0, 125.0, 95.0])),
    );
  });

  test('discovers PlatformViewRenderBox inside absorbing RenderAbsorbPointer painted after another platform view', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final PlatformViewRenderBox pv1 = _createPlatformView(1);
    final PlatformViewRenderBox pv2 = _createPlatformView(2);
    final RenderBox siblingInsideAbsorber = _createHitTarget(width: 40, height: 40);

    final absorber = RenderAbsorbPointer(
      child: RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 200, height: 200, child: pv2),
          // Painted over PV2, but inside the absorber, so it never claims.
          _positioned(left: 10, top: 10, width: 40, height: 40, child: siblingInsideAbsorber),
        ],
      ),
    );

    final RenderBox barrier = _createHitTarget(width: 800, height: 600);

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: pv1),
        _positioned(left: 100, top: 100, width: 200, height: 200, child: absorber),
        // Painted last, over both platform views.
        _positioned(left: 0, top: 0, width: 800, height: 600, child: barrier),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // PV1's group holds the absorber's own rect; PV2 still starts its own group,
    // which holds the barrier painted on top of it.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0, 1.0, 100.0, 100.0, 300.0, 300.0, //
          2.0, 1.0, 0.0, 0.0, 800.0, 600.0,
        ]),
      ),
    );
  });

  test('multi-view PipelineOwner hierarchy: flushHitTestRegions and clearHitTestRegions recurse into child owners when parent has no rootNode', () {
    final parentUpdates = <Float64List>[];
    final child1Updates = <Float64List>[];
    final child2Updates = <Float64List>[];

    final parentOwner = PipelineOwner(onHitTestRegionsUpdate: parentUpdates.add);
    final childOwner1 = PipelineOwner(onHitTestRegionsUpdate: child1Updates.add);
    final childOwner2 = PipelineOwner(onHitTestRegionsUpdate: child2Updates.add);
    parentOwner.adoptChild(childOwner1);
    parentOwner.adoptChild(childOwner2);

    final view1 = RenderView(
      configuration: _createViewConfiguration(),
      view: binding.platformDispatcher.views.single,
    );
    final view2 = RenderView(
      configuration: _createViewConfiguration(),
      view: binding.platformDispatcher.views.single,
    );
    childOwner1.rootNode = view1;
    childOwner2.rootNode = view2;
    view1.prepareInitialFrame();
    view2.prepareInitialFrame();

    addTearDown(() {
      childOwner1.rootNode = null;
      childOwner2.rootNode = null;
      parentOwner.dropChild(childOwner1);
      parentOwner.dropChild(childOwner2);
      childOwner1.dispose();
      childOwner2.dispose();
      parentOwner.dispose();
    });

    view1.child = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(101)),
        _positioned(left: 10, top: 20, width: 50, height: 40, child: _createHitTarget()),
      ],
    );
    view2.child = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(202)),
        _positioned(left: 30, top: 40, width: 70, height: 60, child: _createHitTarget()),
      ],
    );

    parentOwner.flushLayout();
    parentOwner.flushCompositingBits();
    parentOwner.flushPaint();

    // parentOwner has rootNode == null and 0 direct platform views, but must still recurse.
    expect(parentOwner.rootNode, isNull);
    parentOwner.flushHitTestRegions();

    expect(parentUpdates, isEmpty);
    expect(
      childOwner1.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[101.0, 1.0, 10.0, 20.0, 60.0, 60.0])),
    );
    expect(
      childOwner2.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[202.0, 1.0, 30.0, 40.0, 100.0, 100.0])),
    );
    expect(child1Updates, hasLength(1));
    expect(child2Updates, hasLength(1));

    // clearHitTestRegions recurses to all children and dispatches empty Float64List(0).
    parentOwner.clearHitTestRegions();
    expect(childOwner1.debugLastHitTestRegions, isNull);
    expect(childOwner2.debugLastHitTestRegions, isNull);
    expect(child1Updates.last, isEmpty);
    expect(child2Updates.last, isEmpty);
  });

  test('toggling automaticPointerInterceptorsEnabled from true to false immediately clears regions and dispatches empty payload', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final childUpdates = <Float64List>[];
    final childOwner = PipelineOwner(onHitTestRegionsUpdate: childUpdates.add);
    binding.rootPipelineOwner.adoptChild(childOwner);
    final childView = RenderView(
      configuration: _createViewConfiguration(),
      view: binding.platformDispatcher.views.single,
    );
    childOwner.rootNode = childView;
    childView.prepareInitialFrame();
    addTearDown(() {
      childOwner.rootNode = null;
      binding.rootPipelineOwner.dropChild(childOwner);
      childOwner.dispose();
    });

    childView.child = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(11)),
        _positioned(left: 5, top: 15, width: 40, height: 30, child: _createHitTarget()),
      ],
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(1)),
        _positioned(left: 10, top: 20, width: 100, height: 50, child: _createHitTarget()),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNotNull);
    expect(childOwner.debugLastHitTestRegions, isNotNull);
    expect(childUpdates, hasLength(1));
    expect(childUpdates.single, isNotEmpty);

    // Toggle off at runtime -> immediately clears debugLastHitTestRegions and sends Float64List(0).
    binding.automaticPointerInterceptorsEnabled = false;
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);
    expect(childOwner.debugLastHitTestRegions, isNull);
    expect(childUpdates, hasLength(2));
    expect(childUpdates.last, isEmpty);
  });

  test('drops overlays clipped to empty intersection and does not overlap against completely clipped platform view', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    // PV 1 is inside a 50x50 ClipRect at (0, 0), but translated to (200, 200) -> clipped to empty.
    final RenderBox clippedOutPv = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints.tightFor(width: 50.0, height: 50.0),
      child: RenderClipRect(
        child: RenderTransform(
          transform: Matrix4.translationValues(200.0, 200.0, 0.0),
          child: RenderConstrainedBox(
            additionalConstraints: const BoxConstraints.tightFor(width: 100.0, height: 100.0),
            child: _createPlatformView(1),
          ),
        ),
      ),
    );
    // Overlay at (210, 210) would overlap PV 1's unclipped bounds, but PV 1 is clipped out.
    final RenderBox overlayOverUnclippedPv1 = _createHitTarget(width: 50, height: 50);

    // PV 2 is unclipped at (0, 0) to (300, 300).
    final PlatformViewRenderBox pv2 = _createPlatformView(2);
    // Overlay inside a 50x50 ClipRect at (10, 10), translated to (100, 100) -> disjoint from clip.
    final RenderBox clippedOutOverlay = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints.tightFor(width: 50.0, height: 50.0),
      child: RenderClipRect(
        child: RenderTransform(
          transform: Matrix4.translationValues(100.0, 100.0, 0.0),
          child: _createHitTarget(width: 80, height: 40),
        ),
      ),
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 50, height: 50, child: clippedOutPv),
        _positioned(left: 210, top: 210, width: 50, height: 50, child: overlayOverUnclippedPv1),
        _positioned(left: 0, top: 0, width: 300, height: 300, child: pv2),
        _positioned(left: 10, top: 10, width: 50, height: 50, child: clippedOutOverlay),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 0.0])),
    );
  });

  test('RenderAbsorbPointer(absorbing: false) descends into child hit target and toggling to true claims own bounds', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final PlatformViewRenderBox pv = _createPlatformView(1);
    final absorbPointer = RenderAbsorbPointer(
      absorbing: false,
      child: RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 10, top: 15, width: 60, height: 40, child: _createHitTarget()),
        ],
      ),
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: pv),
        _positioned(left: 20, top: 30, width: 200, height: 150, child: absorbPointer),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // When absorbing is false, only the inner child rect [30, 45, 90, 85] is claimed.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 30.0, 45.0, 90.0, 85.0])),
    );

    // Toggling absorbing to true claims the RenderAbsorbPointer bounds [20, 30, 220, 180]
    // and its children no longer claim.
    absorbPointer.absorbing = true;
    binding.pumpCompleteFrame();
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 20.0, 30.0, 220.0, 180.0])),
    );
  });

  test('zero-sized PlatformViewRenderBox does not emit a group and zero-sized overlay over valid platform view is dropped', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final PlatformViewRenderBox zeroPv = _createPlatformView(1);
    final RenderBox validOverlay = _createHitTarget(width: 100, height: 50);

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 0, height: 0, child: zeroPv),
        _positioned(left: 0, top: 0, width: 100, height: 50, child: validOverlay),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // Only a zero-sized platform view is present -> returns null.
    expect(binding.rootPipelineOwner.debugLastHitTestRegions, isNull);

    // Add a valid platform view (id 2) and a zero-sized overlay on top of it.
    final PlatformViewRenderBox validPv = _createPlatformView(2);
    final RenderBox zeroOverlay = _createHitTarget(width: 0, height: 0);
    stack.add(_positioned(left: 0, top: 0, width: 300, height: 300, child: validPv));
    stack.add(_positioned(left: 50, top: 50, width: 0, height: 0, child: zeroOverlay));

    pumpFrame(phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // Zero-sized PV 1 is omitted and zero-sized overlay over PV 2 is dropped.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[2.0, 0.0])),
    );
  });

  test('RenderIndexedStack contributes only its displayed child', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final PlatformViewRenderBox pv1 = _createPlatformView(1);
    final indexedStack = RenderIndexedStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        // Index 0: a hit target over platform view 1.
        _positioned(left: 10, top: 20, width: 100, height: 50, child: _createHitTarget()),
        // Index 1: platform view 2 with a hit target on top of it.
        _positioned(
          left: 0,
          top: 0,
          width: 300,
          height: 300,
          child: RenderStack(
            textDirection: TextDirection.ltr,
            children: <RenderBox>[
              _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(2)),
              _positioned(
                left: 50,
                top: 60,
                width: 40,
                height: 30,
                child: _createHitTarget(width: 40, height: 30),
              ),
            ],
          ),
        ),
      ],
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: pv1),
        _positioned(left: 0, top: 0, width: 400, height: 400, child: indexedStack),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // Index 0 is displayed: the hidden platform view 2 and the hit target over
    // it are laid out but not painted, so they contribute neither a group nor
    // a rect.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
    );

    // Index 1 is displayed: the hidden hit target over platform view 1 does not
    // claim, and platform view 2 starts a group holding the hit target over it.
    indexedStack.index = 1;
    pumpFrame(phase: EnginePhase.composite);
    binding.pumpCompleteFrame();
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 1.0, 50.0, 60.0, 90.0, 90.0])),
    );
  });

  test('RenderFlow children are walked in the order the delegate paints them', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final flow = RenderFlow(
      delegate: const _PaintOrderFlowDelegate(
        // Child 2 is painted first (under the platform view), then the
        // platform view, then child 0 (over the platform view). Child 3 is
        // never painted.
        paintOrder: <int>[2, 1, 0],
        offsets: <Offset>[Offset(10, 20), Offset.zero, Offset(200, 300), Offset(50, 50)],
      ),
      children: <RenderBox>[
        _createHitTarget(),
        RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(width: 400.0, height: 400.0),
          child: _createPlatformView(1),
        ),
        _createHitTarget(width: 80, height: 40),
        _createHitTarget(width: 60, height: 30),
      ],
    );

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[_positioned(left: 0, top: 0, width: 400, height: 400, child: flow)],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // Only child 0, painted after the platform view, claims its rect.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
    );
  });

  test('visitHitTestRegions overrides report unclipped local rects instead of their bounds', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;
    binding.renderView.configuration = _createViewConfiguration(devicePixelRatio: 2.0);

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
        // Clips at x = 215 (logical), and maps the box's local point (x, y) to
        // (20 + 2x, 10 + 2y) (logical).
        _positioned(
          left: 0,
          top: 0,
          width: 215,
          height: 400,
          child: RenderClipRect(
            child: RenderTransform(
              transform: Matrix4.translationValues(20.0, 10.0, 0.0)
                ..multiply(Matrix4.diagonal3Values(2.0, 2.0, 1.0)),
              child: _RegionHitTestBox(<Rect>[
                // Inside the box's bounds.
                const Rect.fromLTRB(5, 5, 15, 15),
                // Crosses the ancestor clip.
                const Rect.fromLTRB(90, 40, 110, 50),
                // Extends above and to the left of the box's own bounds.
                const Rect.fromLTRB(-5, -5, 5, 5),
              ]),
            ),
          ),
        ),
        // Accepts pointer events nowhere, even though hitTestSelf is true.
        _positioned(left: 300, top: 0, width: 50, height: 50, child: _RegionHitTestBox(<Rect>[])),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    // Each local rect is transformed to logical (20 + 2l, 10 + 2t, 20 + 2r,
    // 10 + 2b), clipped at x = 215, and scaled by the device pixel ratio of 2.
    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          3.0,
          60.0,
          40.0,
          100.0,
          80.0,
          400.0,
          180.0,
          430.0,
          220.0,
          20.0,
          0.0,
          60.0,
          40.0,
        ]),
      ),
    );
  });

  test('children overflowing an ancestor claim only where the ancestor hit tests them', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
        // An unclipped 100x100 stack whose child paints at (50, 60, 150, 160),
        // but RenderStack.hitTest rejects positions outside the stack.
        _positioned(
          left: 0,
          top: 0,
          width: 100,
          height: 100,
          child: RenderStack(
            textDirection: TextDirection.ltr,
            clipBehavior: Clip.none,
            children: <RenderBox>[
              _positioned(
                left: 50,
                top: 60,
                width: 100,
                height: 100,
                child: _createHitTarget(width: 100, height: 100),
              ),
            ],
          ),
        ),
        // A 50x50 overflow box whose centered 100x100 child paints at
        // (175, -25, 275, 75), but the overflow box rejects positions outside
        // itself.
        _positioned(
          left: 200,
          top: 0,
          width: 50,
          height: 50,
          child: RenderConstrainedOverflowBox(
            minWidth: 100,
            maxWidth: 100,
            minHeight: 100,
            maxHeight: 100,
            child: _createHitTarget(width: 100, height: 100),
          ),
        ),
        // RenderTransform.hitTest does not check its own bounds, so the child
        // painted outside them at (320, 100, 370, 150) is hit tested there.
        _positioned(
          left: 300,
          top: 0,
          width: 50,
          height: 50,
          child: RenderTransform(
            transform: Matrix4.translationValues(20.0, 100.0, 0.0),
            child: _createHitTarget(width: 50, height: 50),
          ),
        ),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(
        Float64List.fromList(<double>[
          1.0,
          3.0,
          50.0,
          60.0,
          100.0,
          100.0,
          200.0,
          0.0,
          250.0,
          50.0,
          320.0,
          100.0,
          370.0,
          150.0,
        ]),
      ),
    );
  });

  test('visitHitTestRegions rects claim a region only if they contain points after clipping', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    final cases = <({String description, Rect region, List<double> payload})>[
      (description: 'zero', region: Rect.zero, payload: <double>[1.0, 0.0]),
      (
        description: 'zero width',
        region: const Rect.fromLTRB(10, 10, 10, 40),
        payload: <double>[1.0, 0.0],
      ),
      (
        description: 'inverted',
        region: const Rect.fromLTRB(40, 40, 10, 10),
        payload: <double>[1.0, 0.0],
      ),
      (
        description: 'inverted horizontally',
        region: const Rect.fromLTRB(40, 10, 10, 40),
        payload: <double>[1.0, 0.0],
      ),
      // Rect.largest conventionally means "everywhere"; it is clipped to the
      // ancestor clip at (50, 50, 150, 150).
      (
        description: 'largest',
        region: Rect.largest,
        payload: <double>[1.0, 1.0, 50.0, 50.0, 150.0, 150.0],
      ),
    ];

    for (final c in cases) {
      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
          _positioned(
            left: 50,
            top: 50,
            width: 100,
            height: 100,
            child: RenderClipRect(
              child: RenderTransform(
                transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
                child: _RegionHitTestBox(<Rect>[c.region]),
              ),
            ),
          ),
        ],
      );

      layout(stack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();

      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(c.payload)),
        reason: c.description,
      );
    }
  });

  test('ancestors that hit test within their bounds restrict all descendants, in their own transformed space', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    // An unclipped 50x50 stack scaled by 2, so it hit tests within
    // (0, 0, 100, 100). Its child stack at (25, 25) overflows it, and that
    // child's own child fills it, so it lies within its parent but overflows
    // its grandparent: it paints at (50, 50, 150, 150) but can only be hit at
    // (50, 50, 100, 100).
    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
        _positioned(
          left: 0,
          top: 0,
          width: 50,
          height: 50,
          child: RenderTransform(
            transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
            child: RenderStack(
              textDirection: TextDirection.ltr,
              clipBehavior: Clip.none,
              children: <RenderBox>[
                _positioned(
                  left: 25,
                  top: 25,
                  width: 50,
                  height: 50,
                  child: RenderStack(
                    textDirection: TextDirection.ltr,
                    children: <RenderBox>[
                      _positioned(
                        left: 0,
                        top: 0,
                        width: 50,
                        height: 50,
                        child: _createHitTarget(width: 50, height: 50),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 50.0, 50.0, 100.0, 100.0])),
    );
  });

  test(
    'children painted outside a fractional translation or a follower claim where they are painted',
    () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final link = LayerLink();
      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
          // Laid out at (100, 0, 150, 50), but paints its child at
          // (200, 50, 250, 100), where RenderFractionalTranslation.hitTest
          // forwards hits without checking its own bounds.
          _positioned(
            left: 100,
            top: 0,
            width: 50,
            height: 50,
            child: RenderFractionalTranslation(
              translation: const Offset(2.0, 1.0),
              child: _createHitTarget(width: 50, height: 50),
            ),
          ),
          // A leader at (300, 200) that claims nothing itself.
          _positioned(
            left: 300,
            top: 200,
            width: 50,
            height: 50,
            child: RenderLeaderLayer(link: link),
          ),
          // Laid out at (100, 300, 150, 350), but paints its child at the
          // leader's position offset by (10, 20), that is at (310, 220, 360, 270),
          // where RenderFollowerLayer.hitTest forwards hits without checking its
          // own bounds.
          _positioned(
            left: 100,
            top: 300,
            width: 50,
            height: 50,
            child: RenderFollowerLayer(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(10.0, 20.0),
              child: _createHitTarget(width: 50, height: 50),
            ),
          ),
        ],
      );

      layout(stack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();

      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(
          Float64List.fromList(<double>[
            1.0,
            2.0,
            200.0,
            50.0,
            250.0,
            100.0,
            310.0,
            220.0,
            360.0,
            270.0,
          ]),
        ),
      );
    },
  );

  test('visitHitTestRegions overrides on slivers are mapped through the viewport', () {
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = true;

    // Scrolled by 30, the second sliver starts at y = 100 - 30 = 70. Neither
    // sliver's child accepts pointer events.
    final viewport = RenderViewport(
      crossAxisDirection: AxisDirection.right,
      offset: ViewportOffset.fixed(30.0),
      children: <RenderSliver>[
        RenderSliverToBoxAdapter(
          child: RenderConstrainedBox(
            additionalConstraints: const BoxConstraints.tightFor(height: 100),
          ),
        ),
        _RegionSliver(
          <Rect>[const Rect.fromLTRB(10, 5, 60, 25)],
          child: RenderConstrainedBox(
            additionalConstraints: const BoxConstraints.tightFor(height: 100),
          ),
        ),
      ],
    );
    final stack = RenderStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        _positioned(left: 0, top: 0, width: 400, height: 400, child: _createPlatformView(1)),
        _positioned(left: 0, top: 0, width: 400, height: 400, child: viewport),
      ],
    );

    layout(stack, phase: EnginePhase.composite);
    binding.pumpCompleteFrame();

    expect(
      binding.rootPipelineOwner.debugLastHitTestRegions,
      equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 75.0, 60.0, 95.0])),
    );
  });

  group('performance optimizations', () {
    test('deduplicates contained rects within a group in both forward and reverse order', () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      // Forward containment: outer rect [10, 10, 140, 140] is claimed first,
      // followed by inner rect [20, 20, 100, 100] and identical rect [10, 10, 140, 140].
      // None of them cover the entire 500x500 platform view.
      final forwardStack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 500, height: 500, child: _createPlatformView(1)),
          _positioned(
            left: 10,
            top: 10,
            width: 130,
            height: 130,
            child: _createHitTarget(width: 130, height: 130),
          ),
          _positioned(
            left: 20,
            top: 20,
            width: 80,
            height: 80,
            child: _createHitTarget(width: 80, height: 80),
          ),
          _positioned(
            left: 10,
            top: 10,
            width: 130,
            height: 130,
            child: _createHitTarget(width: 130, height: 130),
          ),
        ],
      );

      layout(forwardStack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 10.0, 140.0, 140.0])),
      );

      // Reverse containment: inner rect [20, 20, 100, 100] is claimed first,
      // followed by outer rect [10, 10, 140, 140] that completely contains it
      // without covering the entire 500x500 platform view.
      final reverseStack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 500, height: 500, child: _createPlatformView(1)),
          _positioned(
            left: 20,
            top: 20,
            width: 80,
            height: 80,
            child: _createHitTarget(width: 80, height: 80),
          ),
          _positioned(
            left: 10,
            top: 10,
            width: 130,
            height: 130,
            child: _createHitTarget(width: 130, height: 130),
          ),
        ],
      );

      layout(reverseStack, phase: EnginePhase.composite);
      binding.pumpCompleteFrame();
      expect(
        binding.rootPipelineOwner.debugLastHitTestRegions,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 10.0, 140.0, 140.0])),
      );
    });

    test('skips onHitTestRegionsUpdate when payload is unchanged across frames', () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final updates = <Float64List>[];
      final owner = PipelineOwner(onHitTestRegionsUpdate: updates.add);
      final view = RenderView(
        configuration: _createViewConfiguration(),
        view: binding.platformDispatcher.views.single,
      );
      owner.rootNode = view;
      view.prepareInitialFrame();
      addTearDown(() {
        owner.rootNode = null;
        owner.dispose();
      });

      final RenderBox overlay = _positioned(
        left: 10,
        top: 20,
        width: 100,
        height: 50,
        child: _createHitTarget(),
      );
      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 0, top: 0, width: 300, height: 300, child: _createPlatformView(1)),
          overlay,
        ],
      );
      view.child = stack;

      void flushFrame() {
        owner.flushLayout();
        owner.flushCompositingBits();
        owner.flushPaint();
        owner.flushHitTestRegions();
      }

      // Frame 1: initial regions are dispatched once.
      flushFrame();
      expect(updates, hasLength(1));
      expect(
        updates.single,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Frame 2: unchanged hit-test regions do not invoke onHitTestRegionsUpdate again.
      flushFrame();
      expect(updates, hasLength(1));

      // Frame 3: moving the overlay changes the regions and invokes onHitTestRegionsUpdate.
      (overlay.parentData! as StackParentData).left = 30.0;
      stack.markNeedsLayout();
      flushFrame();
      expect(updates, hasLength(2));
      expect(
        updates.last,
        equals(Float64List.fromList(<double>[1.0, 1.0, 30.0, 20.0, 130.0, 70.0])),
      );
    });

    test(
      'skips visiting hit-test regions in clipped subtrees that miss all earlier platform views',
      () {
        debugEnableHitTestRegionsOnAllPlatforms = true;
        binding.automaticPointerInterceptorsEnabled = true;

        final nestedTarget1 = _CountingHitTestBox();
        final nestedTarget2 = _CountingHitTestBox();

        final clippedSubtreeWithoutPv = _TestClipRectBox(
          clipRect: const Rect.fromLTWH(200, 200, 100, 100),
          child: RenderStack(
            textDirection: TextDirection.ltr,
            children: <RenderBox>[
              _positioned(left: 210, top: 210, width: 50, height: 50, child: nestedTarget1),
              _positioned(left: 220, top: 220, width: 40, height: 40, child: nestedTarget2),
            ],
          ),
        );

        final stack1 = RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 0, top: 0, width: 100, height: 100, child: _createPlatformView(1)),
            _positioned(left: 0, top: 0, width: 400, height: 400, child: clippedSubtreeWithoutPv),
          ],
        );

        layout(stack1, phase: EnginePhase.composite);
        final Float64List? regions1 = computeHitTestRegions(stack1);
        expect(regions1, equals(Float64List.fromList(<double>[1.0, 0.0])));
        expect(nestedTarget1.visitCount, 0);
        expect(nestedTarget2.visitCount, 0);

        // When a second platform view is inside the clipped subtree at (210, 210, 50, 50),
        // a box before PV2 in the clipped subtree is not visited, while a box after PV2 is visited.
        final beforePv2InClip = _CountingHitTestBox();
        final afterPv2InClip = _CountingHitTestBox();

        final clippedSubtreeWithPv2 = _TestClipRectBox(
          clipRect: const Rect.fromLTWH(200, 200, 100, 100),
          child: RenderStack(
            textDirection: TextDirection.ltr,
            children: <RenderBox>[
              _positioned(left: 210, top: 210, width: 50, height: 50, child: beforePv2InClip),
              _positioned(
                left: 210,
                top: 210,
                width: 50,
                height: 50,
                child: _createPlatformView(2),
              ),
              _positioned(left: 220, top: 220, width: 30, height: 30, child: afterPv2InClip),
            ],
          ),
        );

        final stack2 = RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 0, top: 0, width: 100, height: 100, child: _createPlatformView(1)),
            _positioned(left: 0, top: 0, width: 400, height: 400, child: clippedSubtreeWithPv2),
          ],
        );

        layout(stack2, phase: EnginePhase.composite);
        final Float64List? regions2 = computeHitTestRegions(stack2);
        expect(
          regions2,
          equals(Float64List.fromList(<double>[1.0, 0.0, 2.0, 1.0, 220.0, 220.0, 250.0, 250.0])),
        );
        expect(beforePv2InClip.visitCount, 0);
        expect(afterPv2InClip.visitCount, 1);
      },
    );

    test('stops visiting hit-test regions after full cover until next platform view and matches enableEarlyStop: false', () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final coveredAfterFullCover = _CountingHitTestBox();
      final singlePvFullCoverStack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 50, top: 50, width: 100, height: 100, child: _createPlatformView(1)),
          _positioned(
            left: 60,
            top: 60,
            width: 30,
            height: 30,
            child: _createHitTarget(width: 30, height: 30),
          ),
          _positioned(
            left: 0,
            top: 0,
            width: 200,
            height: 200,
            child: _createHitTarget(width: 200, height: 200),
          ),
          _positioned(left: 60, top: 60, width: 20, height: 20, child: coveredAfterFullCover),
        ],
      );

      layout(singlePvFullCoverStack, phase: EnginePhase.composite);
      final Float64List? earlyStoppedSingle = computeHitTestRegions(singlePvFullCoverStack);
      expect(coveredAfterFullCover.visitCount, 0);
      expect(
        earlyStoppedSingle,
        equals(computeHitTestRegions(singlePvFullCoverStack, enableEarlyStop: false)),
      );
      expect(coveredAfterFullCover.visitCount, 1);

      // When a second platform view appears after the full-cover box, nodes between the
      // full-cover box and PV2 are skipped, while nodes after PV2 in group 2 are visited.
      final skippedInGroup1 = _CountingHitTestBox();
      final visitedInGroup2 = _CountingHitTestBox();
      final twoPvFullCoverStack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[
          _positioned(left: 50, top: 50, width: 100, height: 100, child: _createPlatformView(1)),
          _positioned(
            left: 55,
            top: 55,
            width: 25,
            height: 25,
            child: _createHitTarget(width: 25, height: 25),
          ),
          _positioned(
            left: 0,
            top: 0,
            width: 200,
            height: 200,
            child: _createHitTarget(width: 200, height: 200),
          ),
          _positioned(left: 60, top: 60, width: 20, height: 20, child: skippedInGroup1),
          _positioned(left: 50, top: 50, width: 100, height: 100, child: _createPlatformView(2)),
          _positioned(left: 70, top: 70, width: 30, height: 30, child: visitedInGroup2),
        ],
      );

      layout(twoPvFullCoverStack, phase: EnginePhase.composite);
      final Float64List? earlyStoppedTwoPv = computeHitTestRegions(twoPvFullCoverStack);
      expect(skippedInGroup1.visitCount, 0);
      expect(visitedInGroup2.visitCount, 1);
      expect(
        earlyStoppedTwoPv,
        equals(computeHitTestRegions(twoPvFullCoverStack, enableEarlyStop: false)),
      );

      // Additional clipped and transformed scenarios comparing enableEarlyStop: true vs false.
      final scenarios = <RenderBox>[
        // 1. Clipped subtrees with full and partial cover.
        RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 50, top: 50, width: 100, height: 100, child: _createPlatformView(1)),
            _positioned(
              left: 25,
              top: 25,
              width: 200,
              height: 200,
              child: RenderClipRect(child: _createHitTarget(width: 200, height: 200)),
            ),
            _positioned(
              left: 60,
              top: 60,
              width: 40,
              height: 40,
              child: RenderClipRect(child: _createHitTarget(width: 40, height: 40)),
            ),
          ],
        ),
        // 4. Translated and scaled subtrees.
        RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 40, top: 40, width: 100, height: 100, child: _createPlatformView(1)),
            _positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 200,
              child: RenderTransform(
                transform: Matrix4.translationValues(20.0, 20.0, 0.0)
                  ..multiply(Matrix4.diagonal3Values(2.0, 2.0, 1.0)),
                child: _createHitTarget(width: 100, height: 100),
              ),
            ),
            _positioned(
              left: 50,
              top: 50,
              width: 30,
              height: 30,
              child: _createHitTarget(width: 30, height: 30),
            ),
          ],
        ),
      ];

      for (final scenario in scenarios) {
        layout(scenario, phase: EnginePhase.composite);
        final Float64List? withEarlyStop = computeHitTestRegions(scenario);
        final Float64List? withoutEarlyStop = computeHitTestRegions(
          scenario,
          enableEarlyStop: false,
        );
        expect(withEarlyStop, equals(withoutEarlyStop));
      }
    });

    test(
      'covering only one of multiple earlier platform views does not trigger premature early-stop',
      () {
        debugEnableHitTestRegionsOnAllPlatforms = true;
        binding.automaticPointerInterceptorsEnabled = true;

        final targetOverPv2AfterPv1Cover = _CountingHitTestBox();
        final targetAfterBothCovered = _CountingHitTestBox();

        // PV1 is at (0, 0, 100, 100) and PV2 is at (0, 200, 100, 300).
        // After PV2, a box covers PV1 completely (0, 0, 120, 120) but does not
        // cover PV2. Early-stop must not activate until all earlier platform
        // views in `groups` are covered, so `targetOverPv2AfterPv1Cover` over PV2
        // is still visited. Once a later box covers both PV1 and PV2
        // (0, 0, 200, 350), `targetAfterBothCovered` is skipped.
        final stack = RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 0, top: 0, width: 100, height: 100, child: _createPlatformView(1)),
            _positioned(left: 0, top: 200, width: 100, height: 100, child: _createPlatformView(2)),
            _positioned(
              left: 0,
              top: 0,
              width: 120,
              height: 120,
              child: _createHitTarget(width: 120, height: 120),
            ),
            _positioned(
              left: 10,
              top: 210,
              width: 40,
              height: 40,
              child: targetOverPv2AfterPv1Cover,
            ),
            _positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 350,
              child: _createHitTarget(width: 200, height: 350),
            ),
            _positioned(left: 20, top: 20, width: 30, height: 30, child: targetAfterBothCovered),
          ],
        );

        layout(stack, phase: EnginePhase.composite);
        final Float64List? withEarlyStop = computeHitTestRegions(stack);
        expect(targetOverPv2AfterPv1Cover.visitCount, 1);
        expect(targetAfterBothCovered.visitCount, 0);
        expect(withEarlyStop, equals(computeHitTestRegions(stack, enableEarlyStop: false)));
      },
    );

    test(
      'absorbing RenderAbsorbPointer still skips its subtree during early-stop and clip-miss',
      () {
        debugEnableHitTestRegionsOnAllPlatforms = true;
        binding.automaticPointerInterceptorsEnabled = true;

        final insideEarlyStoppedAbsorber = _CountingHitTestBox();
        final insideClipMissedAbsorber = _CountingHitTestBox();

        final stack = RenderStack(
          textDirection: TextDirection.ltr,
          children: <RenderBox>[
            _positioned(left: 50, top: 50, width: 100, height: 100, child: _createPlatformView(1)),
            // Covers PV1 completely so currentGroupFullyCovered becomes true.
            _positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 200,
              child: _createHitTarget(width: 200, height: 200),
            ),
            // Absorbing RenderAbsorbPointer visited while currentGroupFullyCovered is true:
            // its subtree is still visited for platform views (PV2 starts a group), while
            // non-platform-view children inside it never claim regions.
            _positioned(
              left: 50,
              top: 50,
              width: 100,
              height: 100,
              child: RenderAbsorbPointer(
                child: RenderStack(
                  textDirection: TextDirection.ltr,
                  children: <RenderBox>[
                    _positioned(
                      left: 0,
                      top: 0,
                      width: 100,
                      height: 100,
                      child: _createPlatformView(2),
                    ),
                    _positioned(
                      left: 10,
                      top: 10,
                      width: 20,
                      height: 20,
                      child: insideEarlyStoppedAbsorber,
                    ),
                  ],
                ),
              ),
            ),
            // Absorbing RenderAbsorbPointer inside a clipped subtree that misses PV1:
            // its subtree is still visited for platform views (PV3 starts a group), while
            // non-platform-view children inside it never claim regions.
            _positioned(
              left: 0,
              top: 0,
              width: 400,
              height: 400,
              child: _TestClipRectBox(
                clipRect: const Rect.fromLTWH(250, 250, 100, 100),
                child: RenderAbsorbPointer(
                  child: RenderStack(
                    textDirection: TextDirection.ltr,
                    children: <RenderBox>[
                      _positioned(
                        left: 260,
                        top: 260,
                        width: 50,
                        height: 50,
                        child: _createPlatformView(3),
                      ),
                      _positioned(
                        left: 270,
                        top: 270,
                        width: 20,
                        height: 20,
                        child: insideClipMissedAbsorber,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        layout(stack, phase: EnginePhase.composite);
        final Float64List? withEarlyStop = computeHitTestRegions(stack);
        expect(insideEarlyStoppedAbsorber.visitCount, 0);
        expect(insideClipMissedAbsorber.visitCount, 0);
        expect(
          withEarlyStop,
          equals(
            Float64List.fromList(<double>[
              1.0, 1.0, 0.0, 0.0, 200.0, 200.0, //
              2.0, 0.0, //
              3.0, 0.0,
            ]),
          ),
        );
        expect(withEarlyStop, equals(computeHitTestRegions(stack, enableEarlyStop: false)));
      },
    );

    test('re-dispatches identical payload after platform view is removed and re-attached', () {
      debugEnableHitTestRegionsOnAllPlatforms = true;
      binding.automaticPointerInterceptorsEnabled = true;

      final updates = <Float64List>[];
      final owner = PipelineOwner(onHitTestRegionsUpdate: updates.add);
      final view = RenderView(
        configuration: _createViewConfiguration(),
        view: binding.platformDispatcher.views.single,
      );
      owner.rootNode = view;
      view.prepareInitialFrame();
      addTearDown(() {
        owner.rootNode = null;
        owner.dispose();
      });

      final RenderBox pvPositioned = _positioned(
        left: 0,
        top: 0,
        width: 300,
        height: 300,
        child: _createPlatformView(1),
      );
      final RenderBox overlay = _positioned(
        left: 10,
        top: 20,
        width: 100,
        height: 50,
        child: _createHitTarget(),
      );
      final stack = RenderStack(
        textDirection: TextDirection.ltr,
        children: <RenderBox>[pvPositioned, overlay],
      );
      view.child = stack;

      void flushFrame() {
        owner.flushLayout();
        owner.flushCompositingBits();
        owner.flushPaint();
        owner.flushHitTestRegions();
      }

      // Frame 1: initial payload is dispatched.
      flushFrame();
      expect(updates, hasLength(1));
      expect(
        updates.last,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );

      // Frame 2: removing the platform view dispatches an empty list once and resets last regions.
      stack.remove(pvPositioned);
      flushFrame();
      expect(updates, hasLength(2));
      expect(updates.last, isEmpty);

      // Frame 3: re-attaching the platform view with the exact same overlay coordinates
      // dispatches the payload again rather than suppressing it as unchanged.
      stack.insert(pvPositioned);
      flushFrame();
      expect(updates, hasLength(3));
      expect(
        updates.last,
        equals(Float64List.fromList(<double>[1.0, 1.0, 10.0, 20.0, 110.0, 70.0])),
      );
    });
  });
}
