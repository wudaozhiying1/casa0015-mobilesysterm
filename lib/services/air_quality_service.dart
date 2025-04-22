import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';

/// Represents an air quality data point, used for API query results
class AirQualityDataPoint {
  final LatLng location;
  final double aqi;     // Air Quality Index (0-500)
  final String? pollutant; // Main pollutant
  final String source;  // Data source
  
  AirQualityDataPoint({
    required this.location,
    required this.aqi,
    this.pollutant,
    required this.source,
  });
}

/// Represents an air quality data point
class AirQualityPoint {
  final LatLng position;
  final double aqi;     // Air Quality Index (0-500)
  final double weight;  // Weight (0.0-1.0)
  final Color color;    // Color
  final double radius;  // Impact radius (meters)
  
  AirQualityPoint({
    required this.position,
    required this.aqi,
    required this.weight,
    required this.color,
    this.radius = 0.0,
  });
}

/// Pollution source model class, used for simulating pollution sources at different locations
class _PollutionSource {
  final double latitude;
  final double longitude;
  final double intensity; // Intensity
  final double radius;    // Impact radius (kilometers)
  
  _PollutionSource({
    required this.latitude,
    required this.longitude,
    required this.intensity,
    required this.radius,
  });
}

/// Air Quality Service - Responsible for retrieving and processing air quality data
class AirQualityService with ChangeNotifier {
  // Google Air Quality API key
  static const String _apiKey = 'AIzaSyB3kdDgM5e1UKLXtdw6CTfaoiOzR66-cmU';
  static const String _baseUrl = 'https://airquality.googleapis.com/v1';
  
  // Method to provide the API key
  String getApiKey() {
    return _apiKey;
  }
  
  Map<String, dynamic>? airQualityData;
  bool isLoading = false;
  String? error;
  
  // Store air quality heatmap data
  List<AirQualityPoint> _heatmapData = [];
  List<AirQualityPoint> get heatmapData => _heatmapData;
  set heatmapData(List<AirQualityPoint> value) {
    _heatmapData = value;
    notifyListeners();
  }
  
  // Fixed city air quality levels, used to simulate real data
  final Map<String, double> _cityAirQualityBase = {
    'London': 35,      // Good
    'Beijing': 120,    // Unhealthy
    'Delhi': 180,      // Very unhealthy
    'Tokyo': 50,       // Moderate
    'New York': 40,    // Good
    'Paris': 60,       // Moderate
    'Los Angeles': 80, // Moderate
  };
  
  // Determine color based on AQI value
  Color _getColorForAQI(double aqi) {
    // Use more vibrant colors to enhance contrast
    if (aqi <= 30) {
      // Excellent: Dark green - Excellent air quality
      return const Color(0xFF009966);
    } else if (aqi <= 50) {
      // Good: Light green
      return const Color(0xFF00E400);
    } else if (aqi <= 100) {
      // Moderate: Yellow - Use more vibrant yellow
      return const Color(0xFFFFFF00);
    } else if (aqi <= 150) {
      // Lightly polluted: Orange - Use more vibrant orange
      return const Color(0xFFFF7E00);
    } else if (aqi <= 200) {
      // Moderately polluted: Red - Use more vibrant red
      return const Color(0xFFFF0000);
    } else if (aqi <= 300) {
      // Heavily polluted: Purple - Use more vibrant purple
      return const Color(0xFF8F3F97);
    } else {
      // Severely polluted: Deep purple/brown - Use more eye-catching brown
      return const Color(0xFF7E0023);
    }
  }
  
  // Calculate weight based on AQI value, used for heatmap display
  double _calculateWeight(double aqi) {
    // Increase weight for severely polluted areas to make them more visible on the map
    if (aqi <= 30) {
      return 0.3; // Very good air quality displays weaker
    } else if (aqi <= 50) {
      return 0.5;
    } else if (aqi <= 100) {
      return 0.65;
    } else if (aqi <= 150) {
      return 0.75;
    } else if (aqi <= 200) {
      return 0.85;
    } else if (aqi <= 300) {
      return 0.95;
    } else {
      return 1.0;
    }
  }
  
  // Calculate distance between two points (kilometers)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius (kilometers)
    
    // Convert to radians
    double latRad1 = _degreesToRadians(lat1);
    double lonRad1 = _degreesToRadians(lon1);
    double latRad2 = _degreesToRadians(lat2);
    double lonRad2 = _degreesToRadians(lon2);
    
    // Differences
    double dLat = latRad2 - latRad1;
    double dLon = lonRad2 - lonRad1;
    
    // Haversine formula
    double a = sin(dLat/2) * sin(dLat/2) +
               cos(latRad1) * cos(latRad2) * 
               sin(dLon/2) * sin(dLon/2);
    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    
    return earthRadius * c;
  }
  
  // Degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
  
  // Calculate distance between two points (kilometers)
  double _calculateDistanceInKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius (kilometers)
    
    // Convert to radians
    double latRad1 = _degreesToRadians(lat1);
    double lonRad1 = _degreesToRadians(lon1);
    double latRad2 = _degreesToRadians(lat2);
    double lonRad2 = _degreesToRadians(lon2);
    
    // Differences
    double dLat = latRad2 - latRad1;
    double dLon = lonRad2 - lonRad1;
    
    // Haversine formula
    double a = sin(dLat/2) * sin(dLat/2) +
               cos(latRad1) * cos(latRad2) * 
               sin(dLon/2) * sin(dLon/2);
    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    
    return earthRadius * c;
  }
  
  // Re-interpolate grid, generate heatmap data for given boundaries
  Future<void> generateHeatmapData(LatLngBounds bounds, {int gridSize = 20, double? zoomLevel}) async {
    // Clear existing data
    _heatmapData.clear();
    
    print('Starting to fetch air quality data');
    
    try {
      // Get boundary center point
      double centerLat = (bounds.southwest.latitude + bounds.northeast.latitude) / 2;
      double centerLng = (bounds.southwest.longitude + bounds.northeast.longitude) / 2;
      LatLng centerPoint = LatLng(centerLat, centerLng);
      
      // Create sample points list - total of 8 random points + center point
      final List<LatLng> samplePoints = [];
      
      // Add center point
      samplePoints.add(centerPoint);
      
      // Add 8 random points within 5km range
      final random = Random();
      final radius = 5.0; // 5 kilometer range
      
      // Add 4 points in cardinal directions (North, East, South, West)
      final directions = [0, 90, 180, 270];
      for (final angleDegrees in directions) {
        // Randomly adjust distance and angle, but keep near the main direction
        final adjustedAngle = angleDegrees + (random.nextDouble() * 30 - 15);
        final adjustedDistance = radius * (0.5 + random.nextDouble() * 0.5);
        
        final point = _calculateLocationInDirection(centerPoint, adjustedAngle.toInt(), adjustedDistance);
        samplePoints.add(point);
      }
      
      // Add 4 more points in random directions to ensure we have 8 points
      while (samplePoints.length < 9) {
        final angle = random.nextDouble() * 360;
        final distance = radius * random.nextDouble();
        final point = _calculateLocationInDirection(centerPoint, angle.toInt(), distance);
        samplePoints.add(point);
      }
      
      print('Created ${samplePoints.length} sample points');
      
      // Request real API data for each sample point
      List<Future<AirQualityPoint?>> apiRequests = [];
      for (final point in samplePoints) {
        apiRequests.add(_fetchPointAirQuality(point));
      }
      
      // Wait for all API requests to complete
      List<AirQualityPoint?> results = await Future.wait(apiRequests);
      
      // Filter out null results and add to heatmap data
      _heatmapData = results.where((point) => point != null).cast<AirQualityPoint>().toList();
      
      print('Successfully retrieved ${_heatmapData.length} air quality data points');
      
      // Notify listeners that data has been updated
      notifyListeners();
    } catch (e) {
      print('Error fetching air quality data: $e');
    }
  }
  
  // Get air quality point data for a specific location
  Future<AirQualityPoint?> _fetchPointAirQuality(LatLng location) async {
    try {
      // Use real API data
      Map<String, dynamic> data = await fetchGoogleAirQualityData(location);
      
      // If API request failed, return null
      if (data['aqi'] == null || data['aqi'] <= 0) return null;
      
      // Get AQI value
      double aqi = data['aqi'].toDouble();
      
      // Get color and weight based on AQI
      Color color = data['color'] ?? _getColorForAQI(aqi);
      double weight = _calculateWeight(aqi);
      
      // Create and return AQI point
      return AirQualityPoint(
        position: location,
        aqi: aqi,
        color: color,
        weight: weight,
      );
    } catch (e) {
      print('Failed to get air quality data for location ${location.latitude},${location.longitude}: $e');
      return null;
    }
  }
  
  // Calculate AQI value at a given position
  double _calculateAQIAtPosition(double lat, double lng, List<_PollutionSource> sources) {
    double aqi = 30; // Base AQI value, representing background air quality
    
    // Add contribution from each pollution source
    for (var source in sources) {
      double distance = _calculateDistanceInKm(
        lat, lng, source.latitude, source.longitude);
      
      // Only consider contribution when the point is within the source's impact radius
      if (distance <= source.radius) {
        // Use smooth inverse distance interpolation
        double factor = 1.0 - (distance / source.radius);
        // Use square relationship to make central area more polluted
        factor = factor * factor;
        
        // Enhance the contribution of pollution sources
        aqi += source.intensity * factor;
      }
    }
    
    // Ensure AQI value is within reasonable range
    aqi = aqi.clamp(0, 500);
    
    // Add some random variation to make the heatmap look more natural
    aqi += (Random().nextDouble() * 20 - 10);
    aqi = max(0, aqi);
    
    return aqi;
  }
  
  // Get air quality data along a route
  Future<List<AirQualityPoint>> getAirQualityAlongRoute(List<LatLng> routePoints, {int samplingRate = 5}) async {
    // Select path points based on sampling rate
    List<LatLng> sampledPoints = [];
    for (int i = 0; i < routePoints.length; i += samplingRate) {
      if (i < routePoints.length) {
        sampledPoints.add(routePoints[i]);
      }
    }
    
    // Ensure at least start and end points are included
    if (sampledPoints.isEmpty && routePoints.isNotEmpty) {
      sampledPoints.add(routePoints.first);
      if (routePoints.length > 1) {
        sampledPoints.add(routePoints.last);
      }
    }
    
    // Calculate air quality for each sample point
    List<AirQualityPoint> result = [];
    List<Future<Map<String, dynamic>>> apiRequests = [];
    
    // Create API request list
    for (LatLng point in sampledPoints) {
      apiRequests.add(fetchGoogleAirQualityData(point));
    }
    
    // Wait for all API requests to complete
    List<Map<String, dynamic>> apiResults = await Future.wait(apiRequests);
    
    // Process API results
    for (int i = 0; i < sampledPoints.length; i++) {
      if (i < apiResults.length) {
        Map<String, dynamic> data = apiResults[i];
        if (data['aqi'] != null && data['aqi'] > 0) { // Ensure API returned valid data
          result.add(AirQualityPoint(
            position: sampledPoints[i],
            aqi: data['aqi'].toDouble(),
            weight: _calculateWeight(data['aqi'].toDouble()),
            color: data['color'] ?? _getColorForAQI(data['aqi'].toDouble()),
            radius: 0.0, // Set to 0, indicating not to display as a circle
          ));
        }
      }
    }
    
    // If no valid data points were retrieved, add a default point to avoid errors
    if (result.isEmpty && sampledPoints.isNotEmpty) {
      print('Warning: All API requests along the route failed, adding a default point');
      result.add(AirQualityPoint(
        position: sampledPoints.first,
        aqi: 50.0, // Default good air quality
        weight: 0.5,
        color: const Color(0xFF00E400), // Green
        radius: 0.0,
      ));
    }
    
    return result;
  }
  
  // Get average air quality index for a route
  Future<double> getRouteAverageAQI(List<LatLng> routePoints) async {
    if (routePoints.isEmpty) return 0;
    
    List<AirQualityPoint> points = await getAirQualityAlongRoute(routePoints);
    if (points.isEmpty) return 0;
    
    double sum = 0;
    for (var point in points) {
      sum += point.aqi;
    }
    
    return sum / points.length;
  }
  
  // Get air quality data for a single location
  Future<void> getAirQualityData(double latitude, double longitude) async {
    isLoading = true;
    error = null;
    notifyListeners();
    
    try {
      final url = Uri.parse('$_baseUrl/currentConditions:lookup?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'location': {
            'latitude': latitude,
            'longitude': longitude
          },
          'extraComputations': [
            'POLLUTANT_CONCENTRATION',
            'DOMINANT_POLLUTANT_CONCENTRATION',
            'HEALTH_RECOMMENDATIONS',
            'POLLUTANT_ADDITIONAL_INFO'
          ],
          'languageCode': 'en' // Use English response
        })
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Process API response
        if (data['indexes'] != null && data['indexes'].isNotEmpty) {
          final indexData = data['indexes'][0];
          final aqi = indexData['aqi'] ?? 0;
          
          // Convert AQI to description and color
          String quality;
          Color color;
          
          switch (aqi) {
            case 1:
              quality = 'Excellent';
              color = Colors.green;
              break;
            case 2:
              quality = 'Good';
              color = Colors.yellow;
              break;
            case 3:
              quality = 'Moderate';
              color = Colors.orange;
              break;
            case 4:
              quality = 'Poor';
              color = Colors.red;
              break;
            case 5:
              quality = 'Very Poor';
              color = Colors.purple;
              break;
            default:
              quality = 'Unknown';
              color = Colors.grey;
          }
          
          // Save detailed pollutant data
          final components = indexData['components'];
          
          airQualityData = {
            'aqi': aqi,
            'quality': quality,
            'color': color,
            'co': components['co'], // Carbon monoxide (μg/m3)
            'no': components['no'], // Nitrogen monoxide (μg/m3)
            'no2': components['no2'], // Nitrogen dioxide (μg/m3)
            'o3': components['o3'], // Ozone (μg/m3)
            'so2': components['so2'], // Sulfur dioxide (μg/m3)
            'pm2_5': components['pm2_5'], // PM2.5 (μg/m3)
            'pm10': components['pm10'], // PM10 (μg/m3)
            'nh3': components['nh3'], // Ammonia (μg/m3)
          };
        } else {
          error = 'No air quality data found';
        }
      } else {
        error = 'Request failed: ${response.statusCode}';
      }
    } catch (e) {
      error = 'Error getting air quality data: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
  
  // Get Google air quality API data (current conditions)
  Future<Map<String, dynamic>> fetchGoogleAirQualityData(LatLng location) async {
    try {
      // Build Google Air Quality API request
      final url = Uri.parse('$_baseUrl/currentConditions:lookup?key=$_apiKey');
      
      // Create request body
      final requestBody = jsonEncode({
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude
        },
        'extraComputations': [
          'POLLUTANT_CONCENTRATION',
          'DOMINANT_POLLUTANT_CONCENTRATION',
          'HEALTH_RECOMMENDATIONS',
          'POLLUTANT_ADDITIONAL_INFO'
        ],
        'languageCode': 'en' // Use English response
      });
      
      print('Requesting air quality data: Location (${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})');
      
      // Add random delay to prevent API rate limiting from frequent requests
      await Future.delayed(Duration(milliseconds: 200 + Random().nextInt(300)));
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json'
        },
        body: requestBody
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check if index data exists
        if (data['indexes'] != null && data['indexes'].isNotEmpty) {
          // Get generic AQI
          final indexData = data['indexes'][0];
          final int aqi = indexData['aqi'] ?? 0;
          
          // Get color
          Color color;
          if (indexData['color'] != null) {
            // Get color from API
            final colorData = indexData['color'];
            double red = (colorData['red'] ?? 0) * 255;
            double green = (colorData['green'] ?? 0) * 255;
            double blue = (colorData['blue'] ?? 0) * 255;
            double alpha = (colorData['alpha'] ?? 255).toDouble();
            
            color = Color.fromRGBO(red.toInt(), green.toInt(), blue.toInt(), alpha/255);
          } else {
            // Generate color using local logic
            color = _getColorForAQI(aqi.toDouble());
          }
          
          // Get main pollutant
          String? pollutant = indexData['dominantPollutant'];
          String category = indexData['category'] ?? 'Unknown';
          
          print('Received air quality data: AQI=$aqi, Level=$category, Location=(${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})');
          
          return {
            'aqi': aqi,
            'quality': category,
            'color': color,
            'pollutant': pollutant,
            'source': 'Google Air Quality API',
            'dateTime': data['dateTime'],
            'regionCode': data['regionCode']
          };
        } else {
          print('API did not return air quality index data: Location=(${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})');
          return {
            'aqi': 0,
            'quality': 'No data',
            'color': Colors.grey,
            'pollutant': 'Unknown',
            'source': 'Google Air Quality API',
          };
        }
      } else {
        print('API request failed: ${response.statusCode}, Location=(${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})');
        return {
          'aqi': 0,
          'quality': 'Request failed',
          'color': Colors.grey,
          'pollutant': 'Error',
          'source': 'Google Air Quality API',
          'error': 'HTTP error ${response.statusCode}'
        };
      }
    } catch (e) {
      print('Exception getting air quality data: $e, Location=(${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)})');
      return {
        'aqi': 0,
        'quality': 'Data retrieval failed',
        'color': Colors.grey,
        'pollutant': 'Error',
        'source': 'Google Air Quality API',
        'error': e.toString(),
        'coordinates': '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
      };
    }
  }
  
  // Calculate new location from a starting point given angle and distance
  LatLng _calculateLocationInDirection(LatLng start, int angleDegrees, double distanceKm) {
    // Convert distance from kilometers to degrees
    double distanceRadians = distanceKm / 6371.0; // Earth radius is approximately 6371 kilometers
    double angleRadians = angleDegrees * pi / 180; // Convert angle to radians
    
    double startLatRadians = start.latitude * pi / 180;
    double startLngRadians = start.longitude * pi / 180;
    
    // Calculate new latitude
    double newLatRadians = asin(
      sin(startLatRadians) * cos(distanceRadians) +
      cos(startLatRadians) * sin(distanceRadians) * cos(angleRadians)
    );
    
    // Calculate new longitude
    double newLngRadians = startLngRadians + atan2(
      sin(angleRadians) * sin(distanceRadians) * cos(startLatRadians),
      cos(distanceRadians) - sin(startLatRadians) * sin(newLatRadians)
    );
    
    // Convert back to degrees
    double newLat = newLatRadians * 180 / pi;
    double newLng = newLngRadians * 180 / pi;
    
    return LatLng(newLat, newLng);
  }
  
  // Submit user-measured air quality data
  Future<bool> submitUserMeasurement(double latitude, double longitude, Map<String, dynamic> measurement) async {
    try {
      // In production, this would be an actual API call to send data to the server
      // Example: final response = await http.post(Uri.parse('$_baseUrl/submit-data'), body: {...});
      
      // Simulate API call delay
      await Future.delayed(const Duration(seconds: 1));
      
      debugPrint('Submitting user measurement data: $measurement at location $latitude, $longitude');
      
      // Here you could add data to local storage or processing logic
      
      return true; // Assume submission successful
    } catch (e) {
      debugPrint('Failed to submit user measurement data: $e');
      return false;
    }
  }
  
  // Get air quality data for different directions around a specified area
  Future<Map<String, Map<String, dynamic>>> getNearbyRegionsAirQuality(LatLng centerLocation, {double radius = 3.0}) async {
    print('Getting regional air quality data: Center point ${centerLocation.latitude},${centerLocation.longitude}');
    Map<String, Map<String, dynamic>> result = {};
    
    try {
      // Add center region
      try {
        final Map<String, dynamic> centerData = await fetchGoogleAirQualityData(centerLocation);
        
        if (centerData['aqi'] != null && centerData['aqi'] > 0) {  // Check if API successfully retrieved data
          result['Current Location'] = {
            'aqi': centerData['aqi'],
            'location': centerLocation,
            'distance': 0.0,
            'quality': centerData['quality'],
            'color': centerData['color'],
            'pollutant': centerData['pollutant'],
            'source': centerData['source'],
            'station_name': 'Current Location',
            'coordinates': '${centerLocation.latitude.toStringAsFixed(5)}, ${centerLocation.longitude.toStringAsFixed(5)}',
          };
          
          print('Successfully retrieved current location air quality data: AQI=${centerData['aqi']}');
        }
      } catch (e) {
        print('Failed to get center region air quality data: $e');
      }
      
      // Define sampling points for directions
      Map<String, int> directions = {
        'Northern Area': 0,      // North
        'Northeast Area': 45,    // Northeast
        'Eastern Area': 90,      // East
        'Southeast Area': 135,   // Southeast
        'Southern Area': 180,    // South
        'Southwest Area': 225,   // Southwest
        'Western Area': 270,     // West
        'Northwest Area': 315,   // Northwest
      };
      
      // Set sampling distances
      List<double> distances = [3.0, 5.0];
      
      // For each distance, get air quality in each direction
      for (double distance in distances) {
        // Process each direction
        for (var entry in directions.entries) {
          String direction = entry.key;
          int angle = entry.value;
          
          // Check if data for this direction already exists
          String directionKey = direction;
          if (result.containsKey(directionKey)) continue;
          
          // Calculate location point for this direction
          LatLng location = _calculateLocationInDirection(
            centerLocation, angle, distance);
          
          try {
            // Get Google air quality data
            final Map<String, dynamic> airQualityData = await fetchGoogleAirQualityData(location);
            
            // Check if API returned valid data
            if (airQualityData['aqi'] != null && airQualityData['aqi'] > 0) {
              // Save data for this point, including coordinate information
              result[directionKey] = {
                'aqi': airQualityData['aqi'],
                'location': location,
                'distance': distance,
                'quality': airQualityData['quality'],
                'color': airQualityData['color'],
                'pollutant': airQualityData['pollutant'],
                'source': airQualityData['source'],
                'station_name': '$direction Sample Point',
                'coordinates': '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
              };
              
              print('Successfully retrieved $direction real-time air quality data: AQI=${airQualityData['aqi']}, Distance: ${distance}km');
            }
          } catch (e) {
            print('Failed to get $direction air quality data: $e');
          }
        }
        
        // If enough data has been retrieved, don't get data for farther distances
        if (result.length >= 5) {
          print('Retrieved data for ${result.length} regions, not retrieving data for farther distances');
          break;
        }
      }
    } catch (e) {
      print('Error getting surrounding air quality data: $e');
    }
    
    print('Generated air quality data for ${result.length} regions in total');
    return result;
  }
  
  // Try to get heatmap tiles
  String getAirQualityHeatmapTileUrl(int z, int x, int y) {
    // Build Google Air Quality Heatmap Tile URL
    return '$_baseUrl/mapTypes/US_AQI/heatmapTiles/$z/$x/$y?key=$_apiKey';
  }
} 