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

  /// Existing callers use this for product/category/store photos. The source
  /// starts fully visible; the merchant can then zoom in/out and pan freely.
  final bool preserveWholeImage;

  @override
  State<PartnerImageCropEditor> createState() => _PartnerImageCropEditorState();
}

class _PartnerImageCropEditorState extends State<PartnerImageCropEditor> {
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transform = TransformationController();

  bool _saving = false;
  Size _viewportSize = Size.zero;

  static const double _minScale = 0.25;
  static const double _maxScale = 8.0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _resetTransform() {
    if (_saving) return;
    _transform.value = Matrix4.identity();
  }

  void _zoomBy(double factor) {
    if (_saving || _viewportSize.isEmpty) return;

    final current = _transform.value;
    final currentScale = current.getMaxScaleOnAxis();
    if (!currentScale.isFinite || currentScale <= 0) return;

    final targetScale =
        (currentScale * factor).clamp(_minScale, _maxScale).toDouble();
    if ((targetScale - currentScale).abs() < 0.0001) return;

    // Preserve the current pan while scaling around the visible frame centre.
    // This avoids the old behaviour where +/- zoom drifted toward the corner.
    final ratio = targetScale / currentScale;
    final translation = current.getTranslation();
    final centerX = _viewportSize.width / 2;
    final centerY = _viewportSize.height / 2;
    final nextX = ratio * translation.x + (1 - ratio) * centerX;
    final nextY = ratio * translation.y + (1 - ratio) * centerY;

    _transform.value = Matrix4.diagonal3Values(targetScale, targetScale, 1)
      ..setTranslationRaw(nextX, nextY, 0);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted && data != null) {
        Navigator.of(context).pop(data.buffer.asUint8List());
      }
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'حفظ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = (constraints.maxWidth - 28).clamp(220.0, 720.0);
            final maxH = (constraints.maxHeight - 112).clamp(220.0, 720.0);

            double width = maxW;
            double height = width / widget.aspectRatio;
            if (height > maxH) {
              height = maxH;
              width = height * widget.aspectRatio;
            }
            _viewportSize = Size(width, height);

            final radius = widget.circularFrame
                ? BorderRadius.circular(width)
                : BorderRadius.circular(18);

            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: width,
                      height: height,
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
                                  minScale: _minScale,
                                  maxScale: _maxScale,
                                  panEnabled: true,
                                  scaleEnabled: true,
                                  boundaryMargin: const EdgeInsets.all(1600),
                                  clipBehavior: Clip.none,
                                  child: SizedBox(
                                    width: width,
                                    height: height,
                                    child: Image.memory(
                                      widget.bytes,
                                      // Always start with the complete image
                                      // visible. The merchant decides how much
                                      // to zoom/crop, on both Android and iOS.
                                      fit: widget.preserveWholeImage
                                          ? BoxFit.contain
                                          : BoxFit.cover,
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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _zoomBy(0.8),
                      icon: const Icon(Icons.remove, color: Colors.white),
                      label: const Text(
                        'إبعاد',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _zoomBy(1.25),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'تقريب',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _resetTransform,
                      icon: const Icon(Icons.restart_alt, color: Colors.white),
                      label: const Text(
                        'إرجاع للحجم الأصلي',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Text(
                    'استخدم إصبعين للتقريب والإبعاد، واسحب الصورة لاختيار الجزء الذي تريد ظهوره.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
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
