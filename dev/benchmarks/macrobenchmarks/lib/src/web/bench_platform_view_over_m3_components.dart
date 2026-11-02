// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'automatic_pointer_interceptors_bench.dart';
import 'material3.dart' as m3;
import 'recorder.dart';

const String _viewType = 'bench_platform_view_over_m3_components_view';

/// Measures frame time while scrolling the Material 3 components page with a
/// platform view painted after the whole page, with automatic pointer
/// interceptors enabled.
///
/// The platform view and a small tappable box sit on top of the page, like an
/// overlay. Because the platform view is painted after everything else, the
/// hit-region walk cannot stop early: it visits the entire render tree on
/// every scroll frame. This is a worst case for the walk.
///
/// The UI is not rebuilt each frame. Frames are driven only by scrolling the
/// first component list, so the walk is a large share of each frame.
class BenchPlatformViewOverM3Components extends WidgetRecorder
    with AutomaticPointerInterceptorsBench {
  BenchPlatformViewOverM3Components() : super(name: benchmarkName);

  static const String benchmarkName = 'bench_platform_view_over_m3_components';

  @override
  Future<void> setUpAll() async {
    await super.setUpAll();
    registerFullSizeDivViewFactory(_viewType);
  }

  @override
  Widget createWidget() => const _PlatformViewOverM3ComponentsApp();
}

class _PlatformViewOverM3ComponentsApp extends StatefulWidget {
  const _PlatformViewOverM3ComponentsApp();

  @override
  State<_PlatformViewOverM3ComponentsApp> createState() => _PlatformViewOverM3ComponentsAppState();
}

class _PlatformViewOverM3ComponentsAppState extends State<_PlatformViewOverM3ComponentsApp>
    with SingleTickerProviderStateMixin {
  /// How far the first component list scrolls on each frame, in logical
  /// pixels.
  static const double _scrollStep = 20;

  final ScrollController _controller = ScrollController();
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    // Wait for the first layout so the scroll extents are known.
    Timer.run(() {
      if (!mounted) {
        return;
      }
      _ticker = createTicker(_scroll)..start();
    });
  }

  void _scroll(Duration elapsed) {
    if (!_controller.hasClients) {
      return;
    }
    final ScrollPosition position = _controller.position;
    double next = position.pixels + _scrollStep;
    if (next > position.maxScrollExtent) {
      next = 0;
    }
    _controller.jumpTo(next);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          m3.TwoColumnMaterial3Components(scrollController: _controller),
          const Positioned(
            left: 600,
            top: 400,
            width: 400,
            height: 300,
            child: HtmlElementView(viewType: _viewType),
          ),
          Positioned(
            left: 700,
            top: 500,
            width: 100,
            height: 40,
            child: GestureDetector(
              onTap: () {},
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
