// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'automatic_pointer_interceptors_bench.dart';
import 'material3.dart' as m3;
import 'recorder.dart';

const String _viewType = 'bench_platform_view_under_m3_components_view';

/// Measures frame time when rendering Material 3 components, dialogs, and
/// sheets stacked above a full-screen platform view with automatic pointer
/// interceptors enabled.
///
/// The platform view is painted first, *behind* the app. Content painted after
/// it soon claims a hit-test region covering the whole platform view, so the
/// hit-region walk stops early (about 18 render objects visited per frame).
/// This is the common case, not the worst case. See `bench_platform_view_over_m3_components` (a platform view painted
/// after the whole page) and `bench_platform_view_under_dense_controls` (a
/// platform view under a dense UI with gaps) for the worst cases.
class BenchPlatformViewUnderM3Components extends WidgetRecorder
    with AutomaticPointerInterceptorsBench {
  BenchPlatformViewUnderM3Components() : super(name: benchmarkName);

  static const String benchmarkName = 'bench_platform_view_under_m3_components';

  @override
  Future<void> setUpAll() async {
    await super.setUpAll();
    registerFullSizeDivViewFactory(_viewType);
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
