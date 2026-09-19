import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens restaurant/customer locations in the platform's external maps app.
///
/// Stage 58 intentionally uses external navigation instead of embedding a map
/// widget. This keeps the partner app light while still giving restaurant staff
/// one-tap access to directions on Windows, Android and iOS.
class MapsService {
  MapsService._();

  static final MapsService instance = MapsService._();

  Uri _coordinatesUri({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    final query = '$latitude,$longitude';
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return Uri.https('maps.apple.com', '/', {
        'll': query,
        if (label != null && label.trim().isNotEmpty) 'q': label.trim(),
      });
    }
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
  }

  Uri _addressUri(String address) {
    final value = address.trim();
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return Uri.https('maps.apple.com', '/', {'q': value});
    }
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': value,
    });
  }

  Uri _directionsCoordinatesUri({
    required double latitude,
    required double longitude,
    bool startNavigation = false,
  }) {
    final destination = '$latitude,$longitude';
    // Google Maps URLs do not require a Maps SDK API key. Omitting
    // dir_action opens the Google Maps route-preview screen; adding
    // dir_action=navigate asks Google Maps to start navigation.
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
      if (startNavigation) 'dir_action': 'navigate',
    });
  }

  Uri _directionsAddressUri(String address, {bool startNavigation = false}) {
    final destination = address.trim();
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
      if (startNavigation) 'dir_action': 'navigate',
    });
  }


  Uri _wazeCoordinatesUri({
    required double latitude,
    required double longitude,
  }) {
    return Uri.https('www.waze.com', '/ul', {
      'll': '$latitude,$longitude',
      'navigate': 'yes',
      'zoom': '18',
    });
  }

  Uri _wazeAddressUri(String address) {
    return Uri.https('www.waze.com', '/ul', {
      'q': address.trim(),
      'navigate': 'yes',
      'zoom': '18',
    });
  }

  /// Opens Waze with the exact saved destination coordinates.
  ///
  /// We deliberately send latitude/longitude (not a searched address) so the
  /// final destination remains the customer's/store's saved point even when
  /// Waze has no mapped street for the last off-road segment. Waze may route
  /// only to the nearest mapped road, but the target itself stays the exact
  /// coordinate supplied by Hala Talab.
  Future<bool> openWazeNavigationCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    final appUri = Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes&zoom=18');
    try {
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return _open(_wazeCoordinatesUri(latitude: latitude, longitude: longitude));
  }

  Future<bool> openWazeNavigationAddress(String address) async {
    final value = address.trim();
    if (value.isEmpty) return false;
    final appUri = Uri.parse('waze://?q=${Uri.encodeComponent(value)}&navigate=yes');
    try {
      if (await canLaunchUrl(appUri)) {
        return await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return _open(_wazeAddressUri(value));
  }

  Future<bool> openCoordinates({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    return _open(_coordinatesUri(
      latitude: latitude,
      longitude: longitude,
      label: label,
    ));
  }

  Future<bool> openDirectionsToCoordinates({
    required double latitude,
    required double longitude,
  }) {
    return _open(_directionsCoordinatesUri(
      latitude: latitude,
      longitude: longitude,
    ));
  }

  Future<bool> openDirectionsToAddress(String address) {
    if (address.trim().isEmpty) return Future.value(false);
    return _open(_directionsAddressUri(address));
  }

  /// Opens Google Maps in route-preview mode (same screen the driver sees
  /// before pressing Start). This uses Google Maps URLs, so it needs no
  /// Google Maps SDK key or Google Cloud billing setup.
  Future<bool> openDriverRoutePreviewCoordinates({
    required double latitude,
    required double longitude,
  }) {
    return _open(_directionsCoordinatesUri(
      latitude: latitude,
      longitude: longitude,
      startNavigation: false,
    ));
  }

  Future<bool> openDriverRoutePreviewAddress(String address) {
    if (address.trim().isEmpty) return Future.value(false);
    return _open(_directionsAddressUri(address, startNavigation: false));
  }

  /// Driver-safe navigation behavior across platforms.
  ///
  /// On Windows/Linux desktops we open the destination as a single map pin.
  /// Desktop browsers can otherwise guess an inaccurate current location and
  /// draw a misleading route. On Android/iOS we keep real turn-by-turn
  /// directions so the device GPS can be used as the route origin.
  Future<bool> openDriverDestinationCoordinates({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (isDesktop) {
      return openCoordinates(
        latitude: latitude,
        longitude: longitude,
        label: label,
      );
    }
    return _open(_directionsCoordinatesUri(
      latitude: latitude,
      longitude: longitude,
      startNavigation: true,
    ));
  }

  Future<bool> openDriverDestinationAddress(String address) {
    if (address.trim().isEmpty) return Future.value(false);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (isDesktop) {
      return openAddress(address);
    }
    return _open(_directionsAddressUri(address, startNavigation: true));
  }

  Future<bool> openAddress(String address) {
    if (address.trim().isEmpty) return Future.value(false);
    return _open(_addressUri(address));
  }

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
