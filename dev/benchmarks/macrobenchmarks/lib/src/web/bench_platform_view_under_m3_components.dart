// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:web/web.dart' as web;

import 'material3.dart' as m3;
import 'recorder.dart';

const String _viewType = 'bench_platform_view_under_m3_components_view';

/// Measures frame time when rendering Material 3 components, dialogs, and
/// sheets stacked above a full-screen platform view with automatic pointer
/// interceptors enabled.
class BenchPlatformViewUnderM3Components extends WidgetRecorder {
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
  Widget createWidget() => const _PlatformViewUnderM3ComponentsApp();
}

class _PlatformViewUnderM3ComponentsApp extends StatefulWidget {
  const _PlatformViewUnderM3ComponentsApp();

  @override
  State<_PlatformViewUnderM3ComponentsApp> createState() =>
      _PlatformViewUnderM3ComponentsAppState();
}

class _PlatformViewUnderM3ComponentsAppState extends State<_PlatformViewUnderM3ComponentsApp>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Timer.run(() {
      if (!mounted) {
        return;
      }
      _ticker = createTicker((_) {
        setState(() {
          _generation += 1;
        });
      })..start();
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        key: m3.scaffoldKey,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: HtmlElementView(viewType: _viewType)),
            KeyedSubtree(
              key: ValueKey<int>(_generation),
              child: Stack(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: m3.FirstComponentList(
                          showNavBottomBar: true,
                          scaffoldKey: m3.scaffoldKey,
                          showSecondList: true,
                        ),
                      ),
                      Expanded(child: m3.SecondComponentList(scaffoldKey: m3.scaffoldKey)),
                    ],
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    width: 320,
                    child: AlertDialog(
                      title: const Text('Overlay Dialog'),
                      content: const Text('Dialog stacked over platform view'),
                      actions: <Widget>[
                        TextButton(onPressed: () {}, child: const Text('Cancel')),
                        FilledButton(onPressed: () {}, child: const Text('OK')),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    width: 320,
                    child: BottomSheet(
                      onClosing: () {},
                      builder: (BuildContext context) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              const Text('Sheet over platform view'),
                              FilledButton.tonal(onPressed: () {}, child: const Text('Action')),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
