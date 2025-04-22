import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:math' as math;
import 'air_quality_service.dart';

class DirectionsService {
  static const String _apiKey = 'AIzaSyB3kdDgM5e1UKLXtdw6CTfaoiOzR66-cmU';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  
  // Get navigation route data
  static Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    String travelMode = 'walking', // Options: 'walking', 'driving', 'bicycling', 'transit'
  }) async {
    final url = Uri.parse(
      '$_baseUrl?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=$travelMode'
      '&key=$_apiKey'
      '&alternatives=true' // Request multiple alternative routes
    );
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check API response status
        if (data['status'] == 'OK') {
          return DirectionsResult.fromMap(data);
        } else {
          debugPrint('Directions API error: ${data['status']}');
          return null;
        }
      } else {
        debugPrint('Directions API request failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Directions API exception: $e');
      return null;
    }
  }
  
  // Calculate average air quality along a route
  static Future<double> calculateRouteAirQuality(List<LatLng> route, AirQualityService airQualityService) async {
    if (route.isEmpty) return 0;
    
    double totalAQI = 0;
    int samplePoints = 0;
    
    // Sample the route, getting air quality data at specific intervals
    int samplingStep = math.max(1, route.length ~/ 10); // Sample at least 10 points if the route is long enough
    
    for (int i = 0; i < route.length; i += samplingStep) {
      final point = route[i];
      try {
        // Get air quality data for this point
        final airQualityData = await airQualityService.fetchGoogleAirQualityData(point);
        if (airQualityData != null && airQualityData['aqi'] != null) {
          totalAQI += airQualityData['aqi'];
          samplePoints++;
        }
      } catch (e) {
        debugPrint('Failed to get air quality data for point (${point.latitude}, ${point.longitude}): $e');
      }
    }
    
    // Avoid division by zero
    if (samplePoints == 0) return 0;
    
    return totalAQI / samplePoints;
  }
  
  // Get multiple routes, including fastest route, lowest pollution route, and alternative routes
  static Future<List<RouteOption>> getRouteOptions({
    required LatLng origin,
    required LatLng destination,
    required AirQualityService airQualityService,
    String travelMode = 'walking',
  }) async {
    List<RouteOption> routeOptions = [];
    
    // Get navigation routes
    final directionsResult = await getDirections(
      origin: origin,
      destination: destination,
      travelMode: travelMode,
    );
    
    if (directionsResult == null || directionsResult.routes.isEmpty) {
      return routeOptions;
    }
    
    // Process all route options
    for (int i = 0; i < directionsResult.routes.length; i++) {
      final route = directionsResult.routes[i];
      
      // Calculate average air quality for this route
      double avgAirQuality = await calculateRouteAirQuality(
        route.polylinePoints,
        airQualityService,
      );
      
      // Create route option
      RouteOption option;
      if (i == 0) {
        // Mark first route as the fastest route
        option = RouteOption(
          route: route,
          avgAirQuality: avgAirQuality,
          routeType: RouteType.fastest,
        );
      } else {
        // Mark other routes as alternative routes
        option = RouteOption(
          route: route,
          avgAirQuality: avgAirQuality,
          routeType: RouteType.alternative,
        );
      }
      
      routeOptions.add(option);
    }
    
    // If there are multiple routes, find the one with the best air quality
    if (routeOptions.length > 1) {
      // Find the route with the lowest AQI value
      RouteOption? lowestAQIRoute = routeOptions.reduce((curr, next) => 
        curr.avgAirQuality < next.avgAirQuality ? curr : next);
      
      // If this route is not already marked as the fastest, mark it as the lowest pollution route
      if (lowestAQIRoute.routeType != RouteType.fastest) {
        lowestAQIRoute.routeType = RouteType.lowestPollution;
      } else {
        // Find the second lowest as the lowest pollution route
        List<RouteOption> otherRoutes = [...routeOptions];
        otherRoutes.remove(lowestAQIRoute);
        
        if (otherRoutes.isNotEmpty) {
          RouteOption secondLowestAQIRoute = otherRoutes.reduce((curr, next) => 
            curr.avgAirQuality < next.avgAirQuality ? curr : next);
          secondLowestAQIRoute.routeType = RouteType.lowestPollution;
        }
      }
    }
    
    return routeOptions;
  }
}

// Route type enumeration
enum RouteType {
  fastest,          // Fastest path
  lowestPollution,  // Lowest pollution path
  alternative       // Alternative path
}

// Route option, containing multiple route types
class RouteOption {
  final RouteData route;
  final double avgAirQuality; // Average air quality
  RouteType routeType; // Allow modification of route type

  RouteOption({
    required this.route,
    required this.avgAirQuality,
    required this.routeType,
  });

  // Get corresponding icon based on route type
  IconData get icon {
    switch (routeType) {
      case RouteType.fastest:
        return Icons.speed;
      case RouteType.lowestPollution:
        return Icons.eco;
      case RouteType.alternative:
        return Icons.shuffle;
    }
  }

  // Get route color
  Color get routeColor {
    switch (routeType) {
      case RouteType.fastest:
        return Colors.blue;
      case RouteType.lowestPollution:
        return Colors.green;
      case RouteType.alternative:
        return Colors.orange;
    }
  }
}

// Navigation result model
class DirectionsResult {
  final List<RouteData> routes;
  
  DirectionsResult({
    required this.routes,
  });
  
  factory DirectionsResult.fromMap(Map<String, dynamic> map) {
    List<RouteData> routes = [];
    
    // Process all returned routes
    if (map['routes'] != null && map['routes'].isNotEmpty) {
      for (var routeData in map['routes']) {
        routes.add(RouteData.fromMap(routeData));
      }
    }
    
    return DirectionsResult(
      routes: routes,
    );
  }
}

// Data model for a single route
class RouteData {
  final List<LatLng> polylinePoints;
  final String distance;
  final String duration;
  final LatLng northeast;
  final LatLng southwest;
  
  RouteData({
    required this.polylinePoints,
    required this.distance,
    required this.duration,
    required this.northeast,
    required this.southwest,
  });
  
  factory RouteData.fromMap(Map<String, dynamic> map) {
    // Get boundaries
    final bounds = map['bounds'];
    final northeast = LatLng(
      bounds['northeast']['lat'],
      bounds['northeast']['lng'],
    );
    final southwest = LatLng(
      bounds['southwest']['lat'],
      bounds['southwest']['lng'],
    );
    
    // Get distance and time
    String distance = '';
    String duration = '';
    if (map['legs'] != null && map['legs'].isNotEmpty) {
      final leg = map['legs'][0];
      distance = leg['distance']['text'];
      duration = leg['duration']['text'];
    }
    
    // Decode polyline points
    final polylinePoints = PolylinePoints()
        .decodePolyline(map['overview_polyline']['points'])
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    
    return RouteData(
      polylinePoints: polylinePoints,
      distance: distance,
      duration: duration,
      northeast: northeast,
      southwest: southwest,
    );
  }
} 