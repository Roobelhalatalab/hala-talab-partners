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
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _centerImage(Size viewport, double imageW, double imageH) {
    if (_lastViewport == viewport) return;
    _lastViewport = viewport;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dx = (viewport.width - imageW) / 2;
      final dy = (viewport.height - imageH) / 2;
      _transform.value = Matrix4.identity()..translateByDouble(dx, dy, 0.0, 1.0);
    });
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
            _centerImage(Size(w, h), imageW, imageH);

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
                                  minScale: 1,
                                  maxScale: 6,
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
