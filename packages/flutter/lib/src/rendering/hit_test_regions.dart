// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/services.dart';
///
/// @docImport 'stack.dart';
/// @docImport 'view.dart';
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'box.dart';
import 'object.dart';
import 'platform_view.dart';
import 'proxy_box.dart';
import 'viewport.dart';

/// The hit-test regions collected for a single [PlatformViewRenderBox].
///
/// One group is created for every non-empty platform view encountered during
/// the child-order walk in [computeHitTestRegions].
///
/// * `viewId` is the [PlatformViewController.viewId] of the platform view, so
///   the engine can tell which platform view the regions sit on top of.
/// * `platformViewRect` is the platform view's bounds in the root coordinate space,
///   intersected with any ancestor paint clip. It is used to decide whether a
///   render object painted later actually covers a platform view.
/// * `rects` are the bounds, in the root coordinate space, of the render
///   objects painted after this platform view (and before the next one) that
///   overlap a platform view and accept pointer events.
typedef _PlatformViewHitTestGroup = ({int viewId, Rect platformViewRect, List<Rect> rects});

/// Whether [outer] completely contains [inner] (including its edges).
bool _rectContains(Rect outer, Rect inner) {
  return outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;
}

/// Maps [localRect] by [transform] into the root coordinate space, using a fast
/// path when [transform] is a 2D translation.
Rect _toGlobal(Rect localRect, Matrix4 transform) {
  final Float64List s = transform.storage;
  if (s[0] == 1.0 &&
      s[1] == 0.0 &&
      s[2] == 0.0 &&
      s[3] == 0.0 &&
      s[4] == 0.0 &&
      s[5] == 1.0 &&
      s[6] == 0.0 &&
      s[7] == 0.0 &&
      s[8] == 0.0 &&
      s[9] == 0.0 &&
      s[10] == 1.0 &&
      s[11] == 0.0 &&
      s[14] == 0.0 &&
      s[15] == 1.0) {
    final double dx = s[12];
    final double dy = s[13];
    if (localRect.left.isFinite &&
        localRect.top.isFinite &&
        localRect.right.isFinite &&
        localRect.bottom.isFinite) {
      if (dx == 0.0 && dy == 0.0) {
        return localRect;
      }
      return Rect.fromLTRB(
        localRect.left + dx,
        localRect.top + dy,
        localRect.right + dx,
        localRect.bottom + dy,
      );
    }
  }
  return MatrixUtils.transformRect(transform, localRect);
}

/// Walks the render tree rooted at [root] in child order (an approximation of
/// paint order; see below) and encodes the bounding rectangles of render
/// objects that paint on top of one or more [PlatformViewRenderBox] instances
/// and claim pointer events.
///
/// The rectangles are in [root]'s coordinate space, which is physical pixels
/// when [root] is a [RenderView].
///
/// On the web, a platform view is a DOM element that sits on top of (or
/// between) Flutter's canvases, so the browser routes pointer events over it
/// to the platform view rather than to Flutter, even where Flutter paints a
/// widget (for example, a button or a dialog) over it. The regions returned
/// here tell the engine where Flutter content that wants pointer events covers
/// a platform view, so that the engine can claim those events for Flutter.
///
/// ## How the regions are collected
///
/// In one sentence: walk the render tree in paint order, tracking the
/// accumulated paint transform and clip; every time a platform view is
/// painted, start a new group for it, and every region in which a render
/// object painted after that accepts pointer events, if it overlaps any
/// platform view painted so far, contributes its clipped, transformed bounds
/// to the most recent group.
///
/// In more detail:
///
/// * The walk follows [RenderObject.visitChildrenInPaintOrder] and treats
///   anything visited after a platform view as painting on top of it. Render
///   objects whose paint order differs from their child order (for example,
///   viewports, which may paint their slivers in reverse order) override that
///   method to visit their children in the order they paint them, and to skip
///   the children they do not paint (for example, the hidden children of a
///   [RenderIndexedStack], or children kept alive while scrolled out of view).
/// * Each child's transform is computed with [RenderObject.applyPaintTransform]
///   and each child's clip with [RenderObject.describeApproximatePaintClip]
///   (except for the children of a [RenderViewportBase], which are clipped to
///   the viewport's bounds), so the rectangles are in the same coordinate space
///   as the root (physical pixels when [root] is a [RenderView]).
/// * Subtrees that cannot receive pointer events are skipped: offstage
///   subtrees ([RenderOffstage]) are not visited at all, and render objects
/// * Subtrees that cannot receive pointer events are skipped: offstage
///   subtrees ([RenderOffstage]) are not visited at all, and render objects
///   under an ignoring [RenderIgnorePointer] or an absorbing
///   [RenderAbsorbPointer] never claim a region. A platform view in such a
///   subtree still starts a group, because the browser still delivers pointer
///   events to it.
/// * Each render object reports the regions in which it accepts pointer
///   events through [RenderObject.visitHitTestRegions]. By default, a render
///   box claims its bounds if [RenderBox.hitTestSelf] returns true at its
///   center. Boxes that only forward hits to their children do not claim a
///   region themselves; their children are visited instead. An absorbing
///   [RenderAbsorbPointer] claims its bounds; its subtree is still visited,
///   as described above, so that platform views inside it start their own
///   groups.
/// * Besides the paint clip, a claimed rectangle is clipped to the bounds of
///   each ancestor [RenderBox] that rejects pointer events outside of its
///   size, which is what [RenderBox.hitTest] does by default, so that a child
///   overflowing such an ancestor only claims the part that can be hit.
///   [RenderTransform], [RenderFractionalTranslation], and
///   [RenderFollowerLayer] hit test their children without checking their own
///   size, so they do not restrict their descendants' regions. This
///   restriction does not apply to platform views (which receive pointer
///   events wherever they are visible), nor to a render object's own regions
///   (which may extend beyond its bounds).
/// * A claimed rectangle is kept only if it is non-empty after clipping and
///   overlaps at least one platform view painted before it. It is attributed
///   to the most recently painted platform view (even if it only overlaps an
///   earlier one), because that is the platform view directly beneath it in
///   paint order. Within each group, rectangles contained inside another
///   rectangle in the same group are deduplicated.
/// * When [enableEarlyStop] is true (the default), once a claimed rectangle in
///   the current group covers all earlier platform views, subsequent render
///   objects skip [RenderObject.visitHitTestRegions] until another platform
///   view starts a new group (and once all attached platform views have been
///   visited, covered or clip-missed subtrees are pruned without descending).
/// * Platform views themselves are leaves of the walk; their children (if any)
///   are not visited.
///
/// ## Encoding
///
/// The groups are flattened into a single [Float64List] so the payload can be
/// handed to the engine without allocating an object per rectangle. Groups
/// appear in the order the walk visits their platform views, and each group is
/// encoded as:
///
/// ```csv
/// [viewId, rectCount, left0, top0, right0, bottom0, ..., leftN, topN, rightN, bottomN]
/// ```
///
/// That is, two values (the platform view ID and the number of rectangles
/// that follow) and then four values (left, top, right, bottom) per rectangle.
/// A group with `rectCount == 0` means the platform view is present but no
/// Flutter content claims pointer events on top of it.
///
/// Returns `null` if no [PlatformViewRenderBox] with a non-empty size is
/// encountered during the walk.
Float64List? computeHitTestRegions(RenderObject root, {bool enableEarlyStop = true}) {
  final groups = <_PlatformViewHitTestGroup>[];
  final int? totalPlatformViews = root.owner?.attachedPlatformViewCount;
  var visitedPlatformViews = 0;
  var currentGroupFullyCovered = false;

  bool allPlatformViewsVisited() {
    return enableEarlyStop &&
        totalPlatformViews != null &&
        visitedPlatformViews >= totalPlatformViews;
  }

  bool overlapsAnyPlatformView(Rect rect) {
    if (!rect.isFinite || rect.isEmpty) {
      return false;
    }
    for (var i = 0; i < groups.length; i++) {
      final Rect platformViewRect = groups[i].platformViewRect;
      if (platformViewRect.isFinite &&
          !platformViewRect.isEmpty &&
          rect.overlaps(platformViewRect)) {
        return true;
      }
    }
    return false;
  }

  // Records [localRect], in the local coordinates described by [transform], as
  // a hit-test region if it covers a platform view that has already been
  // painted.
  void addClaimedRect(Rect localRect, Matrix4 transform, Rect? clip) {
    // An empty rect (including an inverted one) contains no points, but its
    // transformed bounding box could be non-empty, so reject it up front.
    if (localRect.isEmpty) {
      return;
    }
    // Map the local rect into the root coordinate space and clip it to what
    // can actually be hit.
    Rect claimedRect = _toGlobal(localRect, transform);
    if (clip != null) {
      claimedRect = claimedRect.intersect(clip);
    }
    // Only content that covers a platform view needs a region; everywhere
    // else Flutter already receives the pointer events.
    if (!overlapsAnyPlatformView(claimedRect)) {
      return;
    }
    // Attribute the region to the topmost platform view painted so far,
    // deduplicating any rectangles within the group that are contained in
    // another rectangle in the same group.
    final List<Rect> rects = groups.last.rects;
    for (var i = 0; i < rects.length; i++) {
      if (_rectContains(rects[i], claimedRect)) {
        return;
      }
    }
    var writeIndex = 0;
    for (var i = 0; i < rects.length; i++) {
      final Rect existing = rects[i];
      if (!_rectContains(claimedRect, existing)) {
        rects[writeIndex++] = existing;
      }
    }
    rects.length = writeIndex;
    rects.add(claimedRect);

    if (!currentGroupFullyCovered) {
      var coversAll = true;
      for (var i = 0; i < groups.length; i++) {
        final Rect platformViewRect = groups[i].platformViewRect;
        if (platformViewRect.isFinite &&
            !platformViewRect.isEmpty &&
            !_rectContains(claimedRect, platformViewRect)) {
          coversAll = false;
          break;
        }
      }
      if (coversAll) {
        currentGroupFullyCovered = true;
      }
    }
  }

  // Returns the clip, in [parent]'s coordinate space, that [parent] applies
  // when painting [child], or null if it does not clip it.
  Rect? paintClipOf(RenderObject parent, RenderObject child) {
    // A viewport describes the clip of a sliver that a pinned or floating
    // sliver overlaps as starting where the overlap ends, so that content
    // scrolled under a pinned header is not reported as visible to
    // accessibility. That content is still painted (under the header), so the
    // viewport's own bounds are used instead.
    if (parent is RenderViewportBase) {
      return parent.clipBehavior == Clip.none ? null : Offset.zero & parent.size;
    }
    return parent.describeApproximatePaintClip(child);
  }

  // Whether [node] rejects pointer events outside of its own bounds before
  // hit testing its children, as [RenderBox.hitTest] does by default. The
  // exceptions are the framework's render boxes whose hitTest override
  // forwards to their children without checking `size.contains`; extend this
  // list when adding such a box. Other boxes that skip the check are
  // restricted conservatively (their descendants under-claim; they never
  // over-claim).
  bool hitTestsWithinBounds(RenderObject node) {
    return node is RenderBox &&
        node.hasSize &&
        node is! RenderTransform &&
        node is! RenderFractionalTranslation &&
        node is! RenderFollowerLayer;
  }

  // Maps [localRect] by [transform] into the root coordinate space.
  Rect toGlobal(Rect localRect, Matrix4 transform) {
    return localRect.isEmpty ? Rect.zero : _toGlobal(localRect, transform);
  }

  // Intersects [clip] (null meaning unclipped) with [globalRect].
  Rect intersectClip(Rect? clip, Rect globalRect) {
    return clip == null ? globalRect : clip.intersect(globalRect);
  }

  // The transform and hit-test clip of the node whose regions are currently
  // being collected by [claimRegion]. A single visitor is shared by the whole
  // walk so that no closure is allocated per node; this is safe because
  // [RenderObject.visitHitTestRegions] reports synchronously and never
  // re-enters the walk.
  final transformStack = <Matrix4>[Matrix4.identity()];
  Matrix4 currentTransform = transformStack[0];
  Rect? currentHitTestClip;
  Rect? currentNodeBounds;
  var claimedOwnBounds = false;
  void claimRegion(Rect localRect) {
    if (currentNodeBounds != null && _rectContains(localRect, currentNodeBounds!)) {
      claimedOwnBounds = true;
    }
    addClaimedRect(localRect, currentTransform, currentHitTestClip);
  }

  // Per-depth Matrix4 stack and cursor state hoisted outside [visit] so a
  // single [visitChild] closure and one [Matrix4] per tree depth are reused
  // across the entire walk without per-node allocations. [visitChild]
  // snapshots these fields into locals before recursing to `depth + 1` and
  // restores them afterwards.
  late RenderObject currentParent;
  var currentDepth = 0;
  Rect? currentClip;
  Rect? currentDescendantsHitTestClip;
  var currentIgnoringPointers = false;
  int? currentClipMissedAtGroupCount;

  // Visits [node] at tree [depth] and its descendants in paint order (see
  // above). [transform] maps [node]'s local coordinates to the root's, [clip]
  // is the accumulated paint clip in root coordinates (or null if unclipped),
  // [hitTestClip] is [clip] further restricted to the bounds of the ancestors
  // that only hit test within their bounds, [ignoringPointers] is true when an
  // ancestor [RenderIgnorePointer] is ignoring pointer events or an ancestor
  // [RenderAbsorbPointer] is absorbing them, and [clipMissedAtGroupCount]
  // records the `groups.length` at which an ancestor's hit-test clip missed
  // all earlier platform views (or was already covered by the ancestor's own
  // claimed bounds), which automatically invalidates if a descendant platform
  // view appends a new group.
  late final void Function(RenderObject child) visitChild;
  void visit(
    RenderObject node,
    int depth,
    Matrix4 transform,
    Rect? clip,
    Rect? hitTestClip, {
    required bool ignoringPointers,
    required int? clipMissedAtGroupCount,
  }) {
    // Offstage subtrees are neither painted nor hit tested.
    if (node is RenderOffstage && node.offstage) {
      return;
    }

    // A render object under (or itself being) an ignoring IgnorePointer never
    // claims a region.
    final bool selfIgnoringPointers =
        ignoringPointers || (node is RenderIgnorePointer && node.ignoring);
    // An absorbing AbsorbPointer swallows every pointer event within its
    // bounds, so nothing in its subtree can receive pointer events either;
    // its subtree is treated as if it were under an ignoring IgnorePointer.
    final bool childIgnoringPointers =
        selfIgnoringPointers || (node is RenderAbsorbPointer && node.absorbing);

    // A platform view starts a new group. Everything visited after this point
    // paints on top of it.
    if (node is PlatformViewRenderBox) {
      visitedPlatformViews += 1;
      if (node.hasSize && !node.size.isEmpty) {
        Rect platformViewRect = _toGlobal(Offset.zero & node.size, transform);
        if (clip != null) {
          platformViewRect = platformViewRect.intersect(clip);
        }
        groups.add((
          viewId: node.controller.viewId,
          platformViewRect: platformViewRect,
          rects: <Rect>[],
        ));
        currentGroupFullyCovered = false;
      }
      return;
    }

    if (allPlatformViewsVisited() &&
        (currentGroupFullyCovered ||
            childIgnoringPointers ||
            clipMissedAtGroupCount == groups.length)) {
      return;
    }

    final bool checksBounds = !childIgnoringPointers && hitTestsWithinBounds(node);
    var nodeClaimedOwnBounds = false;

    // Nothing can cover a platform view until one has been painted, and
    // render objects that ignore pointers never claim a region.
    if (groups.isNotEmpty && !selfIgnoringPointers) {
      if (!(enableEarlyStop && currentGroupFullyCovered) &&
          clipMissedAtGroupCount != groups.length) {
        // visitHitTestRegions is protected, but asking a render object where it
        // accepts pointer events is exactly the question this pass needs
        // answered, without running a full hit test.
        currentTransform = transform;
        currentHitTestClip = hitTestClip;
        currentNodeBounds = checksBounds ? (Offset.zero & (node as RenderBox).size) : null;
        claimedOwnBounds = false;
        // ignore: invalid_use_of_protected_member
        node.visitHitTestRegions(claimRegion);
        nodeClaimedOwnBounds = enableEarlyStop && claimedOwnBounds;
      }
      if (allPlatformViewsVisited() && (currentGroupFullyCovered || nodeClaimedOwnBounds)) {
        return;
      }
    }

    // A box that only hit tests within its bounds restricts where its
    // descendants can be hit, even if it does not clip their painting.
    int? descendantsClipMissedAtGroupCount = nodeClaimedOwnBounds
        ? groups.length
        : clipMissedAtGroupCount;
    final Rect? descendantsHitTestClip;
    if (checksBounds) {
      descendantsHitTestClip = intersectClip(
        hitTestClip,
        toGlobal(Offset.zero & (node as RenderBox).size, transform),
      );
      if (groups.isNotEmpty &&
          descendantsClipMissedAtGroupCount != groups.length &&
          !overlapsAnyPlatformView(descendantsHitTestClip)) {
        descendantsClipMissedAtGroupCount = groups.length;
      }
      if (allPlatformViewsVisited() && descendantsClipMissedAtGroupCount == groups.length) {
        return;
      }
    } else {
      descendantsHitTestClip = hitTestClip;
    }

    // Descend into the painted children in paint order, accumulating each
    // child's paint transform and clip.
    currentParent = node;
    currentDepth = depth;
    currentClip = clip;
    currentDescendantsHitTestClip = descendantsHitTestClip;
    currentIgnoringPointers = childIgnoringPointers;
    currentClipMissedAtGroupCount = descendantsClipMissedAtGroupCount;
    node.visitChildrenInPaintOrder(visitChild);
  }

  visitChild = (RenderObject child) {
    if (allPlatformViewsVisited() && currentGroupFullyCovered) {
      return;
    }
    final node = currentParent;
    final depth = currentDepth;
    final Matrix4 transform = transformStack[depth];
    final clip = currentClip;
    final descendantsHitTestClip = currentDescendantsHitTestClip;
    final childIgnoringPointers = currentIgnoringPointers;
    final clipMissedAtGroupCount = currentClipMissedAtGroupCount;

    var childClip = clip;
    var childHitTestClip = descendantsHitTestClip;
    var childClipMissedAtGroupCount = clipMissedAtGroupCount;
    final Rect? localClip = paintClipOf(node, child);
    if (localClip != null) {
      final Rect globalClip = toGlobal(localClip, transform);
      childClip = intersectClip(childClip, globalClip);
      childHitTestClip = intersectClip(childHitTestClip, globalClip);
      if (groups.isNotEmpty &&
          childClipMissedAtGroupCount != groups.length &&
          !overlapsAnyPlatformView(childHitTestClip)) {
        childClipMissedAtGroupCount = groups.length;
      }
    } else if (childClipMissedAtGroupCount != null &&
        childClipMissedAtGroupCount != groups.length &&
        childHitTestClip != null &&
        !overlapsAnyPlatformView(childHitTestClip)) {
      childClipMissedAtGroupCount = groups.length;
    }

    final int nextDepth = depth + 1;
    final Matrix4 childTransform;
    if (nextDepth < transformStack.length) {
      childTransform = transformStack[nextDepth]..setFrom(transform);
    } else {
      childTransform = Matrix4.copy(transform);
      transformStack.add(childTransform);
    }
    node.applyPaintTransform(child, childTransform);
    visit(
      child,
      nextDepth,
      childTransform,
      childClip,
      childHitTestClip,
      ignoringPointers: childIgnoringPointers,
      clipMissedAtGroupCount: childClipMissedAtGroupCount,
    );

    currentParent = node;
    currentDepth = depth;
    currentClip = clip;
    currentDescendantsHitTestClip = descendantsHitTestClip;
    currentIgnoringPointers = childIgnoringPointers;
    currentClipMissedAtGroupCount = clipMissedAtGroupCount;
  };

  visit(
    root,
    0,
    transformStack[0],
    null,
    null,
    ignoringPointers: false,
    clipMissedAtGroupCount: null,
  );

  if (groups.isEmpty) {
    return null;
  }

  // Flatten the groups into the encoding described above: for each group,
  // [viewId, rectCount] followed by rectCount * [left, top, right, bottom].
  var totalFloats = 0;
  for (final group in groups) {
    totalFloats += 2 + group.rects.length * 4;
  }

  final payload = Float64List(totalFloats);
  var index = 0;
  for (final group in groups) {
    payload[index++] = group.viewId.toDouble();
    payload[index++] = group.rects.length.toDouble();
    for (final Rect rect in group.rects) {
      payload[index++] = rect.left;
      payload[index++] = rect.top;
      payload[index++] = rect.right;
      payload[index++] = rect.bottom;
    }
  }
  return payload;
}

/// Reports the bounds of [renderObject] to [visitor] if it is a [RenderBox]
/// whose [RenderBox.hitTestSelf] returns true at the center of its bounds.
///
/// This is the default implementation of [RenderObject.visitHitTestRegions].
void visitDefaultHitTestRegions(RenderObject renderObject, HitTestRegionVisitor visitor) {
  if (renderObject is! RenderBox || !renderObject.hasSize || renderObject.size.isEmpty) {
    return;
  }
  final Size size = renderObject.size;
  // hitTestSelf is protected, but whether a box accepts a pointer event at
  // its center is the generic rule for where it claims pointer events.
  // ignore: invalid_use_of_protected_member
  if (renderObject.hitTestSelf(size.center(Offset.zero))) {
    // The box itself accepts pointer events (for example, it paints an opaque
    // background or handles gestures), so its bounds are a region.
    visitor(Offset.zero & size);
  }
}
