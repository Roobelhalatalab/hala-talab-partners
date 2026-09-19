import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../core/build_config.dart';

/// Embedded Mapbox preview on Android/iOS, with a static Mapbox preview on desktop/web.
/// This keeps the same location visible on Windows while mobile retains the interactive map.
class MapboxLocationPreview extends StatelessWidget {
  const MapboxLocationPreview({
    required this.latitude,
    required this.longitude,
    required this.emptyText,
    required this.missingTokenText,
    this.unsupportedText,
    super.key,
    this.height = 220,
    this.zoom = 14,
  });

  final double? latitude;
  final double? longitude;
  final String emptyText;
  final String missingTokenText;
  final String? unsupportedText;
  final double height;
  final double zoom;

  static const _accessToken = BuildConfig.mapboxAccessToken;

  bool get _isMobileMapbox => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final lat = latitude;
    final lng = longitude;
    if (_accessToken.isEmpty) {
      return _MessagePreview(
        height: height,
        icon: Icons.key_off_outlined,
        text: missingTokenText,
      );
    }
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return _MessagePreview(
        height: height,
        icon: Icons.location_off_outlined,
        text: emptyText,
      );
    }

    if (!_isMobileMapbox) {
      return _MessagePreview(
        height: height,
        icon: Icons.map_outlined,
        text: unsupportedText ?? emptyText,
      );
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: ValueKey('mapbox-$lat-$lng'),
              viewport: CameraViewportState(
                center: Point(coordinates: Position(lng, lat)),
                zoom: zoom,
              ),
              styleUri: MapboxStyles.STANDARD,
              onMapCreated: (map) async {
                await map.compass.updateSettings(CompassSettings(enabled: true));
                await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
                try {
                  await map.location.updateSettings(LocationComponentSettings(enabled: true, puckBearingEnabled: true));
                } catch (_) {}
              },
            ),
            const IgnorePointer(
              child: Center(
                child: Icon(Icons.location_pin, color: Color(0xFFF26B38), size: 42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePreview extends StatelessWidget {
  const _MessagePreview({required this.height, required this.icon, required this.text});

  final double height;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: const Color(0xFF7B8494)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF667085), height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Driver trip overview with three map points when available:
/// driver (blue), store (orange) and customer (green).
/// Uses Mapbox Static Images so the same overview is reliable on Android/iOS/desktop;
/// turn-by-turn navigation remains delegated to the device Maps app.
class MapboxDriverTripPreview extends StatelessWidget {
  const MapboxDriverTripPreview({
    required this.driverLatitude,
    required this.driverLongitude,
    required this.storeLatitude,
    required this.storeLongitude,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.emptyText,
    required this.missingTokenText,
    super.key,
    this.height = 300,
  });

  final double? driverLatitude;
  final double? driverLongitude;
  final double? storeLatitude;
  final double? storeLongitude;
  final double? customerLatitude;
  final double? customerLongitude;
  final String emptyText;
  final String missingTokenText;
  final double height;

  static const _accessToken = BuildConfig.mapboxAccessToken;

  bool _valid(double? lat, double? lng) =>
      lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  bool get _isMobileMapbox => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (_accessToken.isEmpty) {
      return _MessagePreview(height: height, icon: Icons.map_outlined, text: missingTokenText);
    }

    final overlays = <String>[];
    if (_valid(driverLatitude, driverLongitude)) {
      overlays.add('pin-s+2563eb(${driverLongitude!},${driverLatitude!})');
    }
    if (_valid(storeLatitude, storeLongitude)) {
      overlays.add('pin-s+f26b38(${storeLongitude!},${storeLatitude!})');
    }
    if (_valid(customerLatitude, customerLongitude)) {
      overlays.add('pin-s+16a34a(${customerLongitude!},${customerLatitude!})');
    }
    if (overlays.isEmpty) {
      return _MessagePreview(height: height, icon: Icons.location_off_outlined, text: emptyText);
    }

    // Stage 187: mobile driver home no longer uses the legacy streets-v12
    // static snapshot. Use the same live Mapbox STANDARD map as order details,
    // centered on the current destination. This avoids stale cached snapshots
    // and keeps zoom/pan/current-location behavior consistent.
    if (_isMobileMapbox) {
      final destinationLat = _valid(storeLatitude, storeLongitude)
          ? storeLatitude
          : customerLatitude;
      final destinationLng = _valid(storeLatitude, storeLongitude)
          ? storeLongitude
          : customerLongitude;
      return MapboxLocationPreview(
        latitude: destinationLat,
        longitude: destinationLng,
        height: height,
        zoom: 14.5,
        emptyText: emptyText,
        missingTokenText: missingTokenText,
      );
    }

    final staticUri = Uri.parse(
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/'
      '${overlays.join(',')}/auto/900x520'
      '?padding=64&access_token=${Uri.encodeQueryComponent(_accessToken)}',
    );

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              staticUri.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _MessagePreview(
                height: height,
                icon: Icons.map_outlined,
                text: emptyText,
              ),
            ),
            PositionedDirectional(
              start: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    _TripLegendDot(color: Color(0xFF2563EB), label: 'السائق'),
                    _TripLegendDot(color: Color(0xFFF26B38), label: 'المتجر'),
                    _TripLegendDot(color: Color(0xFF16A34A), label: 'العميل'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripLegendDot extends StatelessWidget {
  const _TripLegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
        ],
      );
}
