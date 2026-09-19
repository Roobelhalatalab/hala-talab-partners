import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Lightweight persistent image cache for the partner app.
///
/// Supabase image URLs are immutable because every upload gets a unique path,
/// so caching by URL is safe. The cache lives in the app sandbox temp folder
/// and survives ordinary app restarts on Android/iOS/Windows; the OS may still
/// evict it when storage is tight, in which case the image is downloaded again.
class PersistentNetworkImage extends StatefulWidget {
  const PersistentNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.placeholder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)? errorBuilder;

  @override
  State<PersistentNetworkImage> createState() => _PersistentNetworkImageState();
}

class _PersistentNetworkImageState extends State<PersistentNetworkImage> {
  static final Map<String, Uint8List> _memory = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _inFlight = <String, Future<Uint8List>>{};

  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PersistentNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url.trim();
    if (url.isEmpty) return;

    final memory = _memory[url];
    if (memory != null) {
      if (mounted) setState(() { _bytes = memory; _error = null; });
      return;
    }

    if (mounted) setState(() { _bytes = null; _error = null; });
    try {
      final future = _inFlight.putIfAbsent(url, () => _readOrDownload(url));
      final bytes = await future;
      _inFlight.remove(url);
      _memory[url] = bytes;
      if (mounted && widget.url.trim() == url) setState(() => _bytes = bytes);
    } catch (error, stackTrace) {
      _inFlight.remove(url);
      debugPrint('Persistent image cache failed for $url: $error\n$stackTrace');
      if (mounted && widget.url.trim() == url) setState(() => _error = error);
    }
  }

  static Future<Uint8List> _readOrDownload(String url) async {
    if (kIsWeb) {
      throw UnsupportedError('PersistentNetworkImage disk cache is not used on web');
    }

    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}hala_talab_partner_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${_fnv1a64(url)}.img');

    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      } catch (_) {
        try { await file.delete(); } catch (_) {}
      }
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'image/avif,image/webp,image/*,*/*;q=0.8');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Image HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) throw const FormatException('Downloaded image is empty');
      unawaited(file.writeAsBytes(bytes, flush: false).catchError((_) => file));
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  static String _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, null);
    }
    if (kIsWeb) {
      return Image.network(
        widget.url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: widget.errorBuilder == null
            ? null
            : (context, error, stackTrace) => widget.errorBuilder!(context, error, stackTrace),
      );
    }
    return widget.placeholder ?? const SizedBox.expand();
  }
}
