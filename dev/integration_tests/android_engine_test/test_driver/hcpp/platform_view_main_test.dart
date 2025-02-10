// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:android_driver_extensions/native_driver.dart';
import 'package:android_driver_extensions/skia_gold.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

import '../_luci_skia_gold_prelude.dart';

/// For local debugging, a (local) golden-file is required as a baseline:
///
/// ```sh
/// # Checkout HEAD, i.e. *before* changes you want to test.
/// UPDATE_GOLDENS=1 flutter drive lib/platform_view/hcpp/platform_view_main.dart
///
/// # Make your changes.
///
/// # Run the test against baseline.
/// flutter drive lib/platform_view/hcpp/platform_view_main.dart
/// ```
///
/// For a convenient way to deflake a test, see `tool/deflake.dart`.
void main() async {
  const String goldenPrefix = 'hybrid_composition_pp_platform_view';

  late final FlutterDriver flutterDriver;
  late final NativeDriver nativeDriver;

  setUpAll(() async {
    if (isLuci) {
      await enableSkiaGoldComparator(namePrefix: 'android_engine_test$goldenVariant');
    }
    flutterDriver = await FlutterDriver.connect();
    nativeDriver = await AndroidNativeDriver.connect(flutterDriver);
    await nativeDriver.configureForScreenshotTesting();
    await flutterDriver.waitUntilFirstFrameRasterized();
  });

  tearDownAll(() async {
    await nativeDriver.close();
    await flutterDriver.close();
  });

  test('should screenshot an HCPP platform view', () async {
    await expectLater(
      nativeDriver.screenshot(),
      matchesGoldenFile('$goldenPrefix.platform_view.png'),
    );
  }, timeout: Timeout.none);

  test('should rotate landscape and screenshot the platform view', () async {
    await nativeDriver.rotateToLandscape();
    await expectLater(
      nativeDriver.screenshot(),
      matchesGoldenFile('$goldenPrefix.platform_view_landscape_rotated.png'),
    );

    await nativeDriver.rotateResetDefault();
    await expectLater(
      nativeDriver.screenshot(),
      matchesGoldenFile('$goldenPrefix.platform_view_portait_rotated_back.png'),
    );
  }, timeout: Timeout.none);
}
