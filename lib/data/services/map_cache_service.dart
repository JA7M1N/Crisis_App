import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

/// MapCacheService — provides a NetworkTileProvider for flutter_map.
/// No external caching package needed — uses flutter_map's built-in provider.
/// For true offline tile caching, TileCacheService (tile_cache_service.dart)
/// handles disk-based caching via http + path_provider.

class MapCacheService {
  /// Drop-in TileProvider for TileLayer — uses flutter_map's default
  /// NetworkTileProvider which handles cancellation internally in v7+.
  static TileProvider get tileProvider => NetworkTileProvider();

  /// Pre-cache tiles around user position (stub — real caching is in TileCacheService)
  static Future<void> preCacheArea({
    required double lat,
    required double lng,
    double radiusKm = 5,
  }) async {
    debugPrint('[MapCache] preCacheArea called ($lat, $lng)');
  }
}
