import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// TileCacheService — caches OSM map tiles to disk for offline use.
///
/// Drop-in usage in FlutterMap TileLayer:
///   tileProvider: CachedTileProvider(),
///
/// pubspec.yaml dependencies needed (already in pubspec):
///   path_provider: ^2.1.4
///   http: ^1.2.2

class TileCacheService {
  static final TileCacheService _instance = TileCacheService._internal();
  factory TileCacheService() => _instance;
  TileCacheService._internal();

  Directory? _cacheDir;
  bool _initialized = false;

  static const int _maxCachedTiles = 2000;

  Future<void> init() async {
    if (_initialized) return;
    final base = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${base.path}/tile_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    _initialized = true;
    debugPrint('[TileCache] Initialized at ${_cacheDir!.path}');
  }

  String _tileKey(String url) {
    return url
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('/', '_')
        .replaceAll('.', '-')
        .replaceAll('?', '_')
        .replaceAll('&', '_');
  }

  File _tileFile(String url) {
    final key = _tileKey(url);
    final safe = key.length > 180 ? key.substring(0, 180) : key;
    return File('${_cacheDir!.path}/$safe.png');
  }

  Future<Uint8List?> getTile(String url) async {
    if (!_initialized) await init();
    final file = _tileFile(url);
    if (await file.exists()) {
      await file.setLastAccessed(DateTime.now());
      return file.readAsBytes();
    }
    return null;
  }

  Future<Uint8List?> fetchAndCache(String url) async {
    // 1. Cache first
    final cached = await getTile(url);
    if (cached != null) return cached;

    // 2. Network fetch
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'SankatMitra/1.0 crisis-response-app'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await _saveTile(url, bytes);
        return bytes;
      }
    } catch (e) {
      debugPrint('[TileCache] Network error for $url: $e');
    }
    return null;
  }

  Future<void> _saveTile(String url, Uint8List bytes) async {
    if (!_initialized) await init();
    final file = _tileFile(url);
    await file.writeAsBytes(bytes);
    await _evictIfNeeded();
  }

  Future<void> _evictIfNeeded() async {
    try {
      final files = await _cacheDir!.list().toList();
      if (files.length <= _maxCachedTiles) return;
      final sorted = files.whereType<File>().toList()
        ..sort((a, b) =>
            a.statSync().accessed.compareTo(b.statSync().accessed));
      final toDelete = sorted.take(files.length - _maxCachedTiles);
      for (final f in toDelete) {
        await f.delete();
      }
    } catch (_) {}
  }

  /// Pre-warm tiles for an area while online.
  Future<void> prewarmArea({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int minZoom = 10,
    int maxZoom = 15,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!_initialized) await init();
    final urls = <String>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final xMin = _lngToTile(minLng, z);
      final xMax = _lngToTile(maxLng, z);
      final yMin = _latToTile(maxLat, z);
      final yMax = _latToTile(minLat, z);
      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          final sub = ['a', 'b', 'c', 'd'][x % 4];
          urls.add(
              'https://$sub.basemaps.cartocdn.com/dark_all/$z/$x/$y.png');
        }
      }
    }
    debugPrint('[TileCache] Pre-warming ${urls.length} tiles...');
    int done = 0;
    for (final url in urls) {
      await fetchAndCache(url);
      done++;
      onProgress?.call(done, urls.length);
    }
    debugPrint('[TileCache] Pre-warm complete.');
  }

  Future<int> cachedTileCount() async {
    if (!_initialized) await init();
    final files = await _cacheDir!.list().toList();
    return files.whereType<File>().length;
  }

  Future<void> clearCache() async {
    if (!_initialized) await init();
    await _cacheDir!.delete(recursive: true);
    await _cacheDir!.create();
  }

  // ── Tile math ─────────────────────────────────────────────────────────────
  int _lngToTile(double lng, int zoom) =>
      ((lng + 180) / 360 * (1 << zoom)).floor();

  int _latToTile(double lat, int zoom) {
    final latRad = lat * 3.141592653589793 / 180;
    final tanVal = _tan(latRad);
    final cosVal = _cos(latRad);
    final logVal = _ln(tanVal + 1 / cosVal);
    return ((1 - logVal / 3.141592653589793) / 2 * (1 << zoom)).floor();
  }

  double _ln(double x) {
    if (x <= 0) return 0;
    double result = 0;
    while (x > 2.718281828) {
      x /= 2.718281828;
      result++;
    }
    result += (x - 1) - (x - 1) * (x - 1) / 2;
    return result;
  }

  double _tan(double x) => _sin(x) / _cos(x);

  double _sin(double x) {
    double r = x % (2 * 3.141592653589793);
    return r - r * r * r / 6 + r * r * r * r * r / 120;
  }

  double _cos(double x) {
    double r = x % (2 * 3.141592653589793);
    return 1 - r * r / 2 + r * r * r * r / 24;
  }
}

/// CachedTileProvider — extends flutter_map's TileProvider.
/// Serves tiles from disk cache, fetches + saves when missing.
///
/// Usage:
///   TileLayer(
///     urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
///     subdomains: const ['a', 'b', 'c', 'd'],
///     tileProvider: CachedTileProvider(),
///   )
class CachedTileProvider extends TileProvider {
  final TileCacheService _cache = TileCacheService();

  CachedTileProvider() {
    _cache.init();
  }

  @override
  ImageProvider<Object> getImage(
      TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _CachedTileImage(url: url, cache: _cache);
  }
}

/// Internal ImageProvider using flutter painting + dart:ui APIs.
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final String url;
  final TileCacheService cache;

  const _CachedTileImage({required this.url, required this.cache});

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      _CachedTileImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadAsync(key, decode));
  }

  Future<ImageInfo> _loadAsync(
      _CachedTileImage key, ImageDecoderCallback decode) async {
    final bytes = await cache.fetchAndCache(url);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('[TileCache] No data for tile: $url');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
