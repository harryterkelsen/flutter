// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

import 'material3.dart';
import 'recorder.dart';

const String _viewType = 'bench_platform_view_under_m3_components_view';

/// Measures the cost of constructing the Material 3 components screen painted
/// on top of a full-screen platform view with automatic pointer interceptors
/// enabled.
class BenchPlatformViewUnderM3Components extends WidgetBuildRecorder {
  BenchPlatformViewUnderM3Components() : super(name: benchmarkName);

  static const String benchmarkName = 'bench_platform_view_under_m3_components';

  static bool _factoryRegistered = false;

  @override
  Future<void> setUpAll() async {
    await super.setUpAll();
    if (!_factoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final element = web.document.createElement('div') as web.HTMLDivElement;
        element.style
          ..width = '100%'
          ..height = '100%';
        return element;
      });
      _factoryRegistered = true;
    }
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
  }

  @override
  Future<void> tearDownAll() async {
    RendererBinding.instance.automaticPointerInterceptorsEnabled = false;
    await super.tearDownAll();
  }

  @override
  Widget createWidget() {
    return MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: HtmlElementView(viewType: _viewType)),
            Row(
              children: <Widget>[
                Expanded(
                  child: FirstComponentList(
                    showNavBottomBar: true,
                    scaffoldKey: scaffoldKey,
                    showSecondList: true,
                  ),
                ),
                Expanded(child: SecondComponentList(scaffoldKey: scaffoldKey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
