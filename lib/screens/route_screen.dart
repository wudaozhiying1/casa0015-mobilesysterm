import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:math';
import '../services/directions_service.dart'; // Added Directions service import
import '../services/route_history_service.dart';
import '../models/place.dart';
import 'package:provider/provider.dart';
import '../services/air_quality_service.dart';

class RouteScreen extends StatefulWidget {
  final LatLng origin;
  final LatLng destination;
  final String destinationName;
  final bool startNavigation;
  final String? originName;
  final RouteOption? selectedRoute;  // Added selectedRoute parameter

  const RouteScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.destinationName,
    this.startNavigation = false,
    this.originName,
    this.selectedRoute,  // Added new parameter
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Loading status
  bool _isLoading = true;
  
  // Route information
  String _distance = "Calculating...";
  String _distanceValue = "Calculating...";
  String _routeDescription = "Getting route information...";
  String _routePath = "Loading...";
  
  // Navigation mode status
  bool _isNavigating = false;
  int _currentStep = 0;
  List<LatLng> _routePoints = [];
  Timer? _navigationTimer;
  
  // Estimated time for various transportation methods
  String _carTime = "Calculating...";
  String _busTime = "Calculating...";
  String _bikeTime = "Calculating...";

  @override
  void initState() {
    super.initState();
    print('RouteScreen initialized - Origin: ${widget.origin}, Destination: ${widget.destination}, Destination Name: ${widget.destinationName}');
    print('Selected route type: ${widget.selectedRoute?.routeType.toString() ?? "Not specified"}');
    
    // Add a short delay to ensure UI initialization is complete
    Future.delayed(Duration(milliseconds: 100), () {
      // First set the markers
      _setupMarkers();
      
      // If there's a pre-selected route, use it directly
      if (widget.selectedRoute != null) {
        _useSelectedRoute();
      } else {
        // Otherwise generate a new route
        _generateRoute();
      }
      
      // If navigation should start directly
      if (widget.startNavigation) {
        // Delay starting navigation to ensure the route has been loaded
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            _startNavigation();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _setupMarkers() {
    print('Setting route markers - Origin: ${widget.origin}, Destination: ${widget.destination}, Destination Name: ${widget.destinationName}');
    
    // Clear existing markers
    _markers.clear();
    
    // Origin marker - using passed location info
    _markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: widget.origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: _getOriginName()),
      ),
    );
    
    // Destination marker - ensure destination coordinates are valid and visible
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.destinationName),
        visible: true,
        zIndex: 2, // Ensure destination marker is on top
      ),
    );
    
    print('Markers setup complete - Number of markers: ${_markers.length}');
  }

  // Generate route using directions API
  Future<void> _generateRoute() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('Generating route from ${widget.origin.latitude},${widget.origin.longitude} to ${widget.destination.latitude},${widget.destination.longitude}');
      
      // Get route options using the DirectionsService to obtain multiple routes including pollution levels
      final airQualityService = Provider.of<AirQualityService>(context, listen: false);
      final routeOptions = await DirectionsService.getRouteOptions(
        origin: widget.origin,
        destination: widget.destination,
        airQualityService: airQualityService,
        travelMode: 'walking',
      );
      
      if (routeOptions.isNotEmpty) {
        // Select the fastest route by default
        final defaultRouteOption = routeOptions.firstWhere(
          (option) => option.routeType == RouteType.fastest,
          orElse: () => routeOptions.first
        );
        
        final route = defaultRouteOption.route;
        _routePoints = route.polylinePoints;
        
        // Add polylines for all available routes with different colors
        _polylines.clear();
        for (var option in routeOptions) {
          Color routeColor;
          int width = 5;
          List<PatternItem> patterns = [];
          
          switch (option.routeType) {
            case RouteType.fastest:
              routeColor = Colors.blue;
              width = option == defaultRouteOption ? 6 : 5;
              break;
            case RouteType.lowestPollution:
              routeColor = Colors.green;
              width = option == defaultRouteOption ? 6 : 5;
              break;
            case RouteType.alternative:
              routeColor = Colors.orange;
              width = option == defaultRouteOption ? 6 : 5;
              patterns = option == defaultRouteOption ? [] : [PatternItem.dash(20), PatternItem.gap(10)];
              break;
            default:
              routeColor = Colors.grey;
          }
          
          _polylines.add(
            Polyline(
              polylineId: PolylineId('route_${option.routeType.toString()}'),
              points: option.route.polylinePoints,
              color: routeColor,
              width: width,
              patterns: patterns,
            ),
          );
        }
        
        // Use the selected route for navigation information
        setState(() {
          _distanceValue = route.distance;
          _distance = route.duration;
          
          // Update times for other transportation methods
          _updateOtherTransportTimes(_distanceValue);
          
          // Set route description based on distance
          _setRouteDescription(_distanceValue);
          
          // Set path description with route type information
          String routeTypeDesc = "Fastest route";
          if (routeOptions.length > 1) {
            // Find the lowest pollution route for information display
            final lowestPollutionRoute = routeOptions.firstWhere(
              (option) => option.routeType == RouteType.lowestPollution,
              orElse: () => defaultRouteOption
            );
            
            // Add info about pollution levels available
            _routePath = "Multiple routes available - select fastest for now";
          } else {
            _routePath = "Via best available route";
          }
          
          _isLoading = false;
        });
        
        // Adjust map view to show the entire route
        if (_mapController != null) {
          try {
            print('Adjusting map view to show routes');
            await _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: route.southwest,
                  northeast: route.northeast,
                ),
                80, // Margin
              ),
            );
            print('Successfully adjusted map view');
          } catch (e) {
            print('Error adjusting map view: $e');
            // If unable to adjust to the entire route, at least focus on the origin
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(widget.origin, 14.0),
            );
          }
        } else {
          print('Map controller not initialized, unable to adjust view');
        }
      } else {
        print('No routes returned, falling back to simulated route');
        // If no routes were returned, fall back to generating simulated route
        _generateSimulatedRoute();
      }
    } catch (e) {
      print('Error getting routes data: $e');
      // Fall back to simulated route
      _generateSimulatedRoute();
    }
    
    // If route is still empty, use fallback method: create a simple direct line
    if (_routePoints.isEmpty) {
      print('Route points are still empty, create fallback direct line');
      _createFallbackDirectLine();
    }
    
    // Ensure route generated, try to adjust map view again
    Future.delayed(Duration(seconds: 1), () {
      if (mounted && _mapController != null) {
        print('Delay 1 second before trying to adjust map view again');
        try {
          // Ensure markers are visible
          if (_markers.length < 2) {
            print('Markers insufficient, resetting markers');
            _setupMarkers();
          }
          
          // If route is empty, try to generate fallback route again
          if (_routePoints.isEmpty) {
            print('Trying to generate fallback route again');
            _createFallbackDirectLine();
          }
          
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _getBoundsForRoute(),
              80, // Margin
            ),
          );
          print('Delayed map view adjustment successful');
        } catch (e) {
          print('Delayed map view adjustment failed: $e');
        }
      }
    });
  }
  
  // Analyze distance string and extract value
  double _extractDistanceValue(String distanceText) {
    // Example: "8.41 kilometers" or "8.41 km"
    final RegExp regExp = RegExp(r'(\d+(\.\d+)?)');
    final match = regExp.firstMatch(distanceText);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0') ?? 0.0;
    }
    return 0.0;
  }
  
  // Update times for other transportation methods
  void _updateOtherTransportTimes(String distanceText) {
    double distanceKm = _extractDistanceValue(distanceText);
    
    // If unable to parse distance, use default value
    if (distanceKm <= 0) {
      _carTime = "17 min";
      _busTime = "30 min";
      _bikeTime = "34 min";
      return;
    }
    
    // Calculate times for other transportation methods based on actual distance
    // Car: Approximate 30km/h city speed
    int drivingMinutes = max(1, (distanceKm / 30 * 60).round());
    _carTime = "$drivingMinutes min";
    
    // Bus: Approximate 15km/h plus waiting time
    int transitMinutes = max(5, (distanceKm / 15 * 60).round() + 5);
    _busTime = "$transitMinutes min";
    
    // Cycling: Approximate 15km/h
    int cyclingMinutes = max(1, (distanceKm / 15 * 60).round());
    _bikeTime = "$cyclingMinutes min";
  }
  
  // Set route description based on distance
  void _setRouteDescription(String distanceText) {
    double distanceKm = _extractDistanceValue(distanceText);
    
    if (distanceKm < 0.5) {
      _routeDescription = "Mostly flat roads";
    } else if (distanceKm < 2.0) {
      _routeDescription = "Medium walking distance";
    } else {
      _routeDescription = "Long walking distance";
    }
  }
  
  // Generate simulated route as fallback option
  void _generateSimulatedRoute() {
    print('Generating simulated route...');
    
    // Generate a series of points, simulating route
    final points = _generateLondonRoutePoints(widget.origin, widget.destination);
    _routePoints = points;
    
    // Create route
    _polylines.clear(); // Clear existing routes
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blue, // Use app theme color
        width: 6, // Increase line width
        patterns: [], // Use solid line
      ),
    );
    
    // Calculate simulated distance
    double distanceInKm = _calculateDistance(
      widget.origin.latitude, widget.origin.longitude, 
      widget.destination.latitude, widget.destination.longitude
    );
    
    // Update navigation information
    setState(() {
      _distanceValue = "${distanceInKm.toStringAsFixed(2)} km";
      
      // Walking time estimate (4km/h walking speed)
      int walkingMinutes = max(1, (distanceInKm / 4 * 60).round());
      _distance = "$walkingMinutes min";
      
      // Update times for other transportation methods
      _carTime = "${max(1, (distanceInKm / 30 * 60).round())} min";
      _busTime = "${max(5, (distanceInKm / 15 * 60).round() + 5)} min";
      _bikeTime = "${max(1, (distanceInKm / 15 * 60).round())} min";
      
      // Set route description based on distance
      if (distanceInKm < 0.5) {
        _routeDescription = "Short walking distance";
      } else if (distanceInKm < 2.0) {
        _routeDescription = "Medium walking distance";
      } else {
        _routeDescription = "Long walking distance";
      }
      
      // Set path description
      _routePath = "Simulated route";
      
      // Set loading complete
      _isLoading = false;
    });
    
    // Adjust map view to show the entire route
    if (_mapController != null) {
      try {
        print('Adjusting map view to show simulated route');
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _getBoundsForRoute(),
            80, // Margin
          ),
        );
      } catch (e) {
        print('Error adjusting map view: $e');
        // If unable to adjust to the entire route, at least focus on the origin
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(widget.origin, 14.0),
        );
      }
    }
  }
  
  // Generate London route points from UCL to UCL East Campus
  List<LatLng> _generateLondonRoutePoints(LatLng start, LatLng end) {
    // Create route points list
    List<LatLng> routePoints = [];
    
    // Add origin
    routePoints.add(start);
    
    // Add more intermediate points to simulate road route based on origin and destination distance and direction
    double bearing = _calculateBearing(start.latitude, start.longitude, end.latitude, end.longitude);
    double distance = _calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude);
    
    // If distance is far, add more intermediate points to simulate road bends
    int numberOfPoints = (distance * 5).round();
    numberOfPoints = min(30, max(10, numberOfPoints)); // At least 10 points, up to 30 points
    
    // Use Bezier curve algorithm to generate a more natural route
    _generateRoadLikePath(routePoints, start, end, numberOfPoints);
    
    // Ensure last point is destination
    if (routePoints.last != end) {
      routePoints.add(end);
    }
    
    return routePoints;
  }
  
  // Generate curve-like path similar to road
  void _generateRoadLikePath(List<LatLng> routePoints, LatLng start, LatLng end, int numberOfPoints) {
    // Determine route's general direction and intermediate control points
    // Use two control points to generate curve
    
    // Determine if route is mostly east-west or north-south
    bool isEastWest = (start.longitude - end.longitude).abs() > (start.latitude - end.latitude).abs();
    
    // Select control point offset method based on direction
    double controlLat1, controlLng1, controlLat2, controlLng2;
    
    // Random generator, for adding natural variations
    Random random = Random();
    
    if (isEastWest) {
      // East-west direction, control points have more changes in north-south direction
      double latVariation = (start.latitude - end.latitude).abs() * 0.4;
      
      // First control point
      controlLat1 = start.latitude + (random.nextDouble() * 2 - 1) * latVariation;
      controlLng1 = start.longitude + (end.longitude - start.longitude) * 0.3;
      
      // Second control point
      controlLat2 = end.latitude + (random.nextDouble() * 2 - 1) * latVariation;
      controlLng2 = start.longitude + (end.longitude - start.longitude) * 0.7;
    } else {
      // North-south direction, control points have more changes in east-west direction
      double lngVariation = (start.longitude - end.longitude).abs() * 0.4;
      
      // First control point
      controlLat1 = start.latitude + (end.latitude - start.latitude) * 0.3;
      controlLng1 = start.longitude + (random.nextDouble() * 2 - 1) * lngVariation;
      
      // Second control point
      controlLat2 = start.latitude + (end.latitude - start.latitude) * 0.7;
      controlLng2 = end.longitude + (random.nextDouble() * 2 - 1) * lngVariation;
    }
    
    // Determine control points for cubic Bezier curve
    LatLng control1 = LatLng(controlLat1, controlLng1);
    LatLng control2 = LatLng(controlLat2, controlLng2);
    
    // Generate points on curve
    for (int i = 1; i < numberOfPoints; i++) {
      double t = i / (numberOfPoints - 1);
      
      // Cubic Bezier curve formula B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
      double lat = _cubicBezier(start.latitude, control1.latitude, control2.latitude, end.latitude, t);
      double lng = _cubicBezier(start.longitude, control1.longitude, control2.longitude, end.longitude, t);
      
      // Add some random small variations to make route look more natural
      double microVariation = 0.0001 * (1 - t) * t * random.nextDouble();
      lat += (random.nextBool() ? 1 : -1) * microVariation;
      lng += (random.nextBool() ? 1 : -1) * microVariation;
      
      routePoints.add(LatLng(lat, lng));
    }
    
    // Add some road constraints
    _applyRoadConstraints(routePoints);
  }
  
  // Cubic Bezier curve formula calculation
  double _cubicBezier(double p0, double p1, double p2, double p3, double t) {
    return pow(1 - t, 3) * p0 +
           3 * pow(1 - t, 2) * t * p1 +
           3 * (1 - t) * pow(t, 2) * p2 +
           pow(t, 3) * p3;
  }
  
  // Apply road constraints to make route look more like road
  void _applyRoadConstraints(List<LatLng> points) {
    // Avoid jagged route, smooth continuous points
    for (int i = 1; i < points.length - 1; i++) {
      // Calculate midpoint of previous and next points
      double midLat = (points[i-1].latitude + points[i+1].latitude) / 2;
      double midLng = (points[i-1].longitude + points[i+1].longitude) / 2;
      
      // Offset current point towards midpoint, to achieve smoothing effect
      points[i] = LatLng(
        points[i].latitude * 0.8 + midLat * 0.2,
        points[i].longitude * 0.8 + midLng * 0.2
      );
    }
    
    // Can add more constraints, such as ensuring reasonable turn angles
  }
  
  // Calculate bearing (angle measured clockwise from north)
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final double dLon = _toRadians(lon2 - lon1);
    lat1 = _toRadians(lat1);
    lat2 = _toRadians(lat2);
    
    final double y = sin(dLon) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    
    final double radiansBearing = atan2(y, x);
    return (degrees(radiansBearing) + 360) % 360; // Convert to 0-360 range
  }
  
  // Convert radians to degrees
  double degrees(double radians) {
    return radians * 180 / pi;
  }

  void _startNavigation() {
    setState(() {
      _isNavigating = true;
    });
    
    // Start navigation simulation
    _navigationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_currentStep < _routePoints.length - 1) {
        setState(() {
          _currentStep++;
        });
        
        // Move camera to current position
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_routePoints[_currentStep], 17),
        );
      } else {
        // Reached destination
        timer.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have reached your destination')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.origin,
              zoom: 11.5, // Reduce zoom level to be able to see entire route
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              
              // Delay adjusting map view to ensure enough time to generate route
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  try {
                    // Adjust map view to show entire route
                    controller.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        _getBoundsForRoute(),
                        100, // Margin
                      ),
                    );
                  } catch (e) {
                    print('Error adjusting map view: $e');
                    // Backup plan: Just show origin and destination
                    controller.animateCamera(
                      CameraUpdate.newLatLngZoom(widget.origin, 14.0),
                    );
                  }
                }
              });
            },
          ),
          
          // Top navigation information bar
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, color: Colors.blue, size: 12),
                  const SizedBox(width: 8),
                  Text(
                    _getOriginName(),
                    style: TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.grey[600], size: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.destinationName,
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _distance,
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom route information card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _isNavigating 
                ? _buildNavigationBottomSheet() 
                : _buildRouteBottomSheet(),
          ),
          
          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
          
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 60, // Increase top margin to avoid overlap with top navigation bar
            left: 16,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
          
          // Compass button
          Positioned(
            bottom: _isNavigating ? 190 : 240,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'compass',
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 4,
              child: const Icon(Icons.navigation),
              onPressed: () {
                // Reset map orientation
                _mapController?.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: _isNavigating 
                          ? _routePoints[_currentStep]
                          : widget.origin,
                      zoom: 16.0,
                      bearing: 0,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteBottomSheet() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(
            'Walking',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.directions_walk, color: Colors.blue, size: 20),
              const SizedBox(width: 4),
              Text(
                _distance,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '($_distanceValue) $_routeDescription',
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            _routePath,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
          const SizedBox(height: 16),
          
          // Navigation button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.navigation, color: Colors.white),
                    label: const Text(
                      'Start',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue, // Use app theme color
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _startNavigation,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(Icons.share, color: Colors.grey[700]),
                  onPressed: () {
                    // Share functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share functionality not implemented')),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.grey[700]),
                  onPressed: () {
                    // More options functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('More options functionality not implemented')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Select different transportation method buttons
          Container(
            height: 70,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildTransportOption(Icons.directions_car, _carTime),
                _buildTransportOption(Icons.directions_bus, _busTime),
                _buildTransportOption(Icons.pedal_bike, _bikeTime),
                _buildTransportOption(Icons.directions_walk, _distance, false, true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBottomSheet() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.directions_walk, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Along Westfield Ave Southeast',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _distanceValue,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Arrival time',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  // Calculate arrival time - Add 126 minutes from current time
                  Text(
                    _calculateArrivalTime(126),
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Remaining time',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    _distance,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.close, color: Colors.grey[700]),
                onPressed: () {
                  _navigationTimer?.cancel();
                  setState(() {
                    _isNavigating = false;
                  });
                },
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.mic, color: Colors.grey[700]),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice control')),
                  );
                },
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.layers, color: Colors.grey[700]),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Layer selection')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransportOption(IconData icon, String time, [bool isFirst = false, bool isSelected = false]) {
    return Container(
      margin: EdgeInsets.only(left: isFirst ? 0 : 8, right: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.grey[600],
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              time,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  LatLngBounds _getBoundsForRoute() {
    double minLat = widget.origin.latitude;
    double maxLat = widget.origin.latitude;
    double minLng = widget.origin.longitude;
    double maxLng = widget.origin.longitude;
    
    // Consider destination
    if (widget.destination.latitude < minLat) minLat = widget.destination.latitude;
    if (widget.destination.latitude > maxLat) maxLat = widget.destination.latitude;
    if (widget.destination.longitude < minLng) minLng = widget.destination.longitude;
    if (widget.destination.longitude > maxLng) maxLng = widget.destination.longitude;
    
    // Consider all route points (if any)
    if (_routePoints.isNotEmpty) {
      for (final point in _routePoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }
    
    // Ensure boundary has some width and height
    double latDelta = maxLat - minLat;
    double lngDelta = maxLng - minLng;
    
    // If boundary is too small, add some padding
    if (latDelta < 0.005) { // Approximately 500 meters
      double padding = (0.005 - latDelta) / 2;
      minLat -= padding;
      maxLat += padding;
    }
    
    if (lngDelta < 0.005) {
      double padding = (0.005 - lngDelta) / 2;
      minLng -= padding;
      maxLng += padding;
    }
    
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Calculate arrival time
  String _calculateArrivalTime(int minutesToAdd) {
    final now = DateTime.now();
    final arrivalTime = now.add(Duration(minutes: minutesToAdd));
    return '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}';
  }

  // Get origin name, show "My location" if current location
  String _getOriginName() {
    // If originName is provided, use it; otherwise use "My location"
    return widget.originName ?? "My location";
  }
  
  // Calculate distance between two points (kilometers)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius, in kilometers
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
                    cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
                    sin(dLon / 2) * sin(dLon / 2);
                    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
  
  // Convert degrees to radians
  double _toRadians(double degree) {
    return degree * pi / 180;
  }

  // Create fallback direct line, ensure there's always a route to display
  void _createFallbackDirectLine() {
    print('Creating fallback direct line - from ${widget.origin} to ${widget.destination}');
    
    // Create direct line (origin and destination)
    _routePoints = [widget.origin, widget.destination];
    
    // Calculate straight distance
    double distanceInKm = _calculateDistance(
      widget.origin.latitude, widget.origin.longitude,
      widget.destination.latitude, widget.destination.longitude
    );
    
    // Create route
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('fallback_route'),
        points: _routePoints,
        color: Colors.red, // Use red to distinguish fallback route
        width: 5,
        patterns: [PatternItem.dash(10), PatternItem.gap(5)], // Use dashed line to indicate fallback route
      ),
    );
    
    // Update UI state
    setState(() {
      _distanceValue = "${distanceInKm.toStringAsFixed(2)} km";
      _distance = "${(distanceInKm / 4 * 60).round()} min"; // Calculate walking time based on 4km/h
      _routeDescription = "Straight distance";
      _routePath = "Fallback route";
      _isLoading = false;
    });
    
    print('Fallback route created');
  }

  // Use selected route
  void _useSelectedRoute() {
    print('Using pre-selected route: ${widget.selectedRoute?.routeType.toString()}');
    
    if (widget.selectedRoute == null) {
      print('No selected route, fall back to generating new route');
      _generateRoute();
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    // Use selected route data
    final route = widget.selectedRoute!.route;
    _routePoints = route.polylinePoints;
    
    // Set color based on route type
    Color routeColor;
    switch (widget.selectedRoute!.routeType) {
      case RouteType.fastest:
        routeColor = Colors.blue;
        break;
      case RouteType.lowestPollution:
        routeColor = Colors.green;
        break;
      case RouteType.alternative:
        routeColor = Colors.orange;
        break;
      default:
        routeColor = const Color(0xFF00B0FF);
    }
    
    // Create route
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.polylinePoints,
        color: routeColor,
        width: 6,
        patterns: [], // Use solid line
      ),
    );
    
    // Use selected route distance and time information
    _distanceValue = route.distance;
    _distance = route.duration;
    
    // Update times for other transportation methods
    _updateOtherTransportTimes(_distanceValue);
    
    // Set route description based on distance
    _setRouteDescription(_distanceValue);
    
    // Add route type to description
    String routeTypeDesc;
    switch (widget.selectedRoute!.routeType) {
      case RouteType.fastest:
        routeTypeDesc = "Fastest route";
        break;
      case RouteType.lowestPollution:
        routeTypeDesc = "Lowest pollution route (AQI: ${widget.selectedRoute!.avgAirQuality.toStringAsFixed(1)})";
        break;
      case RouteType.alternative:
        routeTypeDesc = "Alternative route";
        break;
      default:
        routeTypeDesc = "";
    }
    
    if (routeTypeDesc.isNotEmpty) {
      _routePath = "$routeTypeDesc, estimated $_distance";
    } else {
      _routePath = "Estimated $_distance";
    }
    
    setState(() {
      _isLoading = false;
    });
    
    // Adjust map view to show the entire route
    if (_mapController != null) {
      try {
        print('Adjusting map view to show selected route');
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: route.southwest,
              northeast: route.northeast,
            ),
            80, // Margin
          ),
        );
        print('Successfully adjusted map view');
      } catch (e) {
        print('Error adjusting map view: $e');
        // If unable to adjust to the entire route, at least focus on the origin
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(widget.origin, 14.0),
        );
      }
    } else {
      print('Map controller not initialized, unable to adjust view');
    }
    
    // Save to route history
    String routeType;
    switch (widget.selectedRoute!.routeType) {
      case RouteType.fastest:
        routeType = 'Fastest route';
        break;
      case RouteType.lowestPollution:
        routeType = 'Lowest pollution';
        break;
      case RouteType.alternative:
        routeType = 'Alternative route';
        break;
      default:
        routeType = 'Standard route';
    }
    _saveRouteHistory(routeType);
  }
  
  // Save route history
  void _saveRouteHistory(String routeType) {
    // Only save route history if user is logged in
    if (!RouteHistoryService.isUserLoggedIn) {
      print('User not logged in, unable to save route history');
      return;
    }
    
    // Build origin and destination Place objects
    final origin = Place(
      placeId: 'origin_${widget.origin.latitude}_${widget.origin.longitude}',
      name: _getOriginName(),
      address: _getOriginAddress(),
      location: widget.origin,
      formattedAddress: _getOriginAddress(),
    );
    
    final destination = Place(
      placeId: 'destination_${widget.destination.latitude}_${widget.destination.longitude}',
      name: widget.destinationName,
      address: widget.destinationName, // Use name if no detailed address
      location: widget.destination,
      formattedAddress: widget.destinationName,
    );
    
    // Save to route history
    RouteHistoryService.addRouteHistory(
      origin: origin,
      destination: destination,
      distance: _distanceValue,
      duration: _distance,
      routeType: routeType,
    );
    
    print('Route history saved: ${origin.name} to ${destination.name}, Distance: $_distanceValue, Time: $_distance');
  }
  
  // Get origin address
  String _getOriginAddress() {
    return widget.originName ?? 'Current location';
  }

  // Set air quality color based on AQI
  Color _getAqiColor(double aqi) {
    if (aqi <= 50) return Colors.green;
    if (aqi <= 100) return Colors.yellow.shade700;
    if (aqi <= 150) return Colors.orange;
    if (aqi <= 200) return Colors.red;
    if (aqi <= 300) return Colors.purple;
    return Colors.brown;
  }
} 