import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/air_quality_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Air Quality Controller - Responsible for managing air quality related UI states
class AirQualityController extends ChangeNotifier {
  final AirQualityService _airQualityService;
  
  // Heatmap data
  List<AirQualityPoint> _heatmapData = [];
  List<AirQualityPoint> get heatmapData => _heatmapData;
  set heatmapData(List<AirQualityPoint> value) {
    _heatmapData = value;
    notifyListeners();
  }
  
  // Heatmap visibility
  bool _isVisible = false;
  bool get isVisible => _isVisible;
  
  // Heatmap opacity (0.0-1.0)
  double _opacity = 0.7;
  double get opacity => _opacity;
  set opacity(double value) {
    if (value != _opacity && value >= 0.0 && value <= 1.0) {
      _opacity = value;
      notifyListeners();
    }
  }
  
  // Use tile overlay
  bool _useTileOverlay = true;
  bool get useTileOverlay => _useTileOverlay;
  
  // Tile overlay ID
  TileOverlay? _tileOverlay;
  TileOverlay? get tileOverlay => _tileOverlay;
  
  // Tile overlay URL template
  String? _tileUrlTemplate;
  String? get tileUrlTemplate => _tileUrlTemplate;
  
  // Whether data is loading
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // Constructor
  AirQualityController(this._airQualityService) {
    // Listen to data changes in the service layer
    _airQualityService.addListener(_updateFromService);
    
    // Initially get data from service
    _heatmapData = _airQualityService.heatmapData;
  }
  
  // Getters
  AirQualityService get service => _airQualityService;
  
  // Setters
  set isVisible(bool value) {
    if (_isVisible != value) {
      _isVisible = value;
      notifyListeners();
    }
  }
  
  // Get updates from Service
  void _updateFromService() {
    _heatmapData = _airQualityService.heatmapData;
    notifyListeners();
  }
  
  // Toggle heatmap visibility
  void toggleVisibility() {
    _isVisible = !_isVisible;
    notifyListeners();
  }
  
  // Set heatmap visibility
  void setVisibility(bool isVisible) {
    _isVisible = isVisible;
    notifyListeners();
  }
  
  // Generate heatmap data for specified location
  Future<void> generateHeatmapForLocation(LatLng location, {double radius = 0.02, double? zoomLevel}) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Create bounds - centered at location, extending radius degrees in all directions
      final LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          location.latitude - radius,
          location.longitude - radius,
        ),
        northeast: LatLng(
          location.latitude + radius,
          location.longitude + radius,
        ),
      );
      
      // If using tile overlay, prepare tile URL template
      if (_useTileOverlay) {
        _prepareTileOverlayUrl();
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // Otherwise, generate heatmap using data points method
      await _airQualityService.generateHeatmapData(bounds, zoomLevel: zoomLevel);
      _heatmapData = _airQualityService.heatmapData;
    } catch (e) {
      print('Failed to generate heatmap data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Prepare tile overlay URL template
  void _prepareTileOverlayUrl() {
    // Use heatmap tiles provided by Google Air Quality API, get apiKey from service
    final apiKey = _airQualityService.getApiKey(); // Use getter method to get API key
    _tileUrlTemplate = 'https://airquality.googleapis.com/v1/mapTypes/US_AQI/heatmapTiles/{z}/{x}/{y}?key=$apiKey';
    notifyListeners();
  }
  
  // Set tile overlay
  void setTileOverlay(TileOverlay overlay) {
    _tileOverlay = overlay;
    notifyListeners();
  }
  
  // Get air quality data along route
  Future<List<AirQualityPoint>> getAirQualityAlongRoute(List<LatLng> routePoints) async {
    return await _airQualityService.getAirQualityAlongRoute(routePoints);
  }
  
  // Get route average air quality index
  Future<double> getRouteAverageAQI(List<LatLng> routePoints) async {
    return await _airQualityService.getRouteAverageAQI(routePoints);
  }
  
  // Get surrounding areas' air quality data
  Future<Map<String, Map<String, dynamic>>> getNearbyRegionsAirQuality(LatLng centerLocation) async {
    return await _airQualityService.getNearbyRegionsAirQuality(centerLocation);
  }
  
  // Clear heatmap data
  void clearHeatmapData() {
    _heatmapData = [];
    notifyListeners();
  }
  
  @override
  void dispose() {
    _airQualityService.removeListener(_updateFromService);
    super.dispose();
  }
}

// Custom UrlTileProvider for Google Air Quality tiles
class UrlTileProvider implements TileProvider {
  final String urlTemplate;
  
  UrlTileProvider({required this.urlTemplate});
  
  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    if (zoom == null) {
      return TileProvider.noTile;
    }
    
    final url = urlTemplate
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString())
        .replaceAll('{z}', zoom.toString());
    
    try {
      final imageData = await _getImageData(url);
      return Tile(256, 256, imageData);
    } catch (e) {
      print('Error loading tile: $e');
      return TileProvider.noTile;
    }
  }
  
  Future<Uint8List> _getImageData(String url) async {
    try {
      final http = HttpClient();
      final request = await http.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    } catch (e) {
      print('Error loading tile: $e');
      return Uint8List(0);
    }
  }
} 