import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/air_quality_service.dart';

/// Air quality visualization overlay - Using gradient color areas instead of points
class AirQualityOverlay extends StatefulWidget {
  final List<AirQualityPoint> data;
  final double opacity;
  final bool showLegend;
  
  const AirQualityOverlay({
    Key? key,
    required this.data,
    this.opacity = 0.7,
    this.showLegend = true,
  }) : super(key: key);

  @override
  _AirQualityOverlayState createState() => _AirQualityOverlayState();
}

class _AirQualityOverlayState extends State<AirQualityOverlay> {
  @override
  Widget build(BuildContext context) {
    // Add debug output
    print('AirQualityOverlay: Building overlay, number of data points: ${widget.data.length}');
    
    if (widget.data.isEmpty) {
      print('AirQualityOverlay: Warning - No data points');
      // Return a semi-transparent information message instead of an empty component
      return Center(
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 32),
              SizedBox(height: 8),
              Text(
                'Loading air quality data...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }
    
    return Stack(
      children: [
        // Use a more lightweight implementation
        ClipRect(
          child: _buildSimplifiedOverlay(context),
        ),
        
        // If legend is enabled, show the legend
        if (widget.showLegend)
          Positioned(
            right: 16,
            bottom: 100,
            child: _buildLegend(),
          ),
      ],
    );
  }

  // Build simplified air quality overlay
  Widget _buildSimplifiedOverlay(BuildContext context) {
    // Limit the maximum number of points to avoid memory overflow
    final maxDataPoints = 25;
    final dataToShow = widget.data.length > maxDataPoints 
        ? widget.data.take(maxDataPoints).toList() 
        : widget.data;
    
    // Use CustomPaint instead of many Positioned components
    return CustomPaint(
      size: Size.infinite,
      painter: _LightweightAQIPainter(
        data: dataToShow,
        opacity: widget.opacity,
      ),
    );
  }
  
  // Build air quality legend
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Air Quality Index (AQI)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          _legendItem(const Color(0xFF00E400), 'Excellent (0-50)'),
          _legendItem(const Color(0xFFFFFF00), 'Good (51-100)'),
          _legendItem(const Color(0xFFFF7E00), 'Lightly Polluted (101-150)'),
          _legendItem(const Color(0xFFFF0000), 'Moderately Polluted (151-200)'),
          _legendItem(const Color(0xFF9900FF), 'Heavily Polluted (201-300)'),
          _legendItem(const Color(0xFF990000), 'Severely Polluted (>300)'),
        ],
      ),
    );
  }
  
  // Build single legend item
  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Lightweight AQI painter, only showing sample points and AQI values
class _LightweightAQIPainter extends CustomPainter {
  final List<AirQualityPoint> data;
  final double opacity;
  
  _LightweightAQIPainter({
    required this.data,
    this.opacity = 0.7,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    // Calculate geographic boundaries
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    
    for (var point in data) {
      if (point.position.latitude < minLat) minLat = point.position.latitude;
      if (point.position.latitude > maxLat) maxLat = point.position.latitude;
      if (point.position.longitude < minLng) minLng = point.position.longitude;
      if (point.position.longitude > maxLng) maxLng = point.position.longitude;
    }
    
    // Ensure boundaries have certain width and height
    if ((maxLat - minLat).abs() < 0.000001) {
      maxLat += 0.001;
      minLat -= 0.001;
    }
    if ((maxLng - minLng).abs() < 0.000001) {
      maxLng += 0.001;
      minLng -= 0.001;
    }
    
    // Convert lat/lng to pixel coordinates
    for (var point in data) {
      // Calculate position on canvas
      double x = (point.position.longitude - minLng) / (maxLng - minLng) * size.width;
      double y = (1 - (point.position.latitude - minLat) / (maxLat - minLat)) * size.height;
      
      // Ensure coordinates are within canvas range
      x = x.clamp(0, size.width);
      y = y.clamp(0, size.height);
      
      // Draw marker point
      final pointRadius = 12.0;
      final Paint circlePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = point.color.withOpacity(opacity);
      
      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white;
      
      // Draw circular marker
      canvas.drawCircle(Offset(x, y), pointRadius, circlePaint);
      canvas.drawCircle(Offset(x, y), pointRadius, borderPaint);
      
      // Draw AQI value text
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${point.aqi.toInt()}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 1,
                color: Colors.black,
                offset: Offset(0.5, 0.5),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas, 
        Offset(x - textPainter.width / 2, y - textPainter.height / 2)
      );
    }
  }
  
  @override
  bool shouldRepaint(_LightweightAQIPainter oldDelegate) {
    return data != oldDelegate.data || opacity != oldDelegate.opacity;
  }
}

/// Custom painter for air quality layer
class AirQualityPainter extends CustomPainter {
  final List<AirQualityPoint> data;
  final double opacity;
  
  // Store data points in pixel coordinates
  late List<_PixelAQIPoint> _pixelPoints = [];
  
  // Pre-calculated color cache
  Map<Offset, Color> _colorCache = {};
  
  // Add flag to control whether to use cached data
  bool _useCache = false;
  
  // Add current zoom level for adjusting rendering strategy
  double _currentZoomLevel = 15.0; // Default medium zoom level
  
  // Add boundary variables
  double minLat = 0.0;
  double maxLat = 0.0;
  double minLng = 0.0;
  double maxLng = 0.0;
  
  AirQualityPainter({
    required this.data,
    this.opacity = 0.7,
  }) {
    // Try to infer zoom level from data
    _inferZoomLevel();
    // Calculate geographic boundaries
    _calculateBounds();
  }
  
  // Calculate geographic boundaries of data points
  void _calculateBounds() {
    if (data.isEmpty) return;
    
    // Initialize boundary values
    minLat = double.infinity;
    maxLat = -double.infinity;
    minLng = double.infinity;
    maxLng = -double.infinity;
    
    // Find boundaries by iterating through all points
    for (var point in data) {
      if (point.position.latitude < minLat) minLat = point.position.latitude;
      if (point.position.latitude > maxLat) maxLat = point.position.latitude;
      if (point.position.longitude < minLng) minLng = point.position.longitude;
      if (point.position.longitude > maxLng) maxLng = point.position.longitude;
    }
    
    // Ensure boundaries have certain width and height to prevent division by zero
    if ((maxLat - minLat).abs() < 0.000001) {
      maxLat += 0.001;
      minLat -= 0.001;
    }
    if ((maxLng - minLng).abs() < 0.000001) {
      maxLng += 0.001;
      minLng -= 0.001;
    }
  }
  
  // Infer zoom level from point spacing
  void _inferZoomLevel() {
    if (data.isEmpty || data.length <= 1) return;
    
    try {
      // Take first 10 points to calculate average spacing
      int sampleSize = min(10, data.length - 1);
      double totalDistance = 0;
      int count = 0;
      
      for (int i = 0; i < sampleSize; i++) {
        for (int j = i + 1; j < sampleSize + 1; j++) {
          double lat1 = data[i].position.latitude;
          double lng1 = data[i].position.longitude;
          double lat2 = data[j].position.latitude;
          double lng2 = data[j].position.longitude;
          
          // Simple calculation of distance between two points (degrees)
          double dist = sqrt(pow(lat1 - lat2, 2) + pow(lng1 - lng2, 2));
          totalDistance += dist;
          count++;
        }
      }
      
      if (count > 0) {
        double avgDistance = totalDistance / count;
        
        // Map average distance to zoom level
        // Empirical values: distance 0.1 is approximately zoom level 10, distance 0.001 is approximately zoom level 18
        _currentZoomLevel = 14.0 - log(avgDistance) / ln10 * 4.0;
        _currentZoomLevel = _currentZoomLevel.clamp(10.0, 20.0);
      }
    } catch (e) {
      print('Failed to infer zoom level: $e');
    }
  }
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      print('AirQualityPainter: No data to draw');
      return;
    }
    
    print('AirQualityPainter: Starting to draw heatmap, number of data points: ${data.length}');
    print('Canvas size: ${size.width} x ${size.height}');
    
    if (!_validateData()) {
      return;
    }
    
    _convertToPixelCoordinates(size);
    
    if (_pixelPoints.isEmpty) {
      print('AirQualityPainter: No valid pixel points');
      return;
    }
    
    // Draw heatmap
    _drawHeatmap(canvas, size);
    
    print('AirQualityPainter: Heatmap drawing completed');
  }
  
  // Validate data validity
  bool _validateData() {
    if (data.isEmpty) {
      print('AirQualityPainter: Data is empty');
      return false;
    }
    
    // Check if all point positions are valid
    int invalidPointCount = 0;
    for (var point in data) {
      if (point.position.latitude.isNaN || 
          point.position.longitude.isNaN ||
          point.position.latitude == 0 && point.position.longitude == 0) {
        invalidPointCount++;
      }
    }
    
    if (invalidPointCount > 0) {
      print('AirQualityPainter: Found $invalidPointCount invalid coordinate points');
      if (invalidPointCount == data.length) {
        print('AirQualityPainter: All points are invalid, cannot draw');
        return false;
      }
    }
    
    // Check if all points are at the same location
    bool allSameLocation = true;
    final firstLat = data.first.position.latitude;
    final firstLng = data.first.position.longitude;
    
    for (var point in data) {
      if ((point.position.latitude - firstLat).abs() > 0.0000001 ||
          (point.position.longitude - firstLng).abs() > 0.0000001) {
        allSameLocation = false;
        break;
      }
    }
    
    if (allSameLocation) {
      print('AirQualityPainter: All points are at the same location, heatmap may not be visible');
      // Don't return false, as we can still draw in this case
    }
    
    return true;
  }

  // Convert geographic coordinates to pixel coordinates
  void _convertToPixelCoordinates(Size size) {
    _pixelPoints.clear();
    
    // Find geographic boundaries
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    
    for (var point in data) {
      if (point.position.latitude < minLat) minLat = point.position.latitude;
      if (point.position.latitude > maxLat) maxLat = point.position.latitude;
      if (point.position.longitude < minLng) minLng = point.position.longitude;
      if (point.position.longitude > maxLng) maxLng = point.position.longitude;
    }
    
    print('Geographic boundaries: Latitude[$minLat, $maxLat], Longitude[$minLng, $maxLng]');
    
    if (maxLat - minLat < 0.000001 || maxLng - minLng < 0.000001) {
      print('AirQualityPainter: Geographic boundaries too small, expanding boundaries');
      double latPadding = 0.001;
      double lngPadding = 0.001;
      minLat -= latPadding;
      maxLat += latPadding;
      minLng -= lngPadding;
      maxLng += lngPadding;
    }
    
    for (var point in data) {
      // Convert geographic coordinates to 0-1 range
      double normalizedLat = (point.position.latitude - minLat) / (maxLat - minLat);
      double normalizedLng = (point.position.longitude - minLng) / (maxLng - minLng);
      
      // Invert latitude (screen coordinate system y-axis downward)
      normalizedLat = 1.0 - normalizedLat;
      
      // Convert to pixel coordinates
      double x = normalizedLng * size.width;
      double y = normalizedLat * size.height;
      
      _pixelPoints.add(_PixelAQIPoint(
        x: x,
        y: y,
        aqi: point.aqi,
        color: point.color,
        weight: point.weight,
        originalPosition: point.position, // Save original coordinates for debugging
      ));
    }
    
    print('Number of pixel points after conversion: ${_pixelPoints.length}');
  }

  // Draw heatmap
  void _drawHeatmap(Canvas canvas, Size size) {
    // Draw directly on the input canvas instead of using offscreen image
    _drawGradientMap(canvas, size);
    print('Heatmap drawing completed');
  }
  
  // Draw smooth gradient heatmap
  void _drawGradientMap(Canvas canvas, Size size) {
    if (_pixelPoints.isEmpty) return;

    print('Drawing heatmap blocks: Starting to draw, canvas size: ${size.width}x${size.height}');
    
    // Create finer grid - increase grid density
    final int gridWidth = (size.width / 5).ceil(); // One grid point every 5 pixels
    final int gridHeight = (size.height / 5).ceil();
    
    // Store color and weight for each grid point
    final List<List<Map<String, dynamic>>> grid = List.generate(
      gridHeight,
      (_) => List.generate(
        gridWidth,
        (_) => {'color': Colors.transparent, 'weight': 0.0, 'aqi': 0.0},
      ),
    );
    
    // Create an influence range for each AQI point to make the heatmap smoother
    final double influenceRadius = min(size.width, size.height) / 15; // Influence radius
    
    // Map air quality data points to grid
    for (var point in _pixelPoints) {
      // Map pixel coordinates to grid indices
      final int centerGridX = (point.x / size.width * gridWidth).floor().clamp(0, gridWidth - 1);
      final int centerGridY = (point.y / size.height * gridHeight).floor().clamp(0, gridHeight - 1);
      
      // Calculate influence range (grid cells)
      final int radiusInGrid = (influenceRadius / size.width * gridWidth).ceil();
      final int startX = max(0, centerGridX - radiusInGrid);
      final int endX = min(gridWidth - 1, centerGridX + radiusInGrid);
      final int startY = max(0, centerGridY - radiusInGrid);
      final int endY = min(gridHeight - 1, centerGridY + radiusInGrid);
      
      // All grid points within influence range
      for (int y = startY; y <= endY; y++) {
        for (int x = startX; x <= endX; x++) {
          // Calculate pixel coordinates corresponding to grid point
          final double pixelX = (x + 0.5) * size.width / gridWidth;
          final double pixelY = (y + 0.5) * size.height / gridHeight;
          
          // Calculate distance to AQI point
          final double distance = sqrt(pow(pixelX - point.x, 2) + pow(pixelY - point.y, 2));
          
          // If within influence radius
          if (distance <= influenceRadius) {
            // Calculate distance-based weight - closer distance has higher weight
            final double influence = 1.0 - (distance / influenceRadius);
            final double weight = pow(influence, 2).toDouble() * point.weight; // Quadratic function makes center stronger
            
            // If new weight is higher, update grid point
            if (weight > grid[y][x]['weight']) {
              grid[y][x] = {
                'color': point.color,
                'weight': weight,
                'aqi': point.aqi
              };
            }
          }
        }
      }
    }
    
    // Use blur effect to draw heatmap
    final Paint paint = Paint()..style = PaintingStyle.fill;
    
    // Draw directly to canvas, don't use image and blur effect (avoid async issues)
    for (int y = 0; y < gridHeight; y++) {
      for (int x = 0; x < gridWidth; x++) {
        final Map<String, dynamic> cell = grid[y][x];
        final double weight = cell['weight'] as double;
        
        if (weight > 0.01) { // Ignore cells with too small weight
          // Calculate center point coordinates
          final double centerX = (x + 0.5) * size.width / gridWidth;
          final double centerY = (y + 0.5) * size.height / gridHeight;
          
          // Set color and opacity
          final Color color = cell['color'] as Color;
          paint.color = color.withOpacity(weight * opacity);
          
          // Use radial gradient instead of blur effect
          final RadialGradient gradient = RadialGradient(
            colors: [
              paint.color,
              paint.color.withOpacity(0.0),
            ],
            stops: [0.0, 1.0],
          );
          
          // Draw circular hotspot
          final double radius = 8.0 * weight * 1.5; // Adjust size for better visual effect
          
          final Rect rect = Rect.fromCircle(
            center: Offset(centerX, centerY),
            radius: radius,
          );
          
          paint.shader = gradient.createShader(rect);
          canvas.drawCircle(Offset(centerX, centerY), radius, paint);
          paint.shader = null; // Clear shader for next use
        }
      }
    }
    
    print('Heatmap drawing completed');
  }
  
  @override
  bool shouldRepaint(AirQualityPainter oldDelegate) {
    // Repaint if opacity changes
    if (oldDelegate.opacity != opacity) return true;
    
    // Repaint if data length changes
    if (oldDelegate.data.length != data.length) return true;
    
    // Repaint if data content changes
    bool dataChanged = false;
    if (oldDelegate.data.length == data.length) {
      for (int i = 0; i < data.length; i++) {
        if (oldDelegate.data[i].position != data[i].position || 
            oldDelegate.data[i].aqi != data[i].aqi ||
            oldDelegate.data[i].color != data[i].color) {
          dataChanged = true;
          break;
        }
      }
    }
    
    // Repaint if data content has changed
    if (dataChanged) return true;
    
    // Repaint on first draw
    if (_pixelPoints.isEmpty) return true;
    
    // Always repaint to ensure heatmap displays correctly
    return true;
  }

  // Convert geographic coordinates to pixel coordinates
  Offset _geoToPixel(LatLng position, Size size) {
    // Use current boundary range for conversion
    double x = (position.longitude - minLng) / (maxLng - minLng) * size.width;
    double y = (1 - (position.latitude - minLat) / (maxLat - minLat)) * size.height;
    return Offset(x, y);
  }
  
  // Convert pixel coordinates back to geographic coordinates
  LatLng _pixelToGeo(Offset pixel, Size size) {
    // Use current boundary range for conversion
    double lng = (pixel.dx / size.width) * (maxLng - minLng) + minLng;
    double lat = (1 - (pixel.dy / size.height)) * (maxLat - minLat) + minLat;
    return LatLng(lat, lng);
  }
}

// Helper class, representing a point in pixel coordinate system
class _PixelAQIPoint {
  final double x;
  final double y;
  final double aqi;
  final Color color;
  final double weight;
  final LatLng originalPosition; // Add original lat/lng for debugging
  
  _PixelAQIPoint({
    required this.x,
    required this.y,
    required this.aqi,
    required this.color,
    required this.weight,
    required this.originalPosition,
  });
}

/// Widget that displays Air Quality Index (AQI) legend
class AirQualityLegend extends StatelessWidget {
  const AirQualityLegend({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Air Quality Index (AQI)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendItem('Excellent', '0-50', Colors.green),
          _buildLegendItem('Good', '51-100', Colors.yellow),
          _buildLegendItem('Lightly Polluted', '101-150', Colors.orange),
          _buildLegendItem('Moderately Polluted', '151-200', Colors.red),
          _buildLegendItem('Heavily Polluted', '201-300', Colors.purple),
          _buildLegendItem('Severely Polluted', '300+', Colors.brown[800]!),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String range, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Text(
            range,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    );
  }
} 