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
      canvasKit['MakeSWCanvasSurface'] = _jsThrowStringFunction(_canvasNotFoundMessage);
      resetPictureToImageSurface();

      expect(() => picture.toImageSync(1, 1), _throwsStateError(contains(_canvasNotFoundMessage)));

      // Restore surface creation and verify bare JS throws inside toImageSync
      // itself are wrapped in a Dart StateError rather than leaking out raw.
      canvasKit['MakeSWCanvasSurface'] = originalMakeSWCanvasSurface;
      CkSurface.debugForceGLFailure = false;
      resetPictureToImageSurface();

      canvasKit['MakeImage'] = _jsThrowStringFunction(_canvasNotFoundMessage);

      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(
          allOf(contains('Failed to render picture to image:'), contains(_canvasNotFoundMessage)),
        ),
      );

      await expectLater(
        picture.toImage(4, 4),
        _throwsStateError(contains('Failed to render picture to image:')),
      );

      canvasKit['MakeImage'] = _jsThrowExpressionFunction('({code: 500})');
      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(contains('Failed to render picture to image:')),
      );
    });

    test('recovers after a transient failure on fresh surface', () async {
      final ui.Picture picture = _createSolidGreenPicture();

      CkSurface.debugForceGLFailure = true;
      canvasKit['MakeSWCanvasSurface'] = _jsThrowStringFunction(_canvasNotFoundMessage);
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
        _throwsStateError(
          allOf(
            contains('Failed to render picture to image:'),
            contains('Transient MakeImage failure'),
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

        await expectLater(
          picture.toImage(width, height),
          throwsA(
            isA<Exception>().having(
              (Exception error) => error.toString(),
              'toString()',
              contains('Invalid image dimensions.'),
            ),
          ),
        );
      }

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

      expect(() => picture.toImageSync(4, 4), _throwsStateError('readPixels aborted'));
      expect(deleteCallCount, 1);
      expect(capturedSnapshot!.isDeleted(), isTrue);

      // 3. Null return from readPixels deletes snapshot exactly once before throwing StateError.
      deleteCallCount = 0;
      capturedSnapshot = null;
      JSAny? returnNullPixels(JSAny? srcX, JSAny? srcY, JSAny? info) => null;
      currentReadPixelsOverride = returnNullPixels.toJS;

      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError('Unable to convert read pixels from SkImage.'),
      );
      expect(deleteCallCount, 1);
      expect(capturedSnapshot!.isDeleted(), isTrue);

      skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
    });

    test(
      'wraps null snapshots, null MakeImage returns, and unprintable or primitive JS throws',
      () async {
        final ui.Picture picture = _createSolidGreenPicture();
        picture.toImageSync(4, 4).dispose();

        final SkSurface skiaSurface = CanvasKitRenderer.instance.pictureToImageSurface.skSurface!;
        final JSAny? originalMakeImageSnapshot = skiaSurface['makeImageSnapshot'];
        addTearDown(() => skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot);

        JSAny? returnNullSnapshot() => null;
        skiaSurface['makeImageSnapshot'] = returnNullSnapshot.toJS;
        expect(
          () => picture.toImageSync(4, 4),
          _throwsStateError('Unable to create image snapshot from SkSurface.'),
        );
        await expectLater(
          picture.toImage(4, 4),
          _throwsStateError('Unable to create image snapshot from SkSurface.'),
        );
        skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;

        JSAny? returnNullRasterImage(JSAny? a, JSAny? b, JSAny? c) => null;
        canvasKit['MakeImage'] = returnNullRasterImage.toJS;
        expect(
          () => picture.toImageSync(4, 4),
          _throwsStateError('Unable to convert image pixels into SkImage.'),
        );

        const exoticJsThrows = <(String, String)>[
          ('Object.create(null)', '<unprintable JavaScript error>'),
          ('({toString() { throw "unprintable"; }})', '<unprintable JavaScript error>'),
          ('42', '42'),
          ('false', 'false'),
          ('new Error("Embind BindingError")', 'Embind BindingError'),
        ];
        for (final (String jsExpr, String expectedDetail) in exoticJsThrows) {
          canvasKit['MakeImage'] = _jsThrowExpressionFunction(jsExpr);
          expect(
            () => picture.toImageSync(4, 4),
            _throwsStateError(
              allOf(contains('Failed to render picture to image:'), contains(expectedDetail)),
            ),
            reason: 'Expected wrapped StateError for JS throw: $jsExpr',
          );
        }

        for (final jsNullish in const <String>['null', 'undefined']) {
          canvasKit['MakeImage'] = _jsThrowExpressionFunction(jsNullish);
          expect(
            () => picture.toImageSync(4, 4),
            throwsA(
              allOf(
                anyOf(isA<Error>(), isA<Exception>()),
                predicate((Object? e) => e.toString().contains('Throw of null')),
              ),
            ),
          );
        }

        canvasKit['MakeImage'] = originalMakeImage;
        await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
      },
    );

    test('preserves primary readPixels failure when snapshot delete throws and wraps standalone delete throws', () async {
      final ui.Picture picture = _createSolidGreenPicture();
      picture.toImageSync(4, 4).dispose();

      final SkSurface skiaSurface = CanvasKitRenderer.instance.pictureToImageSurface.skSurface!;
      final originalMakeImageSnapshot = skiaSurface['makeImageSnapshot']! as JSFunction;
      final snapshotsToCleanUp = <(SkImage, JSFunction)>[];
      var deleteCallCount = 0;
      var makeImageCalled = false;
      JSFunction? currentReadPixelsOverride;
      late JSFunction currentDeleteBehavior;

      addTearDown(() {
        skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;
        for (final (SkImage snapshot, JSFunction originalDelete) in snapshotsToCleanUp) {
          if (!snapshot.isDeleted()) {
            originalDelete.callAsFunction(snapshot);
          }
        }
      });

      skiaSurface['makeImageSnapshot'] = (() {
        final snapshot = originalMakeImageSnapshot.callAsFunction(skiaSurface)! as SkImage;
        final originalDelete = snapshot['delete']! as JSFunction;
        snapshotsToCleanUp.add((snapshot, originalDelete));
        snapshot['delete'] = (() {
          deleteCallCount++;
          originalDelete.callAsFunction(snapshot);
          currentDeleteBehavior.callAsFunction();
        }).toJS;
        if (currentReadPixelsOverride != null) {
          snapshot['readPixels'] = currentReadPixelsOverride;
        }
        return snapshot;
      }).toJS;

      currentDeleteBehavior = _jsThrowStringFunction('secondary snapshot delete failure');
      currentReadPixelsOverride = _jsThrowStringFunction('primary readPixels failure');
      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(
          allOf(
            contains('primary readPixels failure'),
            isNot(contains('secondary snapshot delete failure')),
          ),
        ),
      );
      expect(deleteCallCount, 1);

      deleteCallCount = 0;
      JSAny? throwPrimaryArgumentError(JSAny? x, JSAny? y, JSAny? info) =>
          throw ArgumentError('primary dart readPixels error');
      currentReadPixelsOverride = throwPrimaryArgumentError.toJS;
      expect(
        () => picture.toImageSync(4, 4),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            'primary dart readPixels error',
          ),
        ),
      );
      expect(deleteCallCount, 1);

      deleteCallCount = 0;
      currentReadPixelsOverride = null;
      currentDeleteBehavior = _jsThrowStringFunction('standalone snapshot delete failure');
      canvasKit['MakeImage'] = ((JSAny? info, JSAny? pixels, JSNumber rowBytes) {
        makeImageCalled = true;
        return (originalMakeImage! as JSFunction).callAsFunction(canvasKit, info, pixels, rowBytes);
      }).toJS;
      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(
          allOf(
            contains('Failed to render picture to image:'),
            contains('standalone snapshot delete failure'),
          ),
        ),
      );
      expect(deleteCallCount, 1);
      expect(makeImageCalled, isFalse);

      skiaSurface['makeImageSnapshot'] = originalMakeImageSnapshot;
      canvasKit['MakeImage'] = originalMakeImage;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
    });

    test('deletes rasterImage handle when width or height throws after MakeImage', () async {
      final ui.Picture picture = _createSolidGreenPicture();
      final imagesToCleanUp = <(SkImage, JSFunction)>[];
      addTearDown(() {
        for (final (SkImage img, JSFunction originalDelete) in imagesToCleanUp) {
          if (!img.isDeleted()) {
            originalDelete.callAsFunction(img);
          }
        }
      });

      SkImage? capturedRasterImage;
      var rasterDeleteCount = 0;
      JSFunction? widthOverride;
      JSFunction? heightOverride;
      JSFunction? afterRasterDelete;

      canvasKit['MakeImage'] = ((JSAny? info, JSAny? pixels, JSNumber rowBytes) {
        final raster =
            (originalMakeImage! as JSFunction).callAsFunction(canvasKit, info, pixels, rowBytes)!
                as SkImage;
        final originalDelete = raster['delete']! as JSFunction;
        imagesToCleanUp.add((raster, originalDelete));
        capturedRasterImage = raster;
        raster['delete'] = (() {
          rasterDeleteCount++;
          originalDelete.callAsFunction(raster);
          afterRasterDelete?.callAsFunction();
        }).toJS;
        if (widthOverride != null) {
          raster['width'] = widthOverride;
        }
        if (heightOverride != null) {
          raster['height'] = heightOverride;
        }
        return raster;
      }).toJS;

      widthOverride = _jsThrowStringFunction('corrupt SkImage width');
      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(
          allOf(contains('Failed to render picture to image:'), contains('corrupt SkImage width')),
        ),
      );
      expect(rasterDeleteCount, 1);
      expect(capturedRasterImage!.isDeleted(), isTrue);

      rasterDeleteCount = 0;
      capturedRasterImage = null;
      widthOverride = null;
      heightOverride = _jsThrowStringFunction('corrupt SkImage height');
      afterRasterDelete = _jsThrowStringFunction('secondary raster delete failure');
      expect(
        () => picture.toImageSync(4, 4),
        _throwsStateError(
          allOf(
            contains('corrupt SkImage height'),
            isNot(contains('secondary raster delete failure')),
          ),
        ),
      );
      expect(rasterDeleteCount, 1);
      expect(capturedRasterImage!.isDeleted(), isTrue);

      canvasKit['MakeImage'] = originalMakeImage;
      await _expectSolidGreenImage(picture.toImageSync(4, 4), width: 4, height: 4);
    });

    test(
      'rejects disposed pictures while keeping prior images and cloned pictures renderable',
      () async {
        final ui.Picture original = _createSolidGreenPicture();
        final LayerPicture cloned = (original as CkPicture).clone();
        addTearDown(() {
          if (!cloned.isDisposed) {
            cloned.dispose();
          }
        });

        final ui.Image priorImage = original.toImageSync(4, 4);
        original.dispose();

        expect(
          () => original.toImageSync(4, 4),
          _throwsStateError(contains('Cannot convert picture to image.')),
        );
        await expectLater(
          original.toImage(4, 4),
          _throwsStateError(contains('Cannot convert picture to image.')),
        );
        expect(() => original.dispose(), _throwsStateError(contains('Cannot dispose picture.')));

        await _expectSolidGreenImage(priorImage, width: 4, height: 4);
        await _expectSolidGreenImage(cloned.toImageSync(4, 4), width: 4, height: 4);
        await _expectSolidGreenImage(await cloned.toImage(4, 4), width: 4, height: 4);

        cloned.dispose();
        expect(
          () => cloned.toImageSync(4, 4),
          _throwsStateError(contains('Cannot convert picture to image.')),
        );
      },
    );

    test(
      'isolates shared pictureToImageSurface across interleaved toImage calls and non-square sizes',
      () async {
        final magentaRecorder = ui.PictureRecorder();
        ui.Canvas(magentaRecorder).drawPaint(ui.Paint()..color = const ui.Color(0xFFFF00FF));
        final ui.Picture opaqueMagenta = magentaRecorder.endRecording();
        addTearDown(opaqueMagenta.dispose);

        final halfCyanRecorder = ui.PictureRecorder();
        ui.Canvas(halfCyanRecorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 3, 4),
          ui.Paint()..color = const ui.Color(0xFF00FFFF),
        );
        final ui.Picture leftHalfCyan = halfCyanRecorder.endRecording();
        addTearDown(leftHalfCyan.dispose);

        final ui.Picture solidGreen = _createSolidGreenPicture();
        final JSFunction throwTransient = _jsThrowStringFunction('interleaved MakeImage failure');
        var makeImageCallIndex = 0;
        canvasKit['MakeImage'] = ((JSAny? info, JSAny? pixels, JSNumber rowBytes) {
          if (++makeImageCallIndex == 3) {
            return throwTransient.callAsFunction();
          }
          return (originalMakeImage! as JSFunction).callAsFunction(
            canvasKit,
            info,
            pixels,
            rowBytes,
          );
        }).toJS;

        Future<Object> captureOutcome(Future<ui.Image> future) async {
          try {
            return await future;
          } catch (error) {
            return error;
          }
        }

        final List<Object> outcomes = await Future.wait<Object>(<Future<Object>>[
          captureOutcome(opaqueMagenta.toImage(7, 3)),
          captureOutcome(opaqueMagenta.toImage(6, 4)),
          captureOutcome(leftHalfCyan.toImage(0, 4)),
          captureOutcome(leftHalfCyan.toImage(6, 4)),
          captureOutcome(leftHalfCyan.toImage(6, 4)),
          captureOutcome(solidGreen.toImage(3, 5)),
        ]);

        final magenta7x3 = outcomes[0] as ui.Image;
        final magenta6x4 = outcomes[1] as ui.Image;
        addTearDown(magenta7x3.dispose);
        addTearDown(magenta6x4.dispose);
        expect((magenta7x3.width, magenta7x3.height), (7, 3));
        expect((magenta6x4.width, magenta6x4.height), (6, 4));
        final Uint8List magentaRgba = (await magenta7x3.toByteData())!.buffer.asUint8List();
        expect(magentaRgba.length, 7 * 3 * 4);
        for (var i = 0; i < magentaRgba.length; i += 4) {
          expect(magentaRgba.sublist(i, i + 4), <int>[255, 0, 255, 255]);
        }

        expect(outcomes[2], isA<Exception>());
        expect(outcomes[2].toString(), contains('Invalid image dimensions.'));
        expect(
          outcomes[3],
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('interleaved MakeImage failure'),
          ),
        );

        final halfCyanImage = outcomes[4] as ui.Image;
        addTearDown(halfCyanImage.dispose);
        expect((halfCyanImage.width, halfCyanImage.height), (6, 4));
        final Uint8List cyanRgba = (await halfCyanImage.toByteData())!.buffer.asUint8List();
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 6; x++) {
            final int offset = (y * 6 + x) * 4;
            final expected = x < 3 ? <int>[0, 255, 255, 255] : <int>[0, 0, 0, 0];
            expect(cyanRgba.sublist(offset, offset + 4), expected, reason: 'pixel ($x, $y)');
          }
        }

        await _expectSolidGreenImage(outcomes[5] as ui.Image, width: 3, height: 5);
      },
    );
  });
}

const String _canvasNotFoundMessage = 'Canvas with id [object OffscreenCanvas] was not found';

Matcher _throwsStateError(Object messageMatcher) {
  return throwsA(
    isA<StateError>().having((StateError error) => error.message, 'message', messageMatcher),
  );
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
