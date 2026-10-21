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

/// Creates an empty `<flt-hit-test-proxy>` element.
///
/// The element covers the whole scene but doesn't receive pointer events
/// itself. Its children, added by [updateHitTestProxyElement], receive pointer
/// events in place of the platform views painted below them. The events then
/// bubble up to the Flutter view, which forwards them to the framework.
DomElement createHitTestProxyElement() {
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

final DomEventListener _preventDefaultListener = createDomEventListener((DomEvent event) {
  event.preventDefault();
});

/// Replaces the children of a `<flt-hit-test-proxy>` [element] with one child
/// element per rect in [rects].
///
/// The [rects] are in physical pixels and are converted to CSS pixels using
/// [devicePixelRatio].
void updateHitTestProxyElement(DomElement element, List<ui.Rect> rects, double devicePixelRatio) {
  element.clearChildren();
  for (final rect in rects) {
    final DomElement rectElement = createDomHTMLDivElement();
    rectElement.style
      ..position = 'absolute'
      ..pointerEvents = 'auto'
      ..left = '${rect.left / devicePixelRatio}px'
      ..top = '${rect.top / devicePixelRatio}px'
      ..width = '${rect.width / devicePixelRatio}px'
      ..height = '${rect.height / devicePixelRatio}px';
    element.append(rectElement);
  }
}
