// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ui/src/engine.dart';
import 'package:ui/ui.dart' as ui;

// Only supported in profile/release mode. Allows Flutter to use MSAA but
// removes the ability for disabling AA on Paint objects.
const bool _kUsingMSAA = bool.fromEnvironment('flutter.canvaskit.msaa');

/// The base class for CanvasKit surfaces, containing shared logic for context
/// management and Skia object creation.
abstract class CkSurface extends Surface {
  CkSurface(this._canvasProvider) {
    _canvas = _canvasProvider.acquireCanvas(_currentSize, onContextLost: onContextLost);
    _maybeAttachCanvasToDom();
    _initialize();
  }

  final CanvasProvider _canvasProvider;

  @override
  bool get supportsPngEncoding => true;

  BitmapSize _currentSize = const BitmapSize(1, 1);

  /// The underlying Skia surface object.
  SkSurface? get skSurface => _skSurface;
  SkSurface? _skSurface;

  /// Whether or not WebGl is supported.
  ///
  /// This defaults to true unless `canvasKitForceCpuOnly` is set to true or
  /// `webGLVersion` is -1. If Skia fails to create a GrContext, this will be
  /// set to false.
  @visibleForTesting
  bool get supportsWebGl {
    if (configuration.canvasKitForceCpuOnly) {
      _fallbackToSoftwareReason = 'canvasKitForceCpuOnly is set to true';
      return false;
    }
    if (webGLVersion == -1) {
      _fallbackToSoftwareReason = 'webGLVersion is -1';
      return false;
    }
    if (_failedToCreateGrContext) {
      return false;
    }
    return true;
  }

  /// Whether this surface is using software rendering.
  bool get isSoftware => !supportsWebGl;

  String? _fallbackToSoftwareReason;

  /// When true, the surface will fail to create a GL context and fall back to
  /// software rendering. This is useful for testing.
  @visibleForTesting
  static bool debugForceGLFailure = false;

  bool _failedToCreateGrContext = false;

  static bool _didWarnAboutWebGlInitializationFailure = false;

  /// The underlying GL context. Returns -1 if the context is not initialized.
  @override
  @visibleForTesting
  int get glContext => _glContext;
  int _glContext = -1;

  /// The canvas object that this surface is rendering to.
  @visibleForTesting
  DomEventTarget get canvas => _canvas;
  late DomEventTarget _canvas;

  /// Whether a WebGL context has been requested on the current [canvas].
  ///
  /// A canvas that owns a WebGL context cannot provide a 2D context, so it
  /// cannot back a software [SkSurface]. When this is true and the surface
  /// falls back to software rendering, the canvas is replaced with a fresh one
  /// first.
  bool _canvasIsWebGlTainted = false;

  void _maybeAttachCanvasToDom();

  /// Returns the WebGL context of [canvas].
  ///
  /// Implemented by subclasses, which know the static type of their canvas, so
  /// that no runtime type check is needed (`instanceof OffscreenCanvas` throws
  /// in browsers that do not define `OffscreenCanvas`).
  WebGLContext _webGlContextOf(DomEventTarget canvas);

  /// A [Future] which completes when the [Surface] is initialized and ready to
  /// render pictures.
  @override
  Future<void> get initialized => _initialized.future;
  final Completer<void> _initialized = Completer<void>();

  Completer<void>? _handledContextLostEvent;

  /// Creates the canvas object and initializes the graphics context.
  Future<void> _initialize() async {
    // Complete [initialized] even if no Skia surface could be created, so that
    // callers awaiting it do not hang forever. `setSize` retries creating the
    // surface. See https://github.com/flutter/flutter/issues/162868.
    try {
      _createSkiaObjects();
    } catch (e, s) {
      printWarning('Failed to initialize CanvasKit surface: $e\n$s');
    } finally {
      _initialized.complete();
    }
  }

  /// The underlying Skia graphics context.
  SkGrContext? _grContext;

  /// Handles the context lost event by acquiring a new canvas and recreating
  /// the graphics context.
  ///
  /// [handledContextLossEvent] completes only once the graphics context has
  /// been recreated (or recovery has failed).
  void onContextLost() {
    final DomEventTarget newCanvas = _canvasProvider.acquireCanvas(
      _currentSize,
      onContextLost: onContextLost,
    );
    try {
      _replaceCanvas(newCanvas);
    } catch (e, s) {
      printWarning('Error recovering from context loss: $e\n$s');
    } finally {
      if (_handledContextLostEvent?.isCompleted == false) {
        _handledContextLostEvent!.complete();
      }
    }
  }

  /// Recreates the Skia surface, falling back to software rendering if WebGL
  /// fails.
  ///
  /// Falling back to software rendering may replace [canvas], see
  /// [_recreateSoftwareSkSurface].
  void _recreateSkSurface() {
    if (supportsWebGl) {
      try {
        _recreateWebGlSkSurface();
      } catch (e) {
        _markWebGlFailed('failed to create GrContext. Error: $e');
        _recreateSoftwareSkSurface();
      }
    } else {
      _recreateSoftwareSkSurface();
    }
  }

  /// Permanently switches this surface to software rendering.
  void _markWebGlFailed(String reason) {
    _failedToCreateGrContext = true;
    _fallbackToSoftwareReason = reason;
  }

  /// Creates the GL context and the Skia `GrContext`.
  void _createGrContext() {
    if (debugForceGLFailure) {
      _markWebGlFailed('debugForceGLFailure is true');
      return;
    }
    final options = SkWebGLContextOptions(
      antialias: _kUsingMSAA ? 1 : 0,
      majorVersion: webGLVersion.toDouble(),
    );
    // Mark the canvas before requesting the context so that it is replaced
    // before software rendering even if the request throws part-way. Replacing
    // a canvas whose request failed outright is unnecessary, but harmless.
    _canvasIsWebGlTainted = true;
    _glContext = _getGlContext(options);
    // CanvasKit returns a context handle of 0 if the browser refused to create
    // a WebGL context.
    if (_glContext <= 0) {
      _markWebGlFailed('failed to create WebGL context (id: $_glContext).');
      return;
    }
    _grContext = canvasKit.MakeGrContext(_glContext.toDouble());
    if (_grContext == null) {
      _markWebGlFailed('failed to create GrContext.');
    }
  }

  /// Creates the underlying GL context for the canvas.
  ///
  /// This method is implemented by subclasses to handle their specific
  /// canvas types.
  int _getGlContext(SkWebGLContextOptions options);

  /// Creates the Skia objects that are backed by the canvas.
  ///
  /// This method is responsible for creating the `SkGrContext` and the
  /// `SkSurface`.
  void _createSkiaObjects() {
    try {
      if (supportsWebGl) {
        _createGrContext();
      }
    } catch (e) {
      _markWebGlFailed('failed to create GrContext. Error: $e');
    }
    _recreateSkSurface();
  }

  void _recreateWebGlSkSurface() {
    _skSurface?.dispose();
    // Clear the disposed surface so that it is not disposed again if creating
    // the new one throws.
    _skSurface = null;
    _skSurface = canvasKit.MakeOnScreenGLSurface(
      _grContext!,
      _currentSize.width.toDouble(),
      _currentSize.height.toDouble(),
      SkColorSpaceSRGB,
      0,
      0,
    );
    if (_skSurface == null) {
      throw Exception('Failed to initialize CanvasKit SkSurface.');
    }
  }

  /// Recreates the Skia surface using software rendering.
  ///
  /// If a WebGL context was requested on the current [canvas], the canvas is
  /// first replaced with a fresh one, because a canvas that is bound to WebGL
  /// cannot provide the 2D context that software rendering draws into.
  void _recreateSoftwareSkSurface() {
    if (_canvasIsWebGlTainted) {
      _swapCanvasForSoftwareRendering();
    }
    if (!_didWarnAboutWebGlInitializationFailure) {
      _didWarnAboutWebGlInitializationFailure = true;
      printWarning(
        'WARNING: Falling back to CPU-only rendering. Reason: $_fallbackToSoftwareReason',
      );
    }
    _skSurface?.dispose();
    _skSurface = _createSoftwareSkSurface();
    if (_skSurface == null) {
      throw Exception('Failed to initialize CanvasKit SkSurface.');
    }
  }

  /// Creates an SkSurface for software rendering. This is used when WebGl is not
  /// supported or when it fails to initialize.
  SkSurface _createSoftwareSkSurface();

  /// Replaces the WebGL-tainted [canvas] with a fresh canvas that can provide
  /// the 2D context required for software rendering.
  void _swapCanvasForSoftwareRendering() {
    _releaseCanvas();
    _canvas = _canvasProvider.acquireCanvas(_currentSize, onContextLost: onContextLost);
    _maybeAttachCanvasToDom();
  }

  /// Releases the current [canvas], along with its WebGL context and the Skia
  /// objects backed by it.
  ///
  /// The caller must assign a new [canvas] afterwards.
  void _releaseCanvas() {
    _skSurface?.dispose();
    _skSurface = null;
    try {
      _grContext?.releaseResourcesAndAbandonContext();
      _grContext?.delete();
    } catch (_) {
      // Ignore GrContext deletion errors on inconsistent state.
    }
    _grContext = null;

    final DomEventTarget oldCanvas = _canvas;
    // Releasing the canvas removes it from the DOM and unregisters its
    // `webglcontextlost` listener. This must happen before the WebGL context
    // is lost below, so that losing it does not trigger another recovery.
    _canvasProvider.releaseCanvas(oldCanvas);
    // Only lose a context that was actually created: requesting the context
    // of a canvas whose request failed could create a new one, which counts
    // against the browser's limit of active WebGL contexts.
    if (_glContext > 0) {
      _destroyGlContext(oldCanvas);
    }
    _glContext = -1;
    _canvasIsWebGlTainted = false;
  }

  /// Frees the WebGL context of [oldCanvas], unless it is already lost.
  void _destroyGlContext(DomEventTarget oldCanvas) {
    try {
      final WebGLContext gl = _webGlContextOf(oldCanvas);
      if (!gl.isContextLost()) {
        gl.loseContextExtension.loseContext();
      }
    } catch (_) {
      // The context may already be unusable; there is nothing left to free.
    }
  }

  double _currentDevicePixelRatio = -1;

  @override
  void setSize(BitmapSize size) {
    final double devicePixelRatio = EngineFlutterDisplay.instance.devicePixelRatio;
    if (_skSurface != null &&
        _currentSize == size &&
        devicePixelRatio == _currentDevicePixelRatio) {
      return;
    }
    _currentDevicePixelRatio = devicePixelRatio;
    _currentSize = size;
    _resizeCanvas(size);
  }

  /// Resizes the underlying canvas to [size] and recreates the Skia surface.
  ///
  /// Subclasses may override this if their underlying canvas type requires
  /// re-allocation or context recreation instead of in-place dimension updates.
  void _resizeCanvas(BitmapSize size) {
    _canvasProvider.resizeCanvas(canvas, size);
    _recreateSkSurface();
  }

  /// Replaces the current canvas with [newCanvas] and recreates the graphics
  /// context on it.
  ///
  /// The old canvas, its WebGL context and the Skia objects backed by it are
  /// released.
  @override
  Future<void> recreateContextForCanvas(DomEventTarget newCanvas) async {
    _replaceCanvas(newCanvas);
  }

  /// Synchronous implementation of [recreateContextForCanvas], for callers
  /// that inspect the surface state right after the canvas is replaced.
  void _replaceCanvas(DomEventTarget newCanvas) {
    _releaseCanvas();
    _canvas = newCanvas;
    _maybeAttachCanvasToDom();
    _createSkiaObjects();
  }

  @override
  void dispose() {
    _skSurface?.dispose();
    _skSurface = null;
  }

  @override
  void setSkiaResourceCacheMaxBytes(int bytes) {
    _grContext?.setResourceCacheLimitBytes(bytes.toDouble());
  }

  @override
  Future<ByteData?> rasterizeImage(ui.Image image, ui.ImageByteFormat format) async {
    await _initialized.future;

    final EngineImage engineImage;
    final SkImage skImage;
    if (image case EngineImage(backendImage: CkImageDelegate(skImage: final imageRef))) {
      engineImage = image;
      skImage = imageRef;
    } else {
      throw ArgumentError('The image being rasterized must be a CanvasKit image.');
    }

    final SkAlphaType alphaType = format == ui.ImageByteFormat.rawStraightRgba
        ? canvasKit.AlphaType.Unpremul
        : canvasKit.AlphaType.Premul;

    Uint8List? bytes;
    if (format == ui.ImageByteFormat.rawRgba || format == ui.ImageByteFormat.rawStraightRgba) {
      final imageInfo = SkImageInfo(
        alphaType: alphaType,
        colorType: canvasKit.ColorType.RGBA_8888,
        colorSpace: SkColorSpaceSRGB,
        width: skImage.width(),
        height: skImage.height(),
      );
      bytes = skImage.readPixels(0, 0, imageInfo);
    } else {
      bytes = skImage.encodeToBytes(); // defaults to PNG 100%
    }

    if (bytes != null) {
      return bytes.buffer.asByteData();
    }

    setSize(BitmapSize(engineImage.width, engineImage.height));
    final SkSurface skSurface = _skSurface!;
    final canvas = CkCanvas.fromSkCanvas(skSurface.getCanvas());

    canvas.clear(const ui.Color(0x00000000));
    final paint = CkPaint();

    canvas.drawImage(engineImage, ui.Offset.zero, paint);
    final SkImage snapshot = skSurface.makeImageSnapshot();

    try {
      if (format == ui.ImageByteFormat.rawRgba || format == ui.ImageByteFormat.rawStraightRgba) {
        final imageInfo = SkImageInfo(
          alphaType: alphaType,
          colorType: canvasKit.ColorType.RGBA_8888,
          colorSpace: SkColorSpaceSRGB,
          width: engineImage.width.toDouble(),
          height: engineImage.height.toDouble(),
        );
        bytes = snapshot.readPixels(0, 0, imageInfo);
      } else {
        bytes = snapshot.encodeToBytes();
      }
    } finally {
      snapshot.delete();
    }

    return bytes?.buffer.asByteData();
  }

  @override
  DomCanvasImageSource get canvasImageSource => canvas as DomCanvasImageSource;

  @override
  Future<void> rasterizeToCanvas(ui.Picture picture) async {
    await _initialized.future;
    final canvas = CkCanvas.fromSkCanvas(_skSurface!.getCanvas());
    final ckPicture = picture as CkPicture;
    canvas.clear(const ui.Color(0x00000000));
    canvas.drawPicture(ckPicture);
    _skSurface!.flush();
  }

  @override
  Future<void> triggerContextLoss() async {
    _handledContextLostEvent = Completer<void>();
    _webGlContextOf(canvas).loseContextExtension.loseContext();
  }

  @override
  Future<void> get handledContextLossEvent => _handledContextLostEvent!.future;
}

/// The CanvasKit implementation of [OffscreenSurface].
class CkOffscreenSurface extends CkSurface implements OffscreenSurface {
  CkOffscreenSurface(OffscreenCanvasProvider super.canvasProvider);

  @override
  int _getGlContext(SkWebGLContextOptions options) {
    return canvasKit.GetOffscreenWebGLContext(canvas as DomOffscreenCanvas, options).toInt();
  }

  @override
  SkSurface _createSoftwareSkSurface() {
    return canvasKit.MakeOffscreenSWCanvasSurface(canvas as DomOffscreenCanvas);
  }

  @override
  Future<List<DomImageBitmap>> rasterizeToImageBitmaps(List<ui.Picture> pictures) async {
    await _initialized.future;
    final bitmaps = <DomImageBitmap>[];
    for (final picture in pictures) {
      await rasterizeToCanvas(picture);
      bitmaps.add(await createImageBitmap(_canvas));
    }
    return bitmaps;
  }

  @override
  void _maybeAttachCanvasToDom() {
    // Do not attach the OffscreenCanvas to the DOM.
  }

  @override
  WebGLContext _webGlContextOf(DomEventTarget canvas) =>
      (canvas as DomOffscreenCanvas).getGlContext(webGLVersion);

  /// Resizes the offscreen canvas to [size], preserving fast in-place resizing
  /// unless the browser's physical WebGL drawing buffer is clamped.
  ///
  /// For standard sizes, modifying `canvas.width` and `canvas.height` in-place
  /// updates the drawing buffer without recreating the WebGL context or
  /// churning GPU resources.
  ///
  /// However, when resizing an active context to very large dimensions
  /// (e.g. 4960x7016, see https://github.com/flutter/flutter/issues/182476),
  /// Chromium's `DrawingBuffer::Resize` may clamp `gl.drawingBufferWidth` or
  /// `gl.drawingBufferHeight` down to fit within its GPU memory budget (WebGL
  /// Spec Section 2.2).
  ///
  /// When a drawing buffer clamp is detected, we acquire a brand-new
  /// [DomOffscreenCanvas] and recreate the WebGL context, allowing the browser
  /// to allocate the full buffer upfront. If even the fresh canvas is clamped
  /// (i.e. requested dimensions exceed hardware/driver limits), an
  /// [UnsupportedError] is thrown rather than silently returning an image with
  /// transparent unbacked pixels.
  @override
  void _resizeCanvas(BitmapSize size) {
    if (!supportsWebGl) {
      _canvasProvider.resizeCanvas(canvas, size);
      _recreateSkSurface();
      return;
    }

    _canvasProvider.resizeCanvas(canvas, size);
    final WebGLContext gl = (canvas as DomOffscreenCanvas).getGlContext(webGLVersion);

    if (gl.drawingBufferWidth >= size.width && gl.drawingBufferHeight >= size.height) {
      _recreateSkSurface();
      return;
    }

    final DomEventTarget newCanvas = _canvasProvider.acquireCanvas(
      size,
      onContextLost: onContextLost,
    );
    // Releases the old canvas.
    _replaceCanvas(newCanvas);
    // If WebGL failed on the fresh canvas, the surface has fallen back to
    // software rendering; do not re-taint the canvas by requesting a WebGL
    // context on it.
    if (!supportsWebGl) {
      return;
    }

    final WebGLContext freshGl = (canvas as DomOffscreenCanvas).getGlContext(webGLVersion);
    if (freshGl.drawingBufferWidth < size.width || freshGl.drawingBufferHeight < size.height) {
      throw UnsupportedError(
        'Requested image size (${size.width}x${size.height}) exceeds browser WebGL capabilities. '
        'The physical drawing buffer was clamped to (${freshGl.drawingBufferWidth}x${freshGl.drawingBufferHeight}).',
      );
    }
  }
}

/// The CanvasKit implementation of [OnscreenSurface].
class CkOnscreenSurface extends CkSurface implements OnscreenSurface {
  CkOnscreenSurface(OnscreenCanvasProvider super.canvasProvider);

  @override
  int _getGlContext(SkWebGLContextOptions options) {
    return canvasKit.GetWebGLContext(canvas as DomHTMLCanvasElement, options).toInt();
  }

  @override
  SkSurface _createSoftwareSkSurface() {
    return canvasKit.MakeSWCanvasSurface(canvas as DomHTMLCanvasElement);
  }

  final DomElement _hostElement = createDomElement('flt-canvas-container');

  @override
  DomElement get hostElement => _hostElement;

  @override
  void _maybeAttachCanvasToDom() {
    hostElement.appendChild(canvas as DomHTMLCanvasElement);
    _applyOverlayStyle();
  }

  @override
  WebGLContext _webGlContextOf(DomEventTarget canvas) =>
      (canvas as DomHTMLCanvasElement).getGlContext(webGLVersion);

  @override
  bool get isConnected =>
      (canvas as JSAny?).isA<DomHTMLCanvasElement>() &&
      (canvas as DomHTMLCanvasElement).isConnected!;

  @override
  void initialize() {
    // No extra initialization is required.
  }

  /// Whether this surface is used as an overlay, see [setIsOverlay].
  bool _isOverlay = false;

  @override
  void setIsOverlay(bool isOverlay) {
    _isOverlay = isOverlay;
    _applyOverlayStyle();
  }

  /// Applies the overlay positioning to the current [canvas], so that it
  /// survives the canvas being replaced.
  void _applyOverlayStyle() {
    final DomCSSStyleDeclaration style = (canvas as DomHTMLCanvasElement).style;
    if (_isOverlay) {
      if (style.position != 'absolute') {
        style.position = 'absolute';
      }
    } else if (style.position == 'absolute') {
      style.removeProperty('position');
    }
  }
}
