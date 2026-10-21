// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

/// Platform view type of the full-screen iframe painted under the dialog.
const String pv1ViewType = 'hit-test-proxy-pv1';

/// Platform view type of the iframe shown inside the dialog.
const String pv2ViewType = 'hit-test-proxy-pv2';

/// Key of the [SizedBox] that hosts PV2 inside the dialog.
const Key pv2Key = ValueKey<String>('pv2');

/// Key of the dialog's title text, which is painted over PV1.
const Key dialogTitleKey = ValueKey<String>('dialog-title');

/// Turns automatic pointer interceptors off when built with
/// `--dart-define=HIT_TEST_PROXY_OFF=true`.
const bool _offByDefine = bool.fromEnvironment('HIT_TEST_PROXY_OFF');

/// Whether this app turns on automatic pointer interceptors.
///
/// They are on unless the page URL has an `off` query parameter or the app was
/// built with `--dart-define=HIT_TEST_PROXY_OFF=true`.
bool get automaticPointerInterceptorsRequested =>
    !_offByDefine && !Uri.base.queryParameters.containsKey('off');

/// Number of `click` events received by PV1's document.
int pv1Clicks = 0;

/// Number of `click` events received by the documents of PV2 instances.
int pv2Clicks = 0;

Completer<void> _pv1Loaded = Completer<void>();
Completer<void> _pv2Loaded = Completer<void>();

/// Completes when PV1's document has loaded and counts clicks.
@visibleForTesting
Future<void> get pv1Loaded => _pv1Loaded.future;

/// Completes when the most recently created PV2's document has loaded and
/// counts clicks.
@visibleForTesting
Future<void> get pv2Loaded => _pv2Loaded.future;

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

bool _factoriesRegistered = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (automaticPointerInterceptorsRequested) {
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
  }
  _registerFactories();
  runApp(const HitTestProxyApp());
}

void _registerFactories() {
  if (_factoriesRegistered) {
    return;
  }
  _factoriesRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(pv1ViewType, (int viewId) {
    if (_pv1Loaded.isCompleted) {
      _pv1Loaded = Completer<void>();
    }
    return _createCountingIFrame(
      label: 'PV1',
      background: '#cfe8ff',
      onClick: () => pv1Clicks += 1,
      loaded: _pv1Loaded,
    );
  });
  ui_web.platformViewRegistry.registerViewFactory(pv2ViewType, (int viewId) {
    if (_pv2Loaded.isCompleted) {
      _pv2Loaded = Completer<void>();
    }
    return _createCountingIFrame(
      label: 'PV2',
      background: '#ffe0b2',
      onClick: () => pv2Clicks += 1,
      loaded: _pv2Loaded,
    );
  });
}

/// Creates a same-origin `<iframe srcdoc>` whose document counts clicks.
web.HTMLIFrameElement _createCountingIFrame({
  required String label,
  required String background,
  required void Function() onClick,
  required Completer<void> loaded,
}) {
  final iframe = web.HTMLIFrameElement();
  iframe.style
    ..border = 'none'
    ..width = '100%'
    ..height = '100%';
  iframe.srcdoc =
      '<!DOCTYPE html><html><body style="margin:0;height:100vh; '
              'background:$background;font:24px sans-serif">$label</body></html>'
          .toJS;
  iframe.addEventListener(
    'load',
    (web.Event _) {
      iframe.contentDocument!.addEventListener(
        'click',
        (web.Event _) {
          onClick();
        }.toJS,
      );
      if (!loaded.isCompleted) {
        loaded.complete();
      }
    }.toJS,
  );
  return iframe;
}

/// Opens a barrier-dismissible dialog over PV1 whose content includes PV2.
void openDialog() {
  showDialog<void>(
    context: _navigatorKey.currentContext!,
    builder: (BuildContext context) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 300,
                height: 60,
                child: Center(child: Text('Dialog over PV1', key: dialogTitleKey)),
              ),
              SizedBox(
                key: pv2Key,
                width: 300,
                height: 200,
                child: HtmlElementView(viewType: pv2ViewType),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A full-screen counting iframe (PV1) with a button that opens a dialog
/// containing another counting iframe (PV2).
class HitTestProxyApp extends StatelessWidget {
  const HitTestProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            HtmlElementView(viewType: pv1ViewType),
            Positioned(
              left: 16,
              bottom: 16,
              child: ElevatedButton(onPressed: openDialog, child: Text('Open dialog')),
            ),
          ],
        ),
      ),
    );
  }
}
