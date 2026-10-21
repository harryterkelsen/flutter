// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart' as test;

/// Runs `hit_test_proxy_integration.dart` and performs the real pointer clicks
/// it requests.
///
/// The in-browser test requests a click by calling `takeScreenshot` with the
/// viewport coordinates in its arguments. The click is a WebDriver pointer
/// action, so the browser hit-tests the DOM exactly as it would for a user.
Future<void> main() async {
  final driver = await FlutterDriver.connect() as WebFlutterDriver;
  await (await driver.webDriver.window).setSize(const Rectangle<int>(0, 0, 1024, 1024));

  await test.integrationDriver(
    driver: driver,
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final Object? x = args?['x'];
      final Object? y = args?['y'];
      if (x is! int || y is! int) {
        return false;
      }
      await driver.webDriver.mouse.moveTo(xOffset: x, yOffset: y, absolute: true);
      await driver.webDriver.mouse.click();
      return true;
    },
  );
}
