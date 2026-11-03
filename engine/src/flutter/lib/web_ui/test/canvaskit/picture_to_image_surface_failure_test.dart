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

  JSAny? originalMakeOnScreenGLSurface;
  JSAny? originalMakeSWCanvasSurface;
  JSAny? originalMakeImage;

  void resetPictureToImageSurface() {
    try {
      CanvasKitRenderer.instance.pictureToImageSurface.dispose();
    } catch (_) {}
    CanvasKitRenderer.instance.debugResetRasterizer();
  }

  setUp(() {
    originalMakeOnScreenGLSurface = canvasKit['MakeOnScreenGLSurface'];
    originalMakeSWCanvasSurface = canvasKit['MakeSWCanvasSurface'];
    originalMakeImage = canvasKit['MakeImage'];
    CkSurface.debugForceGLFailure = false;
  });

  tearDown(() {
    canvasKit['MakeOnScreenGLSurface'] = originalMakeOnScreenGLSurface;
    canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
    canvasKit['MakeImage'] = originalMakeImage;
    CkSurface.debugForceGLFailure = false;
    resetPictureToImageSurface();
  });

  group('CkPicture.toImageSync surface failure and error handling', () {
    test('throws a Dart Error rather than a bare JS value', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      CkSurface.debugForceGLFailure = true;
      canvasKit['MakeSWCanvasSurface'] = _jsThrowStringFunction(
        'Canvas with id [object OffscreenCanvas] was not found',
      );
      resetPictureToImageSurface();

      Object? surfaceFailureThrown;
      try {
        picture.toImageSync(1, 1);
      } catch (error) {
        surfaceFailureThrown = error;
      }
      expect(surfaceFailureThrown, isA<Error>());
      expect(
        surfaceFailureThrown,
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('Canvas with id [object OffscreenCanvas] was not found'),
        ),
      );

      // Restore surface creation and verify bare JS throws inside toImageSync
      // itself are wrapped in a Dart StateError rather than leaking out raw.
      canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
      CkSurface.debugForceGLFailure = false;
      resetPictureToImageSurface();

      canvasKit['MakeImage'] = _jsThrowStringFunction(
        'Canvas with id [object OffscreenCanvas] was not found',
      );

      Object? makeImageThrown;
      try {
        picture.toImageSync(4, 4);
      } catch (error) {
        makeImageThrown = error;
      }
      expect(makeImageThrown, isA<Error>());
      expect(
        makeImageThrown,
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          allOf(
            contains('Failed to render picture to image:'),
            contains('Canvas with id [object OffscreenCanvas] was not found'),
          ),
        ),
      );

      await expectLater(
        picture.toImage(4, 4),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Failed to render picture to image:'),
          ),
        ),
      );

      canvasKit['MakeImage'] = _jsThrowExpressionFunction('({code: 500})');
      expect(
        () => picture.toImageSync(4, 4),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Failed to render picture to image:'),
          ),
        ),
      );
    });

    test('recovers after a transient failure on fresh surface', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      CkSurface.debugForceGLFailure = true;
      canvasKit['MakeSWCanvasSurface'] = _jsThrowStringFunction(
        'Canvas with id [object OffscreenCanvas] was not found',
      );
      resetPictureToImageSurface();

      expect(() => picture.toImageSync(4, 4), throwsStateError);

      canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);

      // Verify transient bare JS throws during pixel conversion also wrap as
      // StateError and leave pictureToImageSurface usable on the next call.
      final JSFunction throwTransientMakeImage = _jsThrowStringFunction(
        'Transient MakeImage failure',
      );
      var failNextMakeImage = true;
      JSAny? flakyMakeImage(JSAny? info, JSAny? pixels, JSNumber bytesPerRow) {
        if (failNextMakeImage) {
          failNextMakeImage = false;
          return throwTransientMakeImage.callAsFunction();
        }
        return (originalMakeImage! as JSFunction).callAsFunction(
          canvasKit,
          info,
          pixels,
          bytesPerRow,
        );
      }

      canvasKit['MakeImage'] = flakyMakeImage.toJS;

      expect(
        () => picture.toImageSync(6, 6),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(
              contains('Failed to render picture to image:'),
              contains('Transient MakeImage failure'),
            ),
          ),
        ),
      );
      await _expectSolidGreenImage(picture.toImageSync(6, 6), width: 6, height: 6);

      failNextMakeImage = true;
      await expectLater(picture.toImage(6, 6), throwsStateError);
      await _expectSolidGreenImage(await picture.toImage(6, 6), width: 6, height: 6);
    });

    test('preserves intentional Exception and Error types', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      const invalidSizes = <(int, int)>[(0, 0), (-1, 10), (10, 0), (10, -5)];
      for (final (int width, int height) in invalidSizes) {
        Object? thrown;
        try {
          picture.toImageSync(width, height);
        } catch (error) {
          thrown = error;
        }
        expect(thrown, isA<Exception>(), reason: 'Expected Exception for ${width}x$height');
        expect(thrown, isNot(isA<Error>()), reason: 'Must not wrap in Error for ${width}x$height');
        expect(thrown.toString(), contains('Invalid image dimensions.'));
      }

      await expectLater(
        picture.toImage(0, 0),
        throwsA(
          isA<Exception>().having(
            (Exception error) => error.toString(),
            'toString()',
            contains('Invalid image dimensions.'),
          ),
        ),
      );
      await expectLater(
        picture.toImage(-1, 10),
        throwsA(
          isA<Exception>().having(
            (Exception error) => error.toString(),
            'toString()',
            contains('Invalid image dimensions.'),
          ),
        ),
      );

      // Standard Dart Exceptions and Errors thrown inside toImageSync propagate unwrapped.
      JSAny? throwFormatException(JSAny? info, JSAny? pixels, JSAny? rowBytes) =>
          throw const FormatException('invalid pixel format');
      canvasKit['MakeImage'] = throwFormatException.toJS;
      expect(() => picture.toImageSync(4, 4), throwsFormatException);

      JSAny? throwArgumentError(JSAny? info, JSAny? pixels, JSAny? rowBytes) =>
          throw ArgumentError('invalid row bytes');
      canvasKit['MakeImage'] = throwArgumentError.toJS;
      expect(() => picture.toImageSync(4, 4), throwsArgumentError);

      canvasKit['MakeImage'] = originalMakeImage;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);

      final CkSurface surface = CanvasKitRenderer.instance.pictureToImageSurface;
      if (surface is CkOffscreenSurface && surface.supportsWebGl) {
        final WebGLContext gl = (surface.canvas as DomOffscreenCanvas).getGlContext(webGLVersion);
        final int maxTextureSize = gl.getParameter(0x0D33); // GL_MAX_TEXTURE_SIZE
        final int oversized = maxTextureSize + 1000;

        expect(() => picture.toImageSync(oversized, oversized), throwsUnsupportedError);
        await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
      }
    });

    test('deletes skImage snapshot handle when readPixels throws', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      // Warm up pictureToImageSurface at 4x4 so subsequent 4x4 calls reuse skSurface.
      final ui.Image warmup = picture.toImageSync(4, 4);
      warmup.dispose();

      final SkSurface skiaSurface = CanvasKitRenderer.instance.pictureToImageSurface.skSurface!;
      final originalMakeImageSnapshot = skiaSurface['makeImageSnapshot']! as JSFunction;
      final snapshotsToCleanUp = <(SkImage, JSFunction)>[];

      SkImage? capturedSnapshot;
      var deleteCallCount = 0;
      late JSFunction currentReadPixelsOverride;

      addTearDown(() {
        skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;
        for (final (SkImage snapshot, JSFunction originalDelete) in snapshotsToCleanUp) {
          if (!snapshot.isDeleted()) {
            originalDelete.callAsFunction(snapshot);
          }
        }
      });

      JSAny? spyMakeImageSnapshot() {
        final snapshot = originalMakeImageSnapshot.callAsFunction(skiaSurface)! as SkImage;
        final originalDelete = snapshot['delete']! as JSFunction;
        snapshotsToCleanUp.add((snapshot, originalDelete));
        capturedSnapshot = snapshot;

        void wrappedDelete() {
          deleteCallCount++;
          originalDelete.callAsFunction(snapshot);
        }

        snapshot['delete'] = wrappedDelete.toJS;
        snapshot['readPixels'] = currentReadPixelsOverride;
        return snapshot;
      }

      skiaSurface['makeImageSnapshot'] = spyMakeImageSnapshot.toJS;

      // 1. Bare JS string thrown from readPixels deletes snapshot and wraps in StateError.
      currentReadPixelsOverride = _jsThrowStringFunction('wasm readPixels out of bounds');
      Object? jsReadPixelsThrown;
      try {
        picture.toImageSync(4, 4);
      } catch (error) {
        jsReadPixelsThrown = error;
      }
      expect(capturedSnapshot, isNotNull);
      expect(deleteCallCount, 1);
      expect(capturedSnapshot!.isDeleted(), isTrue);
      expect(
        jsReadPixelsThrown,
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          allOf(
            contains('Failed to render picture to image:'),
            contains('wasm readPixels out of bounds'),
          ),
        ),
      );

      // 2. Dart Error thrown from readPixels deletes snapshot and rethrows unwrapped.
      deleteCallCount = 0;
      capturedSnapshot = null;
      JSAny? throwReadPixelsStateError(JSAny? srcX, JSAny? srcY, JSAny? info) =>
          throw StateError('readPixels aborted');
      currentReadPixelsOverride = throwReadPixelsStateError.toJS;

      expect(
        () => picture.toImageSync(4, 4),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'readPixels aborted',
          ),
        ),
      );
      expect(deleteCallCount, 1);
      expect(capturedSnapshot!.isDeleted(), isTrue);

      // 3. Null return from readPixels deletes snapshot exactly once before throwing StateError.
      deleteCallCount = 0;
      capturedSnapshot = null;
      JSAny? returnNullPixels(JSAny? srcX, JSAny? srcY, JSAny? info) => null;
      currentReadPixelsOverride = returnNullPixels.toJS;

      expect(
        () => picture.toImageSync(4, 4),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'Unable to convert read pixels from SkImage.',
          ),
        ),
      );
      expect(deleteCallCount, 1);
      expect(capturedSnapshot!.isDeleted(), isTrue);

      skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
    });
  });
}

JSFunction _jsThrowStringFunction(String message) {
  return _jsThrowExpressionFunction('"$message"');
}

JSFunction _jsThrowExpressionFunction(String expression) {
  return globalContext.callMethod<JSFunction>('Function'.toJS, 'throw $expression;'.toJS);
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
  expect(image.width, width);
  expect(image.height, height);
  final ByteData? byteData = await image.toByteData();
  expect(byteData, isNotNull);
  final Uint8List rgba = byteData!.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  expect(rgba.length, width * height * 4);
  for (var offset = 0; offset < rgba.length; offset += 4) {
    expect(rgba[offset], 0);
    expect(rgba[offset + 1], 255);
    expect(rgba[offset + 2], 0);
    expect(rgba[offset + 3], 255);
  }
}
