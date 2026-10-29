// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:ui/ui.dart' as ui;

import '../dom.dart';

/// The rects of Flutter content that is hit tested above the platform view
/// with id `viewId`, in physical pixels.
typedef HitTestProxyGroup = ({int viewId, List<ui.Rect> rects});

/// Decodes the hit-test regions reported through
/// [ui.FlutterView.updateHitTestRegions].
///
/// The [regions] are encoded as a flat, paint-ordered list of groups,
/// `[platformViewId, n, (left, top, right, bottom) × n, …]`, in physical
/// pixels.
List<HitTestProxyGroup> decodeHitTestRegions(Float64List regions) {
  final groups = <HitTestProxyGroup>[];
  var index = 0;
  while (index + 2 <= regions.length) {
    final int viewId = regions[index].toInt();
    final int count = regions[index + 1].toInt();
    index += 2;
    assert(index + count * 4 <= regions.length, 'Malformed hit-test regions: $regions');
    if (index + count * 4 > regions.length) {
      break;
    }
    final rects = <ui.Rect>[
      for (var i = 0; i < count; i++, index += 4)
        ui.Rect.fromLTRB(
          regions[index],
          regions[index + 1],
          regions[index + 2],
          regions[index + 3],
        ),
    ];
    groups.add((viewId: viewId, rects: rects));
  }
  return groups;
}

final List<DomElement> _proxyElementPool = <DomElement>[];
final List<DomElement> _rectElementPool = <DomElement>[];

/// Creates an empty `<flt-hit-test-proxy>` element, reusing a pooled element if
/// available.
///
/// The element covers the whole scene but doesn't receive pointer events
/// itself. Its children, added by [updateHitTestProxyElement], receive pointer
/// events in place of the platform views painted below them. The events then
/// bubble up to the Flutter view, which forwards them to the framework.
DomElement createHitTestProxyElement() {
  if (_proxyElementPool.isNotEmpty) {
    return _proxyElementPool.removeLast();
  }
  final DomElement element = createDomElement('flt-hit-test-proxy');
  element.style
    ..position = 'absolute'
    ..setProperty('inset', '0')
    ..pointerEvents = 'none';
  // Like `package:pointer_interceptor`, prevent the default action of
  // `mousedown` so that clicking a proxy doesn't steal focus from a Flutter
  // text field.
  element.addEventListener('mousedown', _preventDefaultListener);
  return element;
}

/// Detaches any child rect elements of [element] and returns both the children
/// and [element] to the hit-test proxy pools for reuse.
void releaseHitTestProxyElement(DomElement element) {
  while (element.lastElementChild != null) {
    final DomElement child = element.lastElementChild!;
    child.remove();
    _rectElementPool.add(child);
  }
  _proxyElementPool.add(element);
}

/// Clears the pooled `<flt-hit-test-proxy>` and child `<div>` elements.
void clearHitTestProxyPool() {
  _proxyElementPool.clear();
  _rectElementPool.clear();
}

final DomEventListener _preventDefaultListener = createDomEventListener((DomEvent event) {
  event.preventDefault();
});

DomElement _createOrTakeRectElement() {
  if (_rectElementPool.isNotEmpty) {
    return _rectElementPool.removeLast();
  }
  final DomElement rectElement = createDomHTMLDivElement();
  rectElement.style
    ..position = 'absolute'
    ..pointerEvents = 'auto';
  return rectElement;
}

/// Updates the children of a `<flt-hit-test-proxy>` [element] in-place with one
/// child element per rect in [rects], reusing existing and pooled `<div>`
/// elements.
///
/// The [rects] are in physical pixels and are converted to CSS pixels using
/// [devicePixelRatio].
void updateHitTestProxyElement(DomElement element, List<ui.Rect> rects, double devicePixelRatio) {
  DomElement? currentChild = element.firstElementChild;
  for (var i = 0; i < rects.length; i++) {
    final ui.Rect rect = rects[i];
    final DomElement rectElement;
    if (currentChild != null) {
      rectElement = currentChild;
      currentChild = currentChild.nextElementSibling;
    } else {
      rectElement = _createOrTakeRectElement();
      element.append(rectElement);
    }
    final DomCSSStyleDeclaration style = rectElement.style;
    final leftCss = '${rect.left / devicePixelRatio}px';
    final topCss = '${rect.top / devicePixelRatio}px';
    final widthCss = '${rect.width / devicePixelRatio}px';
    final heightCss = '${rect.height / devicePixelRatio}px';
    if (style.left != leftCss) {
      style.left = leftCss;
    }
    if (style.top != topCss) {
      style.top = topCss;
    }
    if (style.width != widthCss) {
      style.width = widthCss;
    }
    if (style.height != heightCss) {
      style.height = heightCss;
    }
  }
  while (currentChild != null) {
    final DomElement? next = currentChild.nextElementSibling;
    currentChild.remove();
    _rectElementPool.add(currentChild);
    currentChild = next;
  }
}
