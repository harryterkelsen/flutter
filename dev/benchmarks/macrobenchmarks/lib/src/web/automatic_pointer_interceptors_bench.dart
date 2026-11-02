// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui_web' as ui_web;

import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;

import 'recorder.dart';

/// Turns on [RendererBinding.automaticPointerInterceptorsEnabled] for the
/// duration of a platform view hit-region benchmark.
///
/// The previous value of the flag is restored in [tearDownAll] rather than
/// forcing it to `false`, so a benchmark that uses this mixin does not change
/// the flag for benchmarks that run after it in the same session.
mixin AutomaticPointerInterceptorsBench on WidgetRecorder {
  /// The value of the flag before [setUpAll], restored by [tearDownAll].
  bool? _previousEnabled;

  @override
  Future<void> setUpAll() async {
    await super.setUpAll();
    _previousEnabled = RendererBinding.instance.automaticPointerInterceptorsEnabled;
    RendererBinding.instance.automaticPointerInterceptorsEnabled = true;
  }

  @override
  Future<void> tearDownAll() async {
    final bool? previous = _previousEnabled;
    if (previous != null) {
      RendererBinding.instance.automaticPointerInterceptorsEnabled = previous;
      _previousEnabled = null;
    }
    await super.tearDownAll();
  }
}

final Set<String> _registeredViewTypes = <String>{};

/// Registers a platform view factory for [viewType] that creates a `<div>`
/// filling its platform view slot.
///
/// Calling this more than once with the same [viewType] has no effect.
void registerFullSizeDivViewFactory(String viewType) {
  if (!_registeredViewTypes.add(viewType)) {
    return;
  }
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final element = web.document.createElement('div') as web.HTMLDivElement;
    element.style
      ..width = '100%'
      ..height = '100%';
    return element;
  });
}
