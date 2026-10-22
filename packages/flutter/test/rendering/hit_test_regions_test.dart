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

/// Gives [child] the stack parent data that places it exactly at [rect].
RenderBox _at(Rect rect, RenderBox child) {
  child.parentData = StackParentData()
    ..left = rect.left
    ..top = rect.top
    ..width = rect.width
    ..height = rect.height;
  return child;
}

RenderStack _stack(List<RenderBox> children) {
  return RenderStack(textDirection: TextDirection.ltr, children: children);
}

PlatformViewRenderBox _platformView(int viewId) {
  return PlatformViewRenderBox(
    controller: FakePlatformViewController(viewId),
    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
  );
}

/// A box that fills its (tight) constraints and, when opaque, accepts pointer
/// events everywhere, so it claims its bounds wherever it covers a platform
/// view.
RenderBox _hitTarget({HitTestBehavior behavior = HitTestBehavior.opaque}) {
  return RenderPointerListener(behavior: behavior);
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
  return _platformView(viewId);
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

/// The payload expected for [groups], given in paint order as
/// `(platformViewId, claimedRects)`: for each group, the ID, the number of
/// rects, and then each rect's left, top, right and bottom multiplied by
/// [scale] (the device pixel ratio).
Float64List _payload(List<(int, List<Rect>)> groups, {double scale = 1.0}) {
  return Float64List.fromList(<double>[
    for (final (int viewId, List<Rect> rects) in groups) ...<double>[
      viewId.toDouble(),
      rects.length.toDouble(),
      for (final Rect rect in rects) ...<double>[
        rect.left * scale,
        rect.top * scale,
        rect.right * scale,
        rect.bottom * scale,
      ],
    ],
  ]);
}

ViewConfiguration _viewConfiguration({double devicePixelRatio = 1.0}) {
  final logicalConstraints = BoxConstraints.tight(const Size(800.0, 600.0));
  return ViewConfiguration(
    logicalConstraints: logicalConstraints,
    physicalConstraints: logicalConstraints * devicePixelRatio,
    devicePixelRatio: devicePixelRatio,
  );
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
    binding.renderView.configuration = _viewConfiguration();
    debugEnableHitTestRegionsOnAllPlatforms = true;
    binding.automaticPointerInterceptorsEnabled = initialAutomaticPointerInterceptorsEnabled;
  });

  tearDown(() {
    binding.automaticPointerInterceptorsEnabled = initialAutomaticPointerInterceptorsEnabled;
    debugEnableHitTestRegionsOnAllPlatforms = false;
    binding.renderView.configuration = initialConfiguration;
    // Detach this test's platform views from the root pipeline owner.
    binding.renderView.child = null;
  });

  /// Runs a full binding frame, which runs the hit-test region pass after
  /// drawFrame, and returns the payload computed for the root view.
  Float64List? regionsAfterFrame() {
    binding.pumpCompleteFrame();
    return binding.rootPipelineOwner.debugLastHitTestRegions;
  }

  Float64List? regionsFor(RenderBox root) {
    layout(root, phase: EnginePhase.composite);
    return regionsAfterFrame();
  }

  /// Creates a pipeline owner for a view showing [child] that records every
  /// payload it is sent in [updates], adopted by [parent] (if any) as in a
  /// multi-view app.
  PipelineOwner createViewOwner(
    RenderBox child,
    List<Float64List> updates, {
    PipelineOwner? parent,
  }) {
    final owner = PipelineOwner(onHitTestRegionsUpdate: updates.add);
    parent?.adoptChild(owner);
    final view = RenderView(
      configuration: _viewConfiguration(),
      view: binding.platformDispatcher.views.single,
    );
    owner.rootNode = view;
    view.prepareInitialFrame();
    view.child = child;
    addTearDown(() {
      owner.rootNode = null;
      parent?.dropChild(owner);
      owner.dispose();
    });
    return owner;
  }

  group('gating and delivery', () {
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

    test('the pass does not run while the flag is off, nor off the web without the debug flag', () {
      binding.automaticPointerInterceptorsEnabled = false;
      final RenderStack root = _stack(<RenderBox>[
        _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
        _at(const Rect.fromLTWH(10, 20, 100, 50), _hitTarget()),
      ]);
      expect(regionsFor(root), isNull);

      if (!kIsWeb) {
        debugEnableHitTestRegionsOnAllPlatforms = false;
        binding.automaticPointerInterceptorsEnabled = true;
        expect(regionsAfterFrame(), isNull);
      }
    });

    test(
      'sends regions while a platform view is attached, then one empty payload after it detaches',
      () {
        final updates = <Float64List>[];
        final RenderStack root = _stack(<RenderBox>[
          _at(const Rect.fromLTWH(10, 20, 100, 50), _hitTarget()),
        ]);
        final PipelineOwner owner = createViewOwner(root, updates);
        void flush() {
          owner.flushLayout();
          owner.flushHitTestRegions();
        }

        flush();
        expect(owner.debugLastHitTestRegions, isNull);
        expect(updates, isEmpty);

        // Insert a platform view below the hit target.
        final PlatformViewRenderBox platformView = _platformView(7);
        root.insert(_at(const Rect.fromLTWH(0, 0, 300, 300), platformView));
        flush();
        // [viewId, rectCount, left, top, right, bottom]
        final expected = Float64List.fromList(<double>[7, 1, 10, 20, 110, 70]);
        expect(owner.debugLastHitTestRegions, expected);
        expect(updates, <Float64List>[expected]);

        // The empty payload tells the engine to drop its regions, but is only
        // sent once.
        root.remove(platformView);
        flush();
        flush();
        expect(owner.debugLastHitTestRegions, isNull);
        expect(updates, <Float64List>[expected, Float64List(0)]);
      },
    );

    test(
      'flushHitTestRegions and clearHitTestRegions recurse from an owner without a render tree',
      () {
        // In a multi-view app the root pipeline owner has no render tree; each
        // view's child owner tracks its own platform views.
        final root = PipelineOwner();
        addTearDown(root.dispose);
        final updates1 = <Float64List>[];
        final updates2 = <Float64List>[];
        const claim1 = Rect.fromLTWH(10, 20, 50, 40);
        const claim2 = Rect.fromLTWH(30, 40, 70, 60);
        final PipelineOwner owner1 = createViewOwner(
          _stack(<RenderBox>[
            _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(1)),
            _at(claim1, _hitTarget()),
          ]),
          updates1,
          parent: root,
        );
        final PipelineOwner owner2 = createViewOwner(
          _stack(<RenderBox>[
            _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(2)),
            _at(claim2, _hitTarget()),
          ]),
          updates2,
          parent: root,
        );

        root.flushLayout();
        root.flushHitTestRegions();
        expect(updates1, <Float64List>[
          _payload(<(int, List<Rect>)>[
            (1, <Rect>[claim1]),
          ]),
        ]);
        expect(updates2, <Float64List>[
          _payload(<(int, List<Rect>)>[
            (2, <Rect>[claim2]),
          ]),
        ]);

        root.clearHitTestRegions();
        expect(owner1.debugLastHitTestRegions, isNull);
        expect(owner2.debugLastHitTestRegions, isNull);
        expect(updates1.last, isEmpty);
        expect(updates2.last, isEmpty);
      },
    );

    test('turning the flag off immediately sends every view an empty payload', () {
      final updates = <Float64List>[];
      final PipelineOwner owner = createViewOwner(
        _stack(<RenderBox>[
          _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(1)),
          _at(const Rect.fromLTWH(5, 15, 40, 30), _hitTarget()),
        ]),
        updates,
        parent: binding.rootPipelineOwner,
      );
      binding.pumpCompleteFrame();
      expect(updates.single, isNotEmpty);

      // No frame is pumped: the setter itself clears the regions.
      binding.automaticPointerInterceptorsEnabled = false;
      expect(owner.debugLastHitTestRegions, isNull);
      expect(updates, hasLength(2));
      expect(updates.last, isEmpty);
    });

    test(
      'toggling the flag sends nothing on a platform where the pass never runs',
      () {
        final updates = <Float64List>[];
        createViewOwner(
          _stack(<RenderBox>[
            _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(1)),
            _at(const Rect.fromLTWH(5, 15, 40, 30), _hitTarget()),
          ]),
          updates,
          parent: binding.rootPipelineOwner,
        );

        debugEnableHitTestRegionsOnAllPlatforms = false;
        binding.automaticPointerInterceptorsEnabled = false;
        binding.automaticPointerInterceptorsEnabled = true;
        binding.pumpCompleteFrame();
        binding.automaticPointerInterceptorsEnabled = false;
        expect(updates, isEmpty);
      },
      skip: kIsWeb, // [intended] On the web, the pass always runs.
    );
  });

  group('geometry', () {
    test('only content painted after and over a platform view claims, in physical pixels', () {
      binding.renderView.configuration = _viewConfiguration(devicePixelRatio: 2.0);
      const overPlatformView = Rect.fromLTWH(10, 20, 100, 50);
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          _at(const Rect.fromLTWH(10, 20, 80, 40), _hitTarget()), // Painted below it.
          _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(1)),
          _at(overPlatformView, _hitTarget()),
          _at(const Rect.fromLTWH(400, 400, 50, 50), _hitTarget()), // Beside it.
        ]),
      );
      expect(
        regions,
        _payload(<(int, List<Rect>)>[
          (1, <Rect>[overPlatformView]),
        ], scale: 2.0),
      );
    });

    test(
      'claims are transformed and clipped by ancestors, but not clipped to the platform view',
      () {
        // Sent whole even though it overhangs the platform view; the engine may
        // clip it.
        const overhangingClaim = Rect.fromLTWH(0, 0, 130, 130);
        final Float64List? regions = regionsFor(
          _stack(<RenderBox>[
            _at(const Rect.fromLTWH(100, 100, 50, 50), _platformView(1)),
            _at(overhangingClaim, _hitTarget()),
            // A 60x60 clip at (100, 100) around a 60x60 box translated by
            // (30, 30): only (130, 130)-(160, 160) remains visible.
            _at(
              const Rect.fromLTWH(100, 100, 60, 60),
              RenderClipRect(
                child: RenderTransform(
                  transform: Matrix4.translationValues(30, 30, 0),
                  child: _hitTarget(),
                ),
              ),
            ),
          ]),
        );
        expect(
          regions,
          _payload(<(int, List<Rect>)>[
            (1, <Rect>[overhangingClaim, const Rect.fromLTRB(130, 130, 160, 160)]),
          ]),
        );
      },
    );

    test('content clipped away entirely neither claims nor counts as a covered platform view', () {
      // Translates [child] out of its parent's bounds and clips it away.
      RenderBox clippedAway(RenderBox child) => RenderClipRect(
        child: RenderTransform(transform: Matrix4.translationValues(200, 200, 0), child: child),
      );
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          // Would be at (200, 200)-(250, 250) without the clip.
          _at(const Rect.fromLTWH(0, 0, 50, 50), clippedAway(_platformView(1))),
          _at(const Rect.fromLTWH(210, 210, 50, 50), _hitTarget()),
          _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(2)),
          // Would be at (210, 210)-(260, 260), over platform view 2, without
          // the clip.
          _at(const Rect.fromLTWH(10, 10, 50, 50), clippedAway(_hitTarget())),
        ]),
      );
      expect(regions, _payload(<(int, List<Rect>)>[(1, <Rect>[]), (2, <Rect>[])]));
    });

    test('empty platform views start no group and empty boxes claim nothing', () {
      final RenderStack root = _stack(<RenderBox>[
        _at(Rect.zero, _platformView(1)),
        _at(const Rect.fromLTWH(0, 0, 100, 50), _hitTarget()),
      ]);
      expect(regionsFor(root), isNull);

      root
        ..add(_at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(2)))
        ..add(_at(const Rect.fromLTWH(50, 50, 0, 0), _hitTarget()));
      expect(regionsAfterFrame(), _payload(<(int, List<Rect>)>[(2, <Rect>[])]));
    });

    test('claims are grouped under the platform view painted most recently before them', () {
      // Platform view 1 under a modal barrier and a dialog that contains
      // platform view 2.
      const buttonOverPv1 = Rect.fromLTWH(20, 30, 80, 40);
      const barrier = Rect.fromLTWH(0, 0, 800, 600);
      const dialogHeader = Rect.fromLTWH(100, 100, 200, 40);
      const buttonOverPv2 = Rect.fromLTWH(120, 160, 50, 30);
      // Painted after platform view 2 but only overlaps platform view 1; it is
      // still grouped under platform view 2, which is directly beneath it in
      // paint order.
      const onlyOverPv1 = Rect.fromLTWH(320, 20, 40, 40);
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
          _at(buttonOverPv1, _hitTarget()),
          _at(barrier, _hitTarget()),
          _at(dialogHeader, _hitTarget()),
          _at(const Rect.fromLTWH(100, 140, 200, 200), _platformView(2)),
          _at(buttonOverPv2, _hitTarget()),
          _at(onlyOverPv1, _hitTarget()),
        ]),
      );
      // PV1 group receives the barrier rect [0, 0, 800, 600], which
      // subsumes buttonOverPv1 and dialogHeader.
      expect(
        regions,
        _payload(<(int, List<Rect>)>[
          (1, <Rect>[barrier]),
          (2, <Rect>[buttonOverPv2, onlyOverPv1]),
        ]),
      );
    });
  });

  group('claim rules', () {
    test('ignored, translucent and offstage content claims nothing', () {
      const overlay = Rect.fromLTWH(10, 20, 100, 50);
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
          _at(overlay, RenderIgnorePointer(child: _hitTarget())),
          _at(overlay, _hitTarget(behavior: HitTestBehavior.translucent)),
          _at(overlay, RenderOffstage(child: _hitTarget())),
          // Offstage platform views are not painted, so they start no group.
          _at(overlay, RenderOffstage(child: _platformView(2))),
        ]),
      );
      expect(regions, _payload(<(int, List<Rect>)>[(1, <Rect>[])]));
    });

    test(
      'an AbsorbPointer claims its own bounds, instead of its children, only while absorbing',
      () {
        const absorberRect = Rect.fromLTWH(20, 30, 200, 150);
        final absorber = RenderAbsorbPointer(
          absorbing: false,
          child: _stack(<RenderBox>[_at(const Rect.fromLTWH(10, 15, 60, 40), _hitTarget())]),
        );
        final RenderStack root = _stack(<RenderBox>[
          _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
          _at(absorberRect, absorber),
        ]);
        expect(
          regionsFor(root),
          _payload(<(int, List<Rect>)>[
            (1, <Rect>[const Rect.fromLTWH(30, 45, 60, 40)]),
          ]),
        );

        // Toggling absorbing neither relayouts nor repaints; the next pass sees it.
        absorber.absorbing = true;
        expect(
          regionsAfterFrame(),
          _payload(<(int, List<Rect>)>[
            (1, <Rect>[absorberRect]),
          ]),
        );
      },
    );

    test('a platform view inside an ignoring IgnorePointer still starts a group', () {
      // The browser still sends it pointer events, so content painted over it
      // must claim them.
      const overlay = Rect.fromLTWH(25, 35, 100, 60);
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          _at(
            const Rect.fromLTWH(0, 0, 300, 300),
            RenderIgnorePointer(
              child: _stack(<RenderBox>[
                _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(1)),
                _at(const Rect.fromLTWH(10, 10, 80, 80), _hitTarget()), // Ignored.
              ]),
            ),
          ),
          _at(overlay, _hitTarget()),
        ]),
      );
      expect(
        regions,
        _payload(<(int, List<Rect>)>[
          (1, <Rect>[overlay]),
        ]),
      );
    });

    test('a platform view inside an absorbing AbsorbPointer still starts a group', () {
      const absorber = Rect.fromLTWH(100, 100, 200, 200);
      const barrier = Rect.fromLTWH(0, 0, 800, 600);
      final Float64List? regions = regionsFor(
        _stack(<RenderBox>[
          _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
          _at(
            absorber,
            RenderAbsorbPointer(
              child: _stack(<RenderBox>[
                _at(const Rect.fromLTWH(0, 0, 200, 200), _platformView(2)),
                _at(const Rect.fromLTWH(10, 10, 40, 40), _hitTarget()), // Absorbed.
              ]),
            ),
          ),
          _at(barrier, _hitTarget()),
        ]),
      );
      expect(
        regions,
        _payload(<(int, List<Rect>)>[
          (1, <Rect>[absorber]),
          (2, <Rect>[barrier]),
        ]),
      );
    });
  });

  test('RenderIndexedStack contributes only its displayed child', () {
    final indexedStack = RenderIndexedStack(
      textDirection: TextDirection.ltr,
      children: <RenderBox>[
        // Index 0: a hit target over platform view 1.
        _at(const Rect.fromLTWH(10, 20, 100, 50), _hitTarget()),
        // Index 1: platform view 2 with a hit target on top of it.
        _at(
          const Rect.fromLTWH(0, 0, 300, 300),
          _stack(<RenderBox>[
            _at(const Rect.fromLTWH(0, 0, 300, 300), _platformView(2)),
            _at(const Rect.fromLTWH(50, 60, 40, 30), _hitTarget()),
          ]),
        ),
      ],
    );

    final RenderStack stack = _stack(<RenderBox>[
      _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
      _at(const Rect.fromLTWH(0, 0, 400, 400), indexedStack),
    ]);

    layout(stack, phase: EnginePhase.composite);

    // Index 0 is displayed: the hidden platform view 2 and the hit target over
    // it are laid out but not painted, so they contribute neither a group nor
    // a rect.
    expect(
      regionsAfterFrame(),
      _payload(<(int, List<Rect>)>[
        (1, <Rect>[const Rect.fromLTWH(10, 20, 100, 50)]),
      ]),
    );

    // Index 1 is displayed: the hidden hit target over platform view 1 does not
    // claim, and platform view 2 starts a group holding the hit target over it.
    indexedStack.index = 1;
    pumpFrame(phase: EnginePhase.composite);
    expect(
      regionsAfterFrame(),
      _payload(<(int, List<Rect>)>[
        (1, const <Rect>[]),
        (2, <Rect>[const Rect.fromLTWH(50, 60, 40, 30)]),
      ]),
    );
  });

  test('RenderFlow children are walked in the order the delegate paints them', () {
    final flow = RenderFlow(
      delegate: const _PaintOrderFlowDelegate(
        // Child 2 is painted first (under the platform view), then the
        // platform view, then child 0 (over the platform view). Child 3 is
        // never painted.
        paintOrder: <int>[2, 1, 0],
        offsets: <Offset>[Offset(10, 20), Offset.zero, Offset(200, 300), Offset(50, 50)],
      ),
      children: <RenderBox>[
        RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(width: 100.0, height: 50.0),
          child: _hitTarget(),
        ),
        RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(width: 400.0, height: 400.0),
          child: _platformView(1),
        ),
        RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(width: 80.0, height: 40.0),
          child: _hitTarget(),
        ),
        RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(width: 60.0, height: 30.0),
          child: _hitTarget(),
        ),
      ],
    );

    final RenderStack stack = _stack(<RenderBox>[_at(const Rect.fromLTWH(0, 0, 400, 400), flow)]);

    layout(stack, phase: EnginePhase.composite);

    // Only child 0, painted after the platform view, claims its rect.
    expect(
      regionsAfterFrame(),
      _payload(<(int, List<Rect>)>[
        (1, <Rect>[const Rect.fromLTWH(10, 20, 100, 50)]),
      ]),
    );
  });

  test('visitHitTestRegions overrides report unclipped local rects instead of their bounds', () {
    binding.renderView.configuration = _viewConfiguration(devicePixelRatio: 2.0);

    final RenderStack stack = _stack(<RenderBox>[
      _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
      // Clips at x = 215 (logical), and maps the box's local point (x, y) to
      // (20 + 2x, 10 + 2y) (logical).
      _at(
        const Rect.fromLTWH(0, 0, 215, 400),
        RenderClipRect(
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
      _at(const Rect.fromLTWH(300, 0, 50, 50), _RegionHitTestBox(<Rect>[])),
    ]);

    // Each local rect is transformed to logical (20 + 2l, 10 + 2t, 20 + 2r,
    // 10 + 2b), clipped at x = 215, and scaled by the device pixel ratio of 2.
    expect(
      regionsFor(stack),
      _payload(<(int, List<Rect>)>[
        (
          1,
          <Rect>[
            const Rect.fromLTRB(30, 20, 50, 40),
            const Rect.fromLTRB(200, 90, 215, 110),
            const Rect.fromLTRB(10, 0, 30, 20),
          ],
        ),
      ], scale: 2.0),
    );
  });

  test('children overflowing an ancestor claim only where the ancestor hit tests them', () {
    final RenderStack stack = _stack(<RenderBox>[
      _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
      // An unclipped 100x100 stack whose child paints at (50, 60, 150, 160),
      // but RenderStack.hitTest rejects positions outside the stack.
      _at(
        const Rect.fromLTWH(0, 0, 100, 100),
        RenderStack(
          textDirection: TextDirection.ltr,
          clipBehavior: Clip.none,
          children: <RenderBox>[_at(const Rect.fromLTWH(50, 60, 100, 100), _hitTarget())],
        ),
      ),
      // A 50x50 overflow box whose centered 100x100 child paints at
      // (175, -25, 275, 75), but the overflow box rejects positions outside
      // itself.
      _at(
        const Rect.fromLTWH(200, 0, 50, 50),
        RenderConstrainedOverflowBox(
          minWidth: 100,
          maxWidth: 100,
          minHeight: 100,
          maxHeight: 100,
          child: _hitTarget(),
        ),
      ),
      // RenderTransform.hitTest does not check its own bounds, so the child
      // painted outside them at (320, 100, 370, 150) is hit tested there.
      _at(
        const Rect.fromLTWH(300, 0, 50, 50),
        RenderTransform(
          transform: Matrix4.translationValues(20.0, 100.0, 0.0),
          child: _hitTarget(),
        ),
      ),
    ]);

    expect(
      regionsFor(stack),
      _payload(<(int, List<Rect>)>[
        (
          1,
          <Rect>[
            const Rect.fromLTRB(50, 60, 100, 100),
            const Rect.fromLTRB(200, 0, 250, 50),
            const Rect.fromLTRB(320, 100, 370, 150),
          ],
        ),
      ]),
    );
  });

  test('visitHitTestRegions rects claim a region only if they contain points after clipping', () {
    final cases = <({String description, Rect region, List<Rect> expectedRects})>[
      (description: 'zero', region: Rect.zero, expectedRects: <Rect>[]),
      (
        description: 'zero width',
        region: const Rect.fromLTRB(10, 10, 10, 40),
        expectedRects: <Rect>[],
      ),
      (
        description: 'inverted',
        region: const Rect.fromLTRB(40, 40, 10, 10),
        expectedRects: <Rect>[],
      ),
      (
        description: 'inverted horizontally',
        region: const Rect.fromLTRB(40, 10, 10, 40),
        expectedRects: <Rect>[],
      ),
      // Rect.largest conventionally means "everywhere"; it is clipped to the
      // ancestor clip at (50, 50, 150, 150).
      (
        description: 'largest',
        region: Rect.largest,
        expectedRects: <Rect>[const Rect.fromLTWH(50, 50, 100, 100)],
      ),
    ];

    for (final c in cases) {
      final RenderStack stack = _stack(<RenderBox>[
        _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
        _at(
          const Rect.fromLTWH(50, 50, 100, 100),
          RenderClipRect(
            child: RenderTransform(
              transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
              child: _RegionHitTestBox(<Rect>[c.region]),
            ),
          ),
        ),
      ]);

      expect(
        regionsFor(stack),
        _payload(<(int, List<Rect>)>[(1, c.expectedRects)]),
        reason: c.description,
      );
    }
  });

  test('ancestors that hit test within their bounds restrict all descendants, in their own transformed space', () {
    // An unclipped 50x50 stack scaled by 2, so it hit tests within
    // (0, 0, 100, 100). Its child stack at (25, 25) overflows it, and that
    // child's own child fills it, so it lies within its parent but overflows
    // its grandparent: it paints at (50, 50, 150, 150) but can only be hit at
    // (50, 50, 100, 100).
    final RenderStack stack = _stack(<RenderBox>[
      _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
      _at(
        const Rect.fromLTWH(0, 0, 50, 50),
        RenderTransform(
          transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
          child: RenderStack(
            textDirection: TextDirection.ltr,
            clipBehavior: Clip.none,
            children: <RenderBox>[
              _at(
                const Rect.fromLTWH(25, 25, 50, 50),
                RenderStack(
                  textDirection: TextDirection.ltr,
                  children: <RenderBox>[_at(const Rect.fromLTWH(0, 0, 50, 50), _hitTarget())],
                ),
              ),
            ],
          ),
        ),
      ),
    ]);

    expect(
      regionsFor(stack),
      _payload(<(int, List<Rect>)>[
        (1, <Rect>[const Rect.fromLTWH(50, 50, 50, 50)]),
      ]),
    );
  });

  test(
    'children painted outside a fractional translation or a follower claim where they are painted',
    () {
      final link = LayerLink();
      final RenderStack stack = _stack(<RenderBox>[
        _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
        // Laid out at (100, 0, 150, 50), but paints its child at
        // (200, 50, 250, 100), where RenderFractionalTranslation.hitTest
        // forwards hits without checking its own bounds.
        _at(
          const Rect.fromLTWH(100, 0, 50, 50),
          RenderFractionalTranslation(translation: const Offset(2.0, 1.0), child: _hitTarget()),
        ),
        // A leader at (300, 200) that claims nothing itself.
        _at(const Rect.fromLTWH(300, 200, 50, 50), RenderLeaderLayer(link: link)),
        // Laid out at (100, 300, 150, 350), but paints its child at the
        // leader's position offset by (10, 20), that is at (310, 220, 360, 270),
        // where RenderFollowerLayer.hitTest forwards hits without checking its
        // own bounds.
        _at(
          const Rect.fromLTWH(100, 300, 50, 50),
          RenderFollowerLayer(
            link: link,
            showWhenUnlinked: false,
            offset: const Offset(10.0, 20.0),
            child: _hitTarget(),
          ),
        ),
      ]);

      expect(
        regionsFor(stack),
        _payload(<(int, List<Rect>)>[
          (1, <Rect>[const Rect.fromLTWH(200, 50, 50, 50), const Rect.fromLTWH(310, 220, 50, 50)]),
        ]),
      );
    },
  );

  test('visitHitTestRegions overrides on slivers are mapped through the viewport', () {
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
    final RenderStack stack = _stack(<RenderBox>[
      _at(const Rect.fromLTWH(0, 0, 400, 400), _platformView(1)),
      _at(const Rect.fromLTWH(0, 0, 400, 400), viewport),
    ]);

    expect(
      regionsFor(stack),
      _payload(<(int, List<Rect>)>[
        (1, <Rect>[const Rect.fromLTRB(10, 75, 60, 95)]),
      ]),
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
