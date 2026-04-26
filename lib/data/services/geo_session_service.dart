import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// GeoSessionService — automatically assigns a session ID based on
/// the user's current city/district using reverse geocoding.
///
/// Session ID format: CITY-DISTRICT  e.g. "VADODARA-GUJARAT"
/// All users in the same city auto-join the same session.
/// No typing, no sharing codes — it just works.
///
/// Uses OpenStreetMap Nominatim API (FREE, no API key needed).

class GeoSessionResult {
  final String sessionId;   // e.g. "VADODARA-GUJARAT"
  final String cityName;    // e.g. "Vadodara"
  final String district;    // e.g. "Gujarat"
  final String country;     // e.g. "India"
  final double lat;
  final double lng;

  const GeoSessionResult({
    required this.sessionId,
    required this.cityName,
    required this.district,
    required this.country,
    required this.lat,
    required this.lng,
  });

  /// Human-readable label for UI
  String get displayLabel => '$cityName, $district';
}

class GeoSessionService {
  static final GeoSessionService _instance = GeoSessionService._internal();
  factory GeoSessionService() => _instance;
  GeoSessionService._internal();

  // Cache result so we don't re-geocode on every build
  GeoSessionResult? _cached;

  /// Main entry point — call once on app start.
  /// Returns a GeoSessionResult with auto-detected session ID.
  /// Falls back to 'GLOBAL-CRISIS' if location is unavailable.
  Future<GeoSessionResult> detectSession() async {
    if (_cached != null) return _cached!;

    try {
      // 1. Get GPS position
      final position = await _getPosition();
      if (position == null) return _fallback();

      // 2. Reverse geocode using Nominatim
      final result = await _reverseGeocode(position.latitude, position.longitude);
      _cached = result;
      return result;
    } catch (e) {
      debugPrint('[GeoSession] Error: $e');
      return _fallback();
    }
  }

  Future<Position?> _getPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[GeoSession] Location error: $e');
      return null;
    }
  }

  Future<GeoSessionResult> _reverseGeocode(double lat, double lng) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=$lat&lon=$lng&format=json&addressdetails=1',
    );

    final response = await http.get(url, headers: {
      'User-Agent': 'SankatMitra/1.0 crisis-response-app',
      'Accept-Language': 'en',
    }).timeout(const Duration(seconds: 6));

    if (response.statusCode != 200) return _fallbackWithCoords(lat, lng);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final address = data['address'] as Map<String, dynamic>? ?? {};

    // Extract location parts — Nominatim uses different keys per region
    final city = _firstNonNull([
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
    ]) ?? 'UNKNOWN';

    final district = _firstNonNull([
      address['state'],
      address['state_district'],
      address['region'],
    ]) ?? 'UNKNOWN';

    final country = address['country_code']?.toString().toUpperCase() ?? 'IN';

    // Build session ID: CITY-STATE (uppercase, spaces→hyphens, safe chars only)
    final sessionId = _buildSessionId(city, district);

    debugPrint('[GeoSession] Detected: $city, $district → Session: $sessionId');

    return GeoSessionResult(
      sessionId: sessionId,
      cityName: _toTitleCase(city),
      district: _toTitleCase(district),
      country: country,
      lat: lat,
      lng: lng,
    );
  }

  String _buildSessionId(String city, String district) {
    // Sanitize: uppercase, replace spaces/special chars with hyphens
    String sanitize(String s) => s
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    final c = sanitize(city);
    final d = sanitize(district);

    if (c == 'UNKNOWN' || c.isEmpty) return 'GLOBAL-CRISIS';
    if (d == 'UNKNOWN' || d.isEmpty) return c;
    return '$c-$d';
  }

  String? _firstNonNull(List<dynamic?> values) {
    for (final v in values) {
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  GeoSessionResult _fallback() => const GeoSessionResult(
        sessionId: 'GLOBAL-CRISIS',
        cityName: 'Unknown Location',
        district: 'Global',
        country: 'IN',
        lat: 0,
        lng: 0,
      );

  GeoSessionResult _fallbackWithCoords(double lat, double lng) =>
      GeoSessionResult(
        sessionId: 'GLOBAL-CRISIS',
        cityName: 'Unknown Location',
        district: 'Global',
        country: 'IN',
        lat: lat,
        lng: lng,
      );

  /// Force re-detect (e.g. user moved city)
  void clearCache() => _cached = null;
}
