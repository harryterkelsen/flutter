// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:test/bootstrap/browser.dart';
import 'package:test/test.dart';
import 'package:ui/src/engine.dart';
import 'package:ui/ui.dart' as ui;
import 'package:ui/ui_web/src/ui_web.dart' as ui_web;

import '../common/rendering.dart';
import '../common/test_initialization.dart';
import 'utils.dart';

EngineFlutterWindow get implicitView => EnginePlatformDispatcher.instance.implicitView!;

DomElement get sceneHost => implicitView.dom.sceneHost;
DomShadowRoot get renderingHost => implicitView.dom.renderingHost;

void main() {
  internalBootstrapBrowserTest(() => testMain);
}

const String _platformViewType = 'test-hit-test-proxy-platform-view';

// Platform view ids used throughout the tests.
const int _pv1 = 1;
const int _pv2 = 2;
const int _unknownViewId = 99;

// Geometry in CSS (logical) pixels. Each test multiplies these by the device
// pixel ratio to obtain the physical pixels used by the scene and the payload.
//
//   * PV1 is a large platform view painted first.
//   * The barrier covers PV1 entirely and is painted after PV1.
//   * The dialog is painted on top of the barrier.
//   * PV2 is a smaller platform view painted inside the dialog, after it.
const ui.Rect _pv1Rect = ui.Rect.fromLTWH(0, 0, 400, 300);
const ui.Rect _barrierRect = ui.Rect.fromLTWH(0, 0, 400, 300);
const ui.Rect _dialogRect = ui.Rect.fromLTWH(100, 75, 200, 150);
const ui.Rect _pv2Rect = ui.Rect.fromLTWH(150, 100, 100, 100);

// Points in CSS pixels, relative to the Flutter view.
const ui.Offset _barrierPoint = ui.Offset(20, 20);
const ui.Offset _dialogPoint = ui.Offset(120, 90);
const ui.Offset _pv2Point = ui.Offset(200, 150);

Future<void> testMain() async {
  setUpUnitTests(withImplicitView: true, setUpTestViewDimensions: false);

  setUp(() {
    ui_web.platformViewRegistry.registerViewFactory(_platformViewType, (int viewId) {
      return createDomHTMLDivElement()
        ..id = 'view-$viewId'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  });

  tearDown(() {
    EngineFlutterDisplay.instance.debugOverrideDevicePixelRatio(null);
    PlatformViewManager.instance.debugClear();
    renderer.debugClear();
  });

  for (final dpr in <double>[1, 2]) {
    group('at device pixel ratio ${dpr.toInt()}', () {
      setUp(() async {
        EngineFlutterDisplay.instance.debugOverrideDevicePixelRatio(dpr);
        await createPlatformView(_pv1, _platformViewType);
        await createPlatformView(_pv2, _platformViewType);
      });

      Future<void> renderDialogOverPlatformView() {
        return _renderWithHitTestRegions(
          _buildDialogScene(dpr),
          _payload(<(int, List<ui.Rect>)>[
            (_pv1, <ui.Rect>[_barrierRect, _dialogRect]),
            (_pv2, <ui.Rect>[]),
          ], dpr),
        );
      }

      test('places the hit-test proxy between the platform views it separates', () async {
        await renderDialogOverPlatformView();

        expect(_sceneChildren(), <String>['pv-$_pv1', 'proxy', 'pv-$_pv2']);
      });

      test('sizes and positions proxy rects in CSS pixels', () async {
        await renderDialogOverPlatformView();

        final DomElement proxy = _singleProxy();
        final List<DomElement> rects = proxy.children.toList();
        expect(rects, hasLength(2));
        _expectProxyRect(rects[0], _barrierRect);
        _expectProxyRect(rects[1], _dialogRect);
      });

      test('proxies win hit tests over the platform view below them', () async {
        await renderDialogOverPlatformView();

        final List<DomElement> rects = _singleProxy().children.toList();
        expect(_elementAt(_barrierPoint), rects[0]);
        expect(_elementAt(_dialogPoint), rects[1]);
        expect(_platformViewIdOf(_elementAt(_pv2Point)), _pv2);
      });

      test('forwards pointer events on a proxy to the framework', () async {
        await renderDialogOverPlatformView();

        final packets = <ui.PointerDataPacket>[];
        final ui.PointerDataPacketCallback? oldCallback =
            ui.PlatformDispatcher.instance.onPointerDataPacket;
        ui.PlatformDispatcher.instance.onPointerDataPacket = packets.add;
        addTearDown(() {
          ui.PlatformDispatcher.instance.onPointerDataPacket = oldCallback;
        });

        final DomElement dialogProxyRect = _singleProxy().children.toList()[1];
        final ui.Offset client = _toClient(_dialogPoint);
        dialogProxyRect.dispatchEvent(_pointerEvent('pointerdown', client, buttons: 1));
        domWindow.dispatchEvent(_pointerEvent('pointerup', client, buttons: 0));

        final ui.PointerData down = packets
            .expand((ui.PointerDataPacket packet) => packet.data)
            .singleWhere((ui.PointerData data) => data.change == ui.PointerChange.down);
        expect(down.viewId, implicitView.viewId);
        expect(down.physicalX / implicitView.devicePixelRatio, _dialogPoint.dx);
        expect(down.physicalY / implicitView.devicePixelRatio, _dialogPoint.dy);
        expect(down.physicalX, _dialogPoint.dx * dpr);
        expect(down.physicalY, _dialogPoint.dy * dpr);
      });

      test('removes proxies when the payload becomes empty', () async {
        await renderDialogOverPlatformView();
        expect(_proxies(), hasLength(1));

        await _renderWithHitTestRegions(_buildDialogScene(dpr), Float64List(0));

        expect(_proxies(), isEmpty);
        expect(_sceneChildren(), <String>['pv-$_pv1', 'pv-$_pv2']);
        expect(_platformViewIdOf(_elementAt(_barrierPoint)), _pv1);
      });

      test('ignores groups for platform views that are not in the scene', () async {
        await _renderWithHitTestRegions(
          _buildDialogScene(dpr, includePv2: false),
          _payload(<(int, List<ui.Rect>)>[
            (_unknownViewId, <ui.Rect>[_dialogRect]),
            (_pv1, <ui.Rect>[_barrierRect]),
            (_pv2, <ui.Rect>[_dialogRect]),
          ], dpr),
        );

        expect(_sceneChildren(), <String>['pv-$_pv1', 'proxy']);
        final List<DomElement> rects = _singleProxy().children.toList();
        expect(rects, hasLength(1));
        _expectProxyRect(rects.single, _barrierRect);
      });
    });
  }
}

/// Renders [scene] and then reports [regions] to the implicit view, in the same
/// order the framework does at the end of a frame.
Future<void> _renderWithHitTestRegions(ui.Scene scene, Float64List regions) async {
  final ui.FlutterView view = implicitView;
  final Future<void> rendered = renderScene(scene);
  view.updateHitTestRegions(regions);
  await rendered;
}

/// Builds a scene with PV1, a dialog picture over it, and (optionally) PV2
/// inside the dialog. All coordinates are in physical pixels.
ui.Scene _buildDialogScene(double dpr, {bool includePv2 = true}) {
  final ui.Rect pv1 = _scale(_pv1Rect, dpr);
  final ui.Rect pv2 = _scale(_pv2Rect, dpr);
  final ui.Picture dialog = drawPicture((ui.Canvas canvas) {
    canvas.drawRect(_scale(_barrierRect, dpr), ui.Paint()..color = const ui.Color(0x80000000));
    canvas.drawRect(_scale(_dialogRect, dpr), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  });

  final sb = ui.SceneBuilder();
  sb.pushOffset(0, 0);
  sb.addPlatformView(_pv1, offset: pv1.topLeft, width: pv1.width, height: pv1.height);
  sb.addPicture(ui.Offset.zero, dialog);
  if (includePv2) {
    sb.addPlatformView(_pv2, offset: pv2.topLeft, width: pv2.width, height: pv2.height);
  }
  sb.pop();
  return sb.build();
}

/// Encodes `[platformViewId, n, l, t, r, b × n, …]` in physical pixels.
Float64List _payload(List<(int, List<ui.Rect>)> groups, double dpr) {
  return Float64List.fromList(<double>[
    for (final (int viewId, List<ui.Rect> rects) in groups) ...<double>[
      viewId.toDouble(),
      rects.length.toDouble(),
      for (final ui.Rect rect in rects) ...<double>[
        rect.left * dpr,
        rect.top * dpr,
        rect.right * dpr,
        rect.bottom * dpr,
      ],
    ],
  ]);
}

ui.Rect _scale(ui.Rect rect, double factor) {
  return ui.Rect.fromLTRB(
    rect.left * factor,
    rect.top * factor,
    rect.right * factor,
    rect.bottom * factor,
  );
}

DomElement get _fltScene => sceneHost.querySelector('flt-scene')!;

/// All `<flt-hit-test-proxy>` elements rendered in the scene.
List<DomElement> _proxies() => sceneHost.querySelectorAll('flt-hit-test-proxy').toList();

/// The only `<flt-hit-test-proxy>` element rendered in the scene.
DomElement _singleProxy() {
  final List<DomElement> proxies = _proxies();
  expect(proxies, hasLength(1), reason: 'Expected exactly one <flt-hit-test-proxy> in the scene.');
  return proxies.single;
}

/// Describes the children of `<flt-scene>` that take part in hit testing, in
/// DOM order: `pv-<id>` for platform views and `proxy` for hit-test proxies.
/// Canvases are omitted because they never receive pointer events.
List<String> _sceneChildren() {
  final result = <String>[];
  for (final DomElement child in _fltScene.children) {
    switch (child.tagName.toLowerCase()) {
      case 'flt-hit-test-proxy':
        result.add('proxy');
      case 'flt-platform-view-slot':
      case 'flt-clip':
        result.add('pv-${_platformViewIdOf(child)}');
    }
  }
  return result;
}

/// Returns the id of the platform view that [element] belongs to, or null if
/// [element] isn't part of a platform view.
///
/// [element] may be part of the platform view's slot inside the rendering
/// shadow root, or part of its slotted contents in the light DOM (which is what
/// Chrome returns when hit testing a slotted platform view through the shadow
/// root).
int? _platformViewIdOf(DomElement? element) {
  const slotPrefix = 'flt-pv-slot-';
  var current = element;
  while (current != null) {
    switch (current.tagName.toLowerCase()) {
      case 'flt-platform-view-slot':
        final String name = current.querySelector('slot')!.getAttribute('name')!;
        return int.parse(name.substring(slotPrefix.length));
      case 'flt-clip':
        return _platformViewIdOf(current.querySelector('flt-platform-view-slot'));
      case 'flt-platform-view':
        return int.parse(current.getAttribute('slot')!.substring(slotPrefix.length));
    }
    current = current.parent;
  }
  return null;
}

/// Converts a point relative to the Flutter view into viewport coordinates.
ui.Offset _toClient(ui.Offset point) {
  final DomRect origin = implicitView.dom.rootElement.getBoundingClientRect();
  return ui.Offset(origin.left + point.dx, origin.top + point.dy);
}

/// Hit tests the rendering shadow root at [point] (relative to the view).
DomElement? _elementAt(ui.Offset point) {
  final ui.Offset client = _toClient(point);
  return renderingHost.elementFromPoint(client.dx.round(), client.dy.round());
}

void _expectProxyRect(DomElement element, ui.Rect expected) {
  expect(element.style.left, '${expected.left.round()}px');
  expect(element.style.top, '${expected.top.round()}px');
  expect(element.style.width, '${expected.width.round()}px');
  expect(element.style.height, '${expected.height.round()}px');

  final DomRect bounds = element.getBoundingClientRect();
  final ui.Offset origin = _toClient(ui.Offset.zero);
  expect(bounds.left - origin.dx, expected.left);
  expect(bounds.top - origin.dy, expected.top);
  expect(bounds.width, expected.width);
  expect(bounds.height, expected.height);
}

DomPointerEvent _pointerEvent(String type, ui.Offset client, {required int buttons}) {
  return createDomPointerEvent(type, <String, dynamic>{
    'bubbles': true,
    'composed': true,
    'cancelable': true,
    'pointerId': 1,
    'pointerType': 'mouse',
    'button': 0,
    'buttons': buttons,
    'clientX': client.dx,
    'clientY': client.dy,
  });
}
