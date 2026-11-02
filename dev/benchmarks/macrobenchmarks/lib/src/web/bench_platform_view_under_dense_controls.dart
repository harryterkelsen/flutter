// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'automatic_pointer_interceptors_bench.dart';
import 'recorder.dart';

const String _viewType = 'bench_platform_view_under_dense_controls_view';

/// The number of times the group of five controls is repeated in the grid.
const int _controlGroupCount = 60;

/// Measures frame time with a full-screen platform view under a dense,
/// non-scrolling grid of small controls, with automatic pointer interceptors
/// enabled.
///
/// The platform view is painted first and the controls are laid out over it
/// with gaps between them, so no single opaque box covers the platform view
/// and the hit-region walk cannot stop early. About 1,100 of the roughly
/// 2,500 render objects are visited per frame, producing about 270 regions.
/// This case remains expensive even when the walk can skip subtrees that are
/// painted before the platform view.
///
/// The controls are never rebuilt. Only a small indeterminate progress
/// indicator animates, so frames are cheap and the walk dominates them. The
/// hit-test region payload is the same on every frame, so this measures the
/// walk rather than churn in the platform view proxy elements.
class BenchPlatformViewUnderDenseControls extends WidgetRecorder
    with AutomaticPointerInterceptorsBench {
  BenchPlatformViewUnderDenseControls() : super(name: benchmarkName);

  static const String benchmarkName = 'bench_platform_view_under_dense_controls';

  @override
  Future<void> setUpAll() async {
    await super.setUpAll();
    registerFullSizeDivViewFactory(_viewType);
  }

  @override
  Widget createWidget() => const _PlatformViewUnderDenseControlsApp();
}

class _PlatformViewUnderDenseControlsApp extends StatelessWidget {
  const _PlatformViewUnderDenseControlsApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Stack(
        children: <Widget>[
          const Positioned.fill(child: HtmlElementView(viewType: _viewType)),
          Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (int i = 0; i < _controlGroupCount; i++) ...<Widget>[
                    ElevatedButton(onPressed: () {}, child: Text('Button $i')),
                    Chip(label: Text('Chip $i')),
                    Checkbox(value: i.isEven, onChanged: (_) {}),
                    Text('Label $i'),
                    const Icon(Icons.star),
                  ],
                ],
              ),
            ),
          ),
          const Positioned(
            right: 16,
            bottom: 16,
            width: 24,
            height: 24,
            // Keeps the indicator's animation from repainting the controls.
            child: RepaintBoundary(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
