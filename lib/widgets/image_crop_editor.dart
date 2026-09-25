import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class PartnerImageCropEditor extends StatefulWidget {
  const PartnerImageCropEditor({
    super.key,
    required this.bytes,
    required this.aspectRatio,
    required this.title,
    this.circularFrame = false,
    this.preserveWholeImage = false,
  });

  final Uint8List bytes;
  final double aspectRatio;
  final String title;
  final bool circularFrame;

  /// When true, the editor starts with the whole source image visible inside
  /// the target frame. The merchant can still zoom in and reposition it.
  /// This is useful for product/category photos coming from phones in arbitrary
  /// portrait, landscape, or square aspect ratios.
  final bool preserveWholeImage;

  @override
  State<PartnerImageCropEditor> createState() => _PartnerImageCropEditorState();
}

class _PartnerImageCropEditorState extends State<PartnerImageCropEditor> {
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transform = TransformationController();
  bool _saving = false;
  double? _sourceAspectRatio;
  Size? _lastViewport;
  Size? _lastImageSize;

  @override
  void initState() {
    super.initState();
    _readSourceSize();
  }

  Future<void> _readSourceSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final ratio = image.width / image.height;
      image.dispose();
      codec.dispose();
      if (mounted) setState(() => _sourceAspectRatio = ratio);
    } catch (_) {
      if (mounted) setState(() => _sourceAspectRatio = widget.aspectRatio);
    }
  }

  @override
  void didUpdateWidget(covariant PartnerImageCropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.aspectRatio != widget.aspectRatio ||
        oldWidget.preserveWholeImage != widget.preserveWholeImage) {
      _sourceAspectRatio = null;
      _lastViewport = null;
      _lastImageSize = null;
      _transform.value = Matrix4.identity();
      _readSourceSize();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Matrix4 _centeredTransform(
    Size viewport,
    double imageW,
    double imageH, {
    double scale = 1.0,
  }) {
    final dx = (viewport.width - (imageW * scale)) / 2;
    final dy = (viewport.height - (imageH * scale)) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  void _centerImage(Size viewport, double imageW, double imageH) {
    final imageSize = Size(imageW, imageH);
    if (_lastViewport == viewport && _lastImageSize == imageSize) return;
    _lastViewport = viewport;
    _lastImageSize = imageSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transform.value = _centeredTransform(viewport, imageW, imageH);
    });
  }

  void _snapBackToWholeImageIfNeeded(
    Size viewport,
    double imageW,
    double imageH,
    double minScale,
  ) {
    final currentScale = _transform.value.getMaxScaleOnAxis();
    if (currentScale > minScale + 0.04) return;
    _transform.value = _centeredTransform(
      viewport,
      imageW,
      imageH,
      scale: minScale,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      // Upload-friendly output: the old 2.2x capture created unnecessarily large
      // PNG files (up to ~1584 px on a 720 px crop). 1.25x keeps product,
      // category, logo and cover images sharp while cutting transfer/decode cost.
      final image = await boundary.toImage(pixelRatio: 1.25);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted && data != null) Navigator.of(context).pop(data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxW = (c.maxWidth - 28).clamp(220.0, 720.0);
            final maxH = (c.maxHeight - 112).clamp(220.0, 720.0);
            double w = maxW;
            double h = w / widget.aspectRatio;
            if (h > maxH) {
              h = maxH;
              w = h * widget.aspectRatio;
            }

            final sourceAspect = _sourceAspectRatio;
            if (sourceAspect == null) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            // Product/category photos may come from any phone camera ratio.
            // For those flows, start with the *whole* source visible so a tall
            // or very wide photo is never cropped automatically. The merchant
            // can still pinch to zoom and pan if they prefer a tighter crop.
            //
            // Other existing flows (store logo/cover) keep the previous
            // cover-first behavior to avoid changing already-approved UI.
            final cropAspect = w / h;
            final double imageW;
            final double imageH;
            if (widget.preserveWholeImage) {
              if (sourceAspect >= cropAspect) {
                imageW = w;
                imageH = w / sourceAspect;
              } else {
                imageH = h;
                imageW = h * sourceAspect;
              }
            } else {
              if (sourceAspect >= cropAspect) {
                imageH = h;
                imageW = h * sourceAspect;
              } else {
                imageW = w;
                imageH = w / sourceAspect;
              }
            }
            final viewport = Size(w, h);
            _centerImage(viewport, imageW, imageH);

            // Allow the user to always return to a true "whole image" view.
            // Cover-first flows can have one source dimension larger than the
            // frame, so minScale=1 used to create a hard zoom-out stop. The
            // calculated floor only relaxes that stop; it does not change the
            // initial crop, upload format, or saved image quality.
            final fitWholeScale = (w / imageW < h / imageH)
                ? w / imageW
                : h / imageH;
            final minScale = fitWholeScale < 1.0 ? fitWholeScale : 1.0;

            final radius = widget.circularFrame ? BorderRadius.circular(w) : BorderRadius.circular(18);

            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _captureKey,
                            child: ClipRRect(
                              borderRadius: radius,
                              child: ColoredBox(
                                color: Colors.white,
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  constrained: false,
                                  minScale: minScale,
                                  maxScale: 6,
                                  onInteractionEnd: (_) => _snapBackToWholeImageIfNeeded(
                                    viewport,
                                    imageW,
                                    imageH,
                                    minScale,
                                  ),
                                  panEnabled: true,
                                  scaleEnabled: true,
                                  clipBehavior: Clip.none,
                                  boundaryMargin: EdgeInsets.zero,
                                  child: SizedBox(
                                    width: imageW,
                                    height: imageH,
                                    child: Image.memory(
                                      widget.bytes,
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.high,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 3),
                                borderRadius: radius,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Text(
                    widget.preserveWholeImage
                        ? 'الصورة تظهر كاملة أولاً. كبّرها أو حرّكها فقط إذا تريد قصاً أقرب داخل الإطار.'
                        : 'حرّك الصورة وكبّرها أو صغّرها حتى يظهر الجزء المطلوب داخل الإطار.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
