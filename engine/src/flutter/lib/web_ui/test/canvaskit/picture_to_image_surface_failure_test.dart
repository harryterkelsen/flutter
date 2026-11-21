// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:test/bootstrap/browser.dart';
import 'package:test/test.dart';
import 'package:ui/src/engine.dart';
import 'package:ui/ui.dart' as ui;

import 'common.dart';

void main() {
  internalBootstrapBrowserTest(() => testMain);
}

void testMain() {
  setUpCanvasKitTest();

  JSAny? originalMakeSWCanvasSurface;
  JSAny? originalMakeImage;

  void resetPictureToImageSurface() {
    try {
      CanvasKitRenderer.instance.pictureToImageSurface.dispose();
    } catch (_) {}
    CanvasKitRenderer.instance.debugResetRasterizer();
  }

  setUp(() {
    originalMakeSWCanvasSurface = canvasKit['MakeSWCanvasSurface'];
    originalMakeImage = canvasKit['MakeImage'];
  });

  tearDown(() {
    canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
    canvasKit['MakeImage'] = originalMakeImage;
    CkSurface.debugForceGLFailure = false;
    resetPictureToImageSurface();
  });

  group('CkPicture.toImageSync', () {
    test('wraps bare JS throws in a StateError and recovers', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      CkSurface.debugForceGLFailure = true;
      canvasKit['MakeSWCanvasSurface'] = _jsThrow(_canvasNotFoundMessage);
      resetPictureToImageSurface();
      expect(() => picture.toImageSync(1, 1), _throwsStateError(_canvasNotFoundMessage));

      CkSurface.debugForceGLFailure = false;
      canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
      resetPictureToImageSurface();

      canvasKit['MakeImage'] = _jsThrow('MakeImage failed');
      expect(() => picture.toImageSync(4, 4), _throwsStateError('MakeImage failed'));
      await expectLater(picture.toImage(4, 4), _throwsStateError('MakeImage failed'));

      // Dart errors are not wrapped.
      JSAny? throwArgumentError(JSAny? info, JSAny? pixels, JSAny? rowBytes) =>
          throw ArgumentError('invalid row bytes');
      canvasKit['MakeImage'] = throwArgumentError.toJS;
      expect(() => picture.toImageSync(4, 4), throwsArgumentError);

      canvasKit['MakeImage'] = originalMakeImage;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
    });

    test('throws an unwrapped Exception for invalid dimensions', () {
      final ui.Picture picture = _createSolidGreenPicture();
      for (final (int width, int height) in const <(int, int)>[(0, 0), (-1, 10)]) {
        expect(
          () => picture.toImageSync(width, height),
          throwsA(
            allOf(
              isA<Exception>(),
              isNot(isA<Error>()),
              predicate((Object e) => e.toString().contains('Invalid image dimensions.')),
            ),
          ),
          reason: '${width}x$height',
        );
      }
    });

    test('deletes the snapshot when readPixels throws', () {
      final ui.Picture picture = _createSolidGreenPicture();
      // Warm up so the next 4x4 call reuses the same SkSurface.
      picture.toImageSync(4, 4).dispose();

      final SkSurface skiaSurface = CanvasKitRenderer.instance.pictureToImageSurface.skSurface!;
      final originalMakeImageSnapshot = skiaSurface['makeImageSnapshot']! as JSFunction;
      addTearDown(() => skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot);

      SkImage? snapshot;
      SkImage spyMakeImageSnapshot() {
        final image = originalMakeImageSnapshot.callAsFunction(skiaSurface)! as SkImage;
        image['readPixels'] = _jsThrow('readPixels failed');
        return snapshot = image;
      }

      skiaSurface['makeImageSnapshot'] = spyMakeImageSnapshot.toJS;

      expect(() => picture.toImageSync(4, 4), _throwsStateError('readPixels failed'));
      expect(snapshot!.isDeleted(), isTrue);
    });

    test('deletes the raster image when reading its size throws', () {
      final ui.Picture picture = _createSolidGreenPicture();

      SkImage? rasterImage;
      SkImage? spyMakeImage(JSAny? info, JSAny? pixels, JSNumber rowBytes) {
        final image =
            (originalMakeImage! as JSFunction).callAsFunction(canvasKit, info, pixels, rowBytes)!
                as SkImage;
        image['width'] = _jsThrow('corrupt SkImage width');
        return rasterImage = image;
      }

      canvasKit['MakeImage'] = spyMakeImage.toJS;

      expect(() => picture.toImageSync(4, 4), _throwsStateError('corrupt SkImage width'));
      expect(rasterImage!.isDeleted(), isTrue);
    });
  });
}

const String _canvasNotFoundMessage = 'Canvas with id [object OffscreenCanvas] was not found';

Matcher _throwsStateError(String detail) {
  return throwsA(
    isA<StateError>().having((StateError error) => error.message, 'message', contains(detail)),
  );
}

JSFunction _jsThrow(String message) {
  return globalContext.callMethod<JSFunction>('Function'.toJS, 'throw "$message";'.toJS);
}

ui.Picture _createSolidGreenPicture() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawPaint(ui.Paint()..color = const ui.Color(0xFF00FF00));
  final ui.Picture picture = recorder.endRecording();
  addTearDown(() {
    if (!(picture as CkPicture).isDisposed) {
      picture.dispose();
    }
  });
  return picture;
}

Future<void> _expectSolidGreenImage(
  ui.Image image, {
  required int width,
  required int height,
}) async {
  addTearDown(image.dispose);
  expect((image.width, image.height), (width, height));
  final ByteData byteData = (await image.toByteData())!;
  final Uint8List rgba = byteData.buffer.asUint8List();
  for (var offset = 0; offset < rgba.length; offset += 4) {
    expect(rgba.sublist(offset, offset + 4), <int>[0, 255, 0, 255]);
  }
}
