import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'dart:math' show pi, cos, sin, sqrt, pow, min, max, abs;
import '../models/place.dart';
import '../services/location_service.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../services/air_quality_service.dart';
import 'route_screen.dart';
import '../widgets/air_quality_overlay.dart';
import 'place_details_screen.dart';

// Handle navigation from details page, receiving start and end parameters
class RoutePlannerScreenWithParams extends StatefulWidget {
  final Place? initialStartPlace;
  final Place? initialEndPlace;
  
  const RoutePlannerScreenWithParams({
    Key? key,
    this.initialStartPlace,
    this.initialEndPlace,
  }) : super(key: key);
  
  @override
  _RoutePlannerScreenWithParamsState createState() => _RoutePlannerScreenWithParamsState();
}

class _RoutePlannerScreenWithParamsState extends State<RoutePlannerScreenWithParams> {
  @override
  Widget build(BuildContext context) {
    // Pass start and end parameters to RoutePlannerScreen
    return RoutePlannerScreen(
      initialStartPlace: widget.initialStartPlace,
      initialEndPlace: widget.initialEndPlace,
    );
  }
}

class RoutePlannerScreen extends StatefulWidget {
  final Place? initialEndPlace;
  final Place? initialStartPlace;
  
  const RoutePlannerScreen({
    super.key, 
    this.initialEndPlace,
    this.initialStartPlace,
  });

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final TextEditingController _startPointController = TextEditingController();
  final TextEditingController _endPointController = TextEditingController();
  
  Place? _selectedStartPlace;
  Place? _selectedEndPlace;
  
  List<Place> _startSearchResults = [];
  List<Place> _endSearchResults = [];
  
  bool _isSearchingStart = false;
  bool _isSearchingEnd = false;
  
  bool _showStartResults = false;
  bool _showEndResults = false;
  
  bool _useCurrentLocationAsStart = true;
  bool _isLoading = false;
  
  // Add map-related variables
  GoogleMapController? _mapController;
  bool _showMap = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  // Add route information variables
  String _routeDistance = '';
  String _routeDuration = '';
  bool _isRoutePlanned = false;
  
  // History - store recently used places
  final List<Place> _recentPlaces = [];

  // Add heatmap-related variables
  bool _showAirQualityHeatmap = false;
  List<AirQualityPoint> _airQualityPoints = [];
  Set<Circle> _airQualityCircles = {};
  late AirQualityService _airQualityService;

  // Add route options list
  List<RouteOption> _routeOptions = [];
  RouteOption? _selectedRouteOption;
  
  // Add flag to indicate if map should be updated immediately after controller initialization
  bool _shouldUpdateMapOnInit = false;

  @override
  void initState() {
    super.initState();
    // Initialize air quality service
    _airQualityService = Provider.of<AirQualityService>(context, listen: false);
    
    // Check if there is an initial starting point
    if (widget.initialStartPlace != null) {
      setState(() {
        _selectedStartPlace = widget.initialStartPlace;
        _startPointController.text = widget.initialStartPlace!.name;
        _useCurrentLocationAsStart = widget.initialStartPlace!.placeId == 'current_location';
      });
      
      print('Using preset starting point: ${widget.initialStartPlace!.name}');
    } else {
      // Try to get current location as default starting point
      _initializeStartLocation();
    }
    
    // Set initial destination (if any)
    if (widget.initialEndPlace != null) {
      setState(() {
        _selectedEndPlace = widget.initialEndPlace;
        _endPointController.text = widget.initialEndPlace!.name;
      });
      
      print('Using preset destination: ${widget.initialEndPlace!.name}');
    }
    
    // If both start and end points are set, update the map
    if (_selectedStartPlace != null && _selectedEndPlace != null) {
      // Update map after UI rendering is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('Preparing to update map to show route...');
        _updateMapIfReady();
      });
    }
    
    // Add some mock history places
    _addMockHistoryPlaces();
  }
  
  // Add mock history data
  void _addMockHistoryPlaces() {
    // If we have some common places, add them as history
    _recentPlaces.add(
      Place(
        placeId: 'history_1',
        name: 'University College London',
        address: 'Gower St, London WC1E 6BT',
        location: const LatLng(51.5246, -0.1339),
      ),
    );
    
    _recentPlaces.add(
      Place(
        placeId: 'history_2',
        name: 'British Museum',
        address: 'Great Russell St, London WC1B 3DG',
        location: const LatLng(51.5194, -0.1269),
      ),
    );
    
    _recentPlaces.add(
      Place(
        placeId: 'history_3',
        name: 'Buckingham Palace',
        address: 'London SW1A 1AA',
        location: const LatLng(51.5014, -0.1419),
      ),
    );
  }
  
  Future<void> _initializeStartLocation() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    
    // Check if location information is already available
    if (locationService.currentPosition != null) {
      setState(() {
        _startPointController.text = 'Your Location';
        
        // Create a Place object representing the current location
        _selectedStartPlace = Place(
          placeId: 'current_location',
          name: 'Your Location',
          address: 'Current Location',
          location: LatLng(
            locationService.currentPosition!.latitude,
            locationService.currentPosition!.longitude,
          ),
        );
        
        _useCurrentLocationAsStart = true;
      });
      
      print('Using existing location information: ${locationService.currentPosition!.latitude}, ${locationService.currentPosition!.longitude}');
      return; // Already have location information, return directly
    }
    
    // Try to get user location
    try {
      print('Trying to get user location...');
      await locationService.getCurrentLocation();
      
      if (locationService.currentPosition != null) {
        setState(() {
          _startPointController.text = 'Your Location';
          
          // Create a Place object representing the current location
          _selectedStartPlace = Place(
            placeId: 'current_location',
            name: 'Your Location',
            address: 'Current Location',
            location: LatLng(
              locationService.currentPosition!.latitude,
              locationService.currentPosition!.longitude,
            ),
          );
          
          _useCurrentLocationAsStart = true;
        });
        
        print('Successfully got user location: ${locationService.currentPosition!.latitude}, ${locationService.currentPosition!.longitude}');
      } else {
        print('Location service returned successfully, but no location was obtained');
        setState(() {
          _useCurrentLocationAsStart = false;
        });
      }
    } catch (e) {
      print('Failed to get user location: $e');
      setState(() {
        _useCurrentLocationAsStart = false;
      });
      
      // Don't set a default location, let the user choose a starting point manually
    }
  }

  @override
  void dispose() {
    _startPointController.dispose();
    _endPointController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _searchStartPlaces(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearchingStart = true;
      _showStartResults = true;
      _useCurrentLocationAsStart = false;
    });
    
    try {
      final results = await GeocodingService.searchPlaces(query);
      setState(() {
        _startSearchResults = results;
        _isSearchingStart = false;
      });
      debugPrint('Found ${results.length} starting locations');
    } catch (e) {
      debugPrint('Error searching for starting point: $e');
      setState(() {
        _isSearchingStart = false;
      });
    }
  }

  void _searchEndPlaces(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isSearchingEnd = true;
      _showEndResults = true;
    });
    
    try {
      final results = await GeocodingService.searchPlaces(query);
      setState(() {
        _endSearchResults = results;
        _isSearchingEnd = false;
      });
      debugPrint('Found ${results.length} destination locations');
    } catch (e) {
      debugPrint('Error searching for destination: $e');
      setState(() {
        _isSearchingEnd = false;
      });
    }
  }

  void _selectStartPlace(Place place) {
    setState(() {
      _selectedStartPlace = place;
      _startPointController.text = place.name;
      _showStartResults = false;
      _useCurrentLocationAsStart = false;
      
      // Add the selected place to history
      _addToRecentPlaces(place);
      
      // Update map
      _updateMapIfReady();
    });
    FocusScope.of(context).unfocus();
  }

  void _selectEndPlace(Place place) {
    setState(() {
      _selectedEndPlace = place;
      _endPointController.text = place.name;
      _showEndResults = false;
      
      // Add the selected place to history
      _addToRecentPlaces(place);
      
      // Update map
      _updateMapIfReady();
    });
    FocusScope.of(context).unfocus();
  }
  
  // Add place to history
  void _addToRecentPlaces(Place place) {
    // If already exists, remove the old entry
    _recentPlaces.removeWhere((p) => p.placeId == place.placeId);
    
    // Add to the front
    _recentPlaces.insert(0, place);
    
    // Keep the record count within a reasonable range
    if (_recentPlaces.length > 10) {
      _recentPlaces.removeLast();
    }
  }

  void _swapStartAndEndPlaces() {
    if (_selectedStartPlace != null && _selectedEndPlace != null) {
      final tempPlace = _selectedStartPlace;
      final tempText = _startPointController.text;
      final wasCurrentLocation = _useCurrentLocationAsStart;
      
      setState(() {
        _selectedStartPlace = _selectedEndPlace;
        _startPointController.text = _endPointController.text;
        
        _selectedEndPlace = tempPlace;
        _endPointController.text = tempText;
        
        _useCurrentLocationAsStart = false; // No longer use current location as starting point after swap
        
        // Update map
        _updateMapIfReady();
      });
    }
  }

  void _resetToCurrentLocation() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    if (locationService.currentPosition != null) {
      setState(() {
        _startPointController.text = 'Your Location';
        _selectedStartPlace = Place(
          placeId: 'current_location',
          name: 'Your Location',
          address: 'Current Location',
          location: LatLng(
            locationService.currentPosition!.latitude,
            locationService.currentPosition!.longitude,
          ),
        );
        _useCurrentLocationAsStart = true;
        _showStartResults = false;
      });
    } else {
      // Try to get location
      try {
        await locationService.getCurrentLocation();
        if (locationService.currentPosition != null) {
          setState(() {
            _startPointController.text = 'Your Location';
            _selectedStartPlace = Place(
              placeId: 'current_location',
              name: 'Your Location',
              address: 'Current Location',
              location: LatLng(
                locationService.currentPosition!.latitude,
                locationService.currentPosition!.longitude,
              ),
            );
            _useCurrentLocationAsStart = true;
            _showStartResults = false;
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get current location, please enter a starting point manually')),
        );
      }
    }
  }
  
  // Open the starting point selection screen
  void _openStartPointSelectionScreen() async {
    // Show location selection screen and receive the selected location
    final selectedPlace = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _LocationSelectionScreen(
          title: 'Select Starting Point',
          initialLocation: _selectedStartPlace,
          recentPlaces: _recentPlaces,
          onLocationSelected: (place) {
            // Select place as starting point
            setState(() {
              _selectedStartPlace = place;
              _startPointController.text = place.name;
              _useCurrentLocationAsStart = place.placeId == 'current_location';
              _addToRecentPlaces(place);
            });
            
            // Update map immediately
            _updateMapIfReady();
          },
        ),
      ),
    );
  }
  
  // Open the destination selection screen
  void _openEndPointSelectionScreen() async {
    // Show location selection screen and receive the selected location
    final selectedPlace = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _LocationSelectionScreen(
          title: 'Select Destination',
          initialLocation: _selectedEndPlace,
          recentPlaces: _recentPlaces,
          onLocationSelected: (place) {
            // Select place as destination
            setState(() {
              _selectedEndPlace = place;
              _endPointController.text = place.name;
              _addToRecentPlaces(place);
            });
            
            // Update map immediately
            _updateMapIfReady();
          },
        ),
      ),
    );
  }

  void _startNavigation() {
    if (_selectedStartPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a starting point')),
      );
      return;
    }
    
    if (_selectedEndPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }
    
    if (_selectedRouteOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please plan a route first')),
      );
      return;
    }
    
    // Confirm starting point information
    LatLng startLocation = _selectedStartPlace!.location;
    String startName = _selectedStartPlace!.name;
    
    // If using current location, get the latest position
    if (_useCurrentLocationAsStart) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      if (locationService.currentPosition != null) {
        startLocation = LatLng(
          locationService.currentPosition!.latitude,
          locationService.currentPosition!.longitude,
        );
        startName = 'Your Location';
      }
    }
    
    debugPrint('Start navigation - from ${startLocation.latitude},${startLocation.longitude} to ${_selectedEndPlace!.location.latitude},${_selectedEndPlace!.location.longitude}');
    debugPrint('Using route type: ${_selectedRouteOption!.routeType.toString()}');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteScreen(
          origin: startLocation,
          destination: _selectedEndPlace!.location,
          destinationName: _selectedEndPlace!.name,
          originName: startName,
          // Pass the selected route option
          selectedRoute: _selectedRouteOption,
          // Don't start navigation mode immediately, allow time for the route to load
          startNavigation: false,
        ),
      ),
    );
  }

  // Update map and draw route
  void _updateMapIfReady() async {
    if (_selectedStartPlace != null && _selectedEndPlace != null) {
      setState(() {
        _showMap = true;
        _polylines.clear();
        _markers.clear();
        _routeOptions.clear();
        _selectedRouteOption = null;
        
        // Add starting point marker
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: _selectedStartPlace!.location,
            infoWindow: InfoWindow(
              title: _selectedStartPlace!.name,
              snippet: _selectedStartPlace!.address,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
        
        // Add destination marker
        _markers.add(
          Marker(
            markerId: const MarkerId('end'),
            position: _selectedEndPlace!.location,
            infoWindow: InfoWindow(
              title: _selectedEndPlace!.name,
              snippet: _selectedEndPlace!.address,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
        
        // Show loading indicator
        _isRoutePlanned = false; // Set to false to show loading state
        _isLoading = true;
      });
      
      // If the map controller is not initialized yet, wait for it
      if (_mapController == null) {
        // Set a flag to update immediately after map initialization
        _shouldUpdateMapOnInit = true;
        return;
      }
      
      try {
        // Use service to get real route options
        final routeOptions = await DirectionsService.getRouteOptions(
          origin: _selectedStartPlace!.location,
          destination: _selectedEndPlace!.location,
          airQualityService: _airQualityService,
          travelMode: 'walking', // Walking mode
        );
        
        if (routeOptions.isNotEmpty) {
          if (mounted) {
            setState(() {
              _routeOptions = routeOptions;
              _selectedRouteOption = routeOptions.first; // Default to the first route
              
              // Add polyline and bubble marker for each route
              for (var i = 0; i < routeOptions.length; i++) {
                var option = routeOptions[i];
                
                // Set color and label based on route type
                Color routeColor = option.routeColor;
                String routeLabel;
                
                switch (option.routeType) {
                  case RouteType.fastest:
                    routeLabel = 'Fastest Route';
                    break;
                  case RouteType.lowestPollution:
                    routeLabel = 'Best Air Quality';
                    break;
                  case RouteType.alternative:
                    routeLabel = 'Alternative Route';
                    break;
                  default:
                    routeLabel = 'Route ${i+1}';
                }
                
                // Add route
                _polylines.add(
                  Polyline(
                    polylineId: PolylineId('route_${option.routeType.toString()}'),
                    points: option.route.polylinePoints,
                    color: routeColor,
                    width: option == _selectedRouteOption ? 6 : 4, // Selected route has greater width
                    patterns: option == _selectedRouteOption 
                        ? [] // Selected route uses solid line
                        : [], // All routes use solid lines, but with different colors
                  ),
                );
                
                // Calculate midpoint position for bubble
                if (option.route.polylinePoints.length > 1) {
                  int midIndex = option.route.polylinePoints.length ~/ 2;
                  LatLng bubblePosition = option.route.polylinePoints[midIndex];
                  
                  // Add bubble marker
                  _markers.add(
                    Marker(
                      markerId: MarkerId('route_bubble_${option.routeType.toString()}'),
                      position: bubblePosition,
                      icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHueForRoute(option.routeType)),
                      alpha: 0.7, // Translucent
                      infoWindow: InfoWindow(
                        title: routeLabel,
                        snippet: option.routeType == RouteType.lowestPollution 
                            ? 'AQI: ${option.avgAirQuality.toStringAsFixed(1)}' 
                            : '${option.route.distance} • ${option.route.duration}',
                      ),
                    ),
                  );
                }
              }
              
              // Update route information
              _routeDistance = _selectedRouteOption!.route.distance;
              _routeDuration = _selectedRouteOption!.route.duration;
              _isRoutePlanned = true;
              _isLoading = false;
              
              // Adjust map view to show the entire route
              _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(
                  LatLngBounds(
                    southwest: _selectedRouteOption!.route.southwest,
                    northeast: _selectedRouteOption!.route.northeast,
                  ),
                  50, // Padding
                ),
              );
            });
          }
        } else {
          // Show error message when API call returns empty
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to get route information, please try again later')),
            );
            
            setState(() {
              _isRoutePlanned = false;
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Error getting navigation route: $e');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error getting route, please try again later')),
          );
          
          setState(() {
            _isRoutePlanned = false;
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _showMap = false;
      });
    }
  }
  
  // Generate simulated multiple routes
  void _generateSimulatedMultiRoutes() {
    if (_selectedStartPlace == null || _selectedEndPlace == null) return;
    
    setState(() {
      _polylines.clear();
      _routeOptions.clear();
      
      LatLng start = _selectedStartPlace!.location;
      LatLng end = _selectedEndPlace!.location;
      
      // Generate fastest route (slightly curved straight line)
      List<LatLng> fastestRoutePoints = _generateSimulatedRoutePath(start, end, variationFactor: 0.1);
      
      // Generate lowest pollution route (detour through green areas)
      List<LatLng> lowestPollutionRoutePoints = _generateSimulatedRoutePath(start, end, variationFactor: 0.3, offset: 0.008);
      
      // Generate alternative route (another optional route)
      List<LatLng> alternativeRoutePoints = _generateSimulatedRoutePath(start, end, variationFactor: 0.2, offset: -0.008);
      
      // Calculate bounds
      LatLngBounds bounds = _calculateLatLngBounds([
        ...fastestRoutePoints,
        ...lowestPollutionRoutePoints,
        ...alternativeRoutePoints,
      ]);
      
      // Create simulated route options
      _routeOptions = [
        RouteOption(
          route: RouteData(
            polylinePoints: fastestRoutePoints,
            distance: '${_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude).toStringAsFixed(1)} km',
            duration: '${(_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude) / 5 * 60).round()} min',
            northeast: bounds.northeast,
            southwest: bounds.southwest,
          ),
          avgAirQuality: 75.0, // Simulated value
          routeType: RouteType.fastest,
        ),
        RouteOption(
          route: RouteData(
            polylinePoints: lowestPollutionRoutePoints,
            distance: '${(_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude) * 1.2).toStringAsFixed(1)} km',
            duration: '${(_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude) * 1.2 / 5 * 60).round()} min',
            northeast: bounds.northeast,
            southwest: bounds.southwest,
          ),
          avgAirQuality: 45.0, // Simulated value - better air quality
          routeType: RouteType.lowestPollution,
        ),
        RouteOption(
          route: RouteData(
            polylinePoints: alternativeRoutePoints,
            distance: '${(_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude) * 1.1).toStringAsFixed(1)} km',
            duration: '${(_calculateDistance(start.latitude, start.longitude, end.latitude, end.longitude) * 1.1 / 5 * 60).round()} min',
            northeast: bounds.northeast,
            southwest: bounds.southwest,
          ),
          avgAirQuality: 65.0, // Simulated value
          routeType: RouteType.alternative,
        ),
      ];
      
      _selectedRouteOption = _routeOptions.first;
      
      // Add polyline and bubble marker for each route
      for (var i = 0; i < _routeOptions.length; i++) {
        var option = _routeOptions[i];
        
        // Set different colors but keep the same line style
        Color routeColor;
        String routeLabel;
        
        switch (option.routeType) {
          case RouteType.fastest:
            routeColor = Colors.blue;
            routeLabel = 'Fastest Route';
            break;
          case RouteType.lowestPollution:
            routeColor = Colors.green;
            routeLabel = 'Best Air Quality';
            break;
          case RouteType.alternative:
            routeColor = Colors.orange;
            routeLabel = 'Alternative Route';
            break;
          default:
            routeColor = Colors.grey;
            routeLabel = 'Route ${i+1}';
        }
        
        // Add route
        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_${option.routeType.toString()}'),
            points: option.route.polylinePoints,
            color: routeColor,
            width: option == _selectedRouteOption ? 6 : 4, // Selected route has greater width
            patterns: option == _selectedRouteOption 
                ? [] 
                : [],
          ),
        );
        
        // Calculate midpoint position for bubble
        if (option.route.polylinePoints.length > 1) {
          int midIndex = option.route.polylinePoints.length ~/ 2;
          LatLng bubblePosition = option.route.polylinePoints[midIndex];
          
          // Add bubble marker
          _markers.add(
            Marker(
              markerId: MarkerId('route_bubble_${option.routeType.toString()}'),
              position: bubblePosition,
              icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHueForRoute(option.routeType)),
              alpha: 0.7, // Translucent
              infoWindow: InfoWindow(
                title: routeLabel,
                snippet: option.routeType == RouteType.lowestPollution 
                    ? 'AQI: ${option.avgAirQuality.toStringAsFixed(1)}' 
                    : '${option.route.distance} • ${option.route.duration}',
              ),
            ),
          );
        }
      }
      
      // Update route information
      _routeDistance = _selectedRouteOption!.route.distance;
      _routeDuration = _selectedRouteOption!.route.duration;
      
      // Adjust map to fit all routes
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 50),
        );
      }
    });
  }
  
  // Generate simulated path points
  List<LatLng> _generateSimulatedRoutePath(LatLng start, LatLng end, {double variationFactor = 0.2, double offset = 0.0}) {
    final List<LatLng> routePoints = [];
    routePoints.add(start);
    
    final Random random = Random();
    
    // Calculate midpoint between start and end
    double midLat = (start.latitude + end.latitude) / 2;
    double midLng = (start.longitude + end.longitude) / 2;
    
    // Add an offset perpendicular to the straight line direction
    // Calculate direction vector of the straight line
    double dx = end.longitude - start.longitude;
    double dy = end.latitude - start.latitude;
    
    // Perpendicular direction unit vector (rotated 90 degrees)
    double perpDx = -dy;
    double perpDy = dx;
    
    // Calculate perpendicular vector length
    double perpLength = sqrt(perpDx * perpDx + perpDy * perpDy);
    
    // Normalize perpendicular vector
    if (perpLength > 0) {
      perpDx /= perpLength;
      perpDy /= perpLength;
    }
    
    // Add fixed offset
    midLat += perpDy * offset;
    midLng += perpDx * offset;
    
    // Add some random variation
    midLat += (random.nextDouble() - 0.5) * variationFactor * (end.latitude - start.latitude).abs();
    midLng += (random.nextDouble() - 0.5) * variationFactor * (end.longitude - start.longitude).abs();
    
    // Add intermediate point
    routePoints.add(LatLng(midLat, midLng));
    
    // Add end point
    routePoints.add(end);
    
    return routePoints;
  }
  
  // Calculate bounds of a set of points
  LatLngBounds _calculateLatLngBounds(List<LatLng> points) {
    if (points.isEmpty) {
      // Return a default value or throw an exception
      return LatLngBounds(
        southwest: const LatLng(0, 0),
        northeast: const LatLng(0, 0),
      );
    }
    
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
  
  // Select route option
  void _selectRouteOption(RouteOption option) {
    setState(() {
      _selectedRouteOption = option;
      
      // Update route information
      _routeDistance = option.route.distance;
      _routeDuration = option.route.duration;
      
      // Refresh all route styles
      _polylines.clear();
      for (var routeOption in _routeOptions) {
        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_${routeOption.routeType.toString()}'),
            points: routeOption.route.polylinePoints,
            color: routeOption.routeColor,
            width: routeOption == _selectedRouteOption ? 6 : 3,
            patterns: routeOption == _selectedRouteOption 
                ? [] 
                : [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map always displays as fullscreen
          Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selectedStartPlace?.location ?? const LatLng(39.9042, 116.4074), // Default to Beijing
                  zoom: 14.0,
                ),
                onMapCreated: (controller) {
                  setState(() {
                    _mapController = controller;
                    debugPrint('Map controller created');
                  });
                  // Check if map needs to be updated immediately
                  if (_shouldUpdateMapOnInit) {
                    _shouldUpdateMapOnInit = false;
                    _updateMapIfReady();
                  }
                  // Only adjust map bounds when both locations are selected
                  else if (_selectedStartPlace != null && _selectedEndPlace != null) {
                    _fitMapToBounds();
                  }
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
                // Configure map style to make circles more visible
                mapType: MapType.normal,
                liteModeEnabled: false, // Disable lite mode to ensure advanced rendering features are available
              ),
              
              // Add air quality overlay
              if (_showAirQualityHeatmap && _airQualityService.heatmapData.isNotEmpty)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: AirQualityOverlay(
                      data: _airQualityService.heatmapData,
                      opacity: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          
          // Back button
          Positioned(
            top: 40,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          
          // Map control buttons
          _buildMapControls(),
          
          // Bottom half-screen route planning panel
          _buildRoutePanel(),
          
          // Loading indicator
          if (_isLoading)
            const Center(
              child: Card(
                color: Colors.white,
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 16),
                      Text('Getting location...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Build bottom route planning panel
  Widget _buildRoutePanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.4, // Initial height is 40% of screen
      minChildSize: 0.2, // Minimum height is 20% of screen
      maxChildSize: 0.6, // Maximum height is 60% of screen
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top drag indicator
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Route Planning',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Starting point input
                  _buildLocationInput(
                    icon: _useCurrentLocationAsStart ? Icons.my_location : Icons.location_on,
                    iconColor: _useCurrentLocationAsStart ? Colors.blue : Colors.red,
                    label: _selectedStartPlace?.name ?? 'Select starting point',
                    address: _selectedStartPlace?.address ?? '',
                    onTap: _openStartPointSelectionScreen,
                  ),
                  
                  // Swap button
                  Center(
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.swap_vert, color: Colors.blue),
                      ),
                      onPressed: _swapStartAndEndPlaces,
                      tooltip: 'Swap starting point and destination',
                    ),
                  ),
                  
                  // Destination input
                  _buildLocationInput(
                    icon: Icons.location_on,
                    iconColor: Colors.red,
                    label: _selectedEndPlace?.name ?? 'Select destination',
                    address: _selectedEndPlace?.address ?? '',
                    onTap: _openEndPointSelectionScreen,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Recent places
                  if (!_showMap && _recentPlaces.isNotEmpty)
                    _buildRecentPlaces(),
                  
                  // Route information
                  if (_showMap && _selectedStartPlace != null && _selectedEndPlace != null)
                    _buildRouteInfo(),
                  
                  const SizedBox(height: 16),
                  
                  // Start navigation button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions),
                      label: const Text('Start Navigation'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _selectedStartPlace != null && _selectedEndPlace != null
                        ? _startNavigation
                        : null,
                    ),
                  ),
                  
                  // Add extra bottom padding to avoid overflow
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Build location input widget
  Widget _buildLocationInput({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String address,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (address.isNotEmpty)
                    Text(
                      address,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
  
  // Build recent places list
  Widget _buildRecentPlaces() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Places',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recentPlaces.length > 3 ? 3 : _recentPlaces.length,
          itemBuilder: (context, index) {
            final place = _recentPlaces[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: Text(place.name),
              subtitle: Text(
                place.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                // Decide whether to set as start or destination based on current focus
                if (_selectedEndPlace == null) {
                  _selectEndPlace(place);
                } else {
                  _selectStartPlace(place);
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.subdirectory_arrow_left, size: 20),
                    onPressed: () => _selectStartPlace(place),
                    tooltip: 'Set as starting point',
                  ),
                  IconButton(
                    icon: const Icon(Icons.subdirectory_arrow_right, size: 20),
                    onPressed: () => _selectEndPlace(place),
                    tooltip: 'Set as destination',
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
  
  // Build route information
  Widget _buildRouteInfo() {
    // If there is API-returned distance and time information, use it first
    final String displayDistance = _routeDistance.isNotEmpty 
        ? _routeDistance 
        : '${_calculateDistance(_selectedStartPlace!.location.latitude, _selectedStartPlace!.location.longitude, 
            _selectedEndPlace!.location.latitude, _selectedEndPlace!.location.longitude).toStringAsFixed(2)} km';
    
    final String displayDuration = _routeDuration.isNotEmpty
        ? _routeDuration
        : '${(_calculateDistance(_selectedStartPlace!.location.latitude, _selectedStartPlace!.location.longitude, 
            _selectedEndPlace!.location.latitude, _selectedEndPlace!.location.longitude) / 5 * 60).round()} min';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: Colors.grey[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Route Information',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (!_isRoutePlanned) 
                      const SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(strokeWidth: 2)
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Distance:'),
                    Text(
                      displayDistance,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Time:'),
                    Text(
                      displayDuration,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // Add route options card (using new component)
        if (_routeOptions.isNotEmpty) 
          _buildRouteOptionsCard(),
      ],
    );
  }
  
  // Adjust map to show entire route
  void _fitMapToBounds() {
    if (_mapController == null || _selectedStartPlace == null || _selectedEndPlace == null) return;
    
    final double southWestLat = min(_selectedStartPlace!.location.latitude, _selectedEndPlace!.location.latitude);
    final double southWestLng = min(_selectedStartPlace!.location.longitude, _selectedEndPlace!.location.longitude);
    final double northEastLat = max(_selectedStartPlace!.location.latitude, _selectedEndPlace!.location.latitude);
    final double northEastLng = max(_selectedStartPlace!.location.longitude, _selectedEndPlace!.location.longitude);
    
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(southWestLat, southWestLng),
      northeast: LatLng(northEastLat, northEastLng),
    );
    
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50), // 50 is padding
    );
  }

  // Add location button functionality
  void _centerOnUserLocation() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Re-get current location
      await locationService.getCurrentLocation();
      
      if (locationService.currentPosition != null && _mapController != null) {
        // Create user location marker
        final userLocation = LatLng(
          locationService.currentPosition!.latitude,
          locationService.currentPosition!.longitude,
        );
        
        // Ensure removing any old "my location" marker
        _markers.removeWhere((m) => m.markerId.value == 'my_location');
        
        // Add new location marker
        _markers.add(
          Marker(
            markerId: const MarkerId('my_location'),
            position: userLocation,
            zIndex: 2, // Ensure location marker is on top layer
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(
              title: 'My Location',
            ),
          ),
        );
        
        // Animate to user location
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            userLocation,
            15.0,
          ),
        );
        
        setState(() {
          // Update marker set
          _markers = Set<Marker>.from(_markers);
        });
      }
    } catch (e) {
      debugPrint('Unable to locate current position: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Toggle air quality heatmap display status
  void _toggleAirQualityHeatmap() async {
    setState(() {
      _showAirQualityHeatmap = !_showAirQualityHeatmap;
    });
    
    if (_showAirQualityHeatmap) {
      await _updateAirQuality();
    }
  }

  // Update air quality data
  Future<void> _updateAirQuality() async {
    if (_mapController == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get current visible region
      final LatLngBounds bounds = await _mapController!.getVisibleRegion();
      
      // Generate heatmap data through service
      await _airQualityService.generateHeatmapData(bounds);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to update air quality data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Get air quality data along the route
  Future<void> _loadRouteAirQualityData(List<LatLng> routePoints) async {
    try {
      final airQualityService = Provider.of<AirQualityService>(context, listen: false);
      final airQualityData = await airQualityService.getAirQualityAlongRoute(
        routePoints, 
        samplingRate: 5, // Sampling rate
      );
      
      // Update UI to display air quality data
      if (mounted) {
        setState(() {
          _airQualityPoints = airQualityData;
          _generateAirQualityCircles();
        });
      }
    } catch (e) {
      debugPrint('Error loading route air quality data: $e');
    }
  }

  // Generate air quality circles
  void _generateAirQualityCircles() {
    final circles = _airQualityPoints.map((point) {
      return Circle(
        circleId: CircleId('aqi_${point.position.latitude}_${point.position.longitude}'),
        center: point.position,
        radius: 1500 + (point.weight * 800), // Further increase base radius and weight influence, making circles overlap
        fillColor: point.color.withOpacity(min(0.7, 0.4 + point.weight * 0.4)), // Adjust opacity
        strokeColor: Colors.white, // Keep white border visible
        strokeWidth: 2, // Slightly reduce border width to reduce visual interference
      );
    }).toSet();
    
    setState(() {
      _airQualityCircles = circles;
      // Output debug information
      debugPrint('Generated ${circles.length} air quality circles');
    });
  }

  // Add camera stop moving callback function
  void _onCameraIdle() async {
    if (_showAirQualityHeatmap) {
      await _updateAirQuality();
    }
  }

  // Add location button in FloatingActionButton column
  Widget _buildMapControls() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        children: [
          // Heatmap switch button
          if (_airQualityService != null)
            FloatingActionButton(
              heroTag: 'heatmapRouteButton',
              mini: true,
              backgroundColor: _showAirQualityHeatmap 
                  ? Theme.of(context).colorScheme.primary 
                  : Colors.white,
              onPressed: _toggleAirQualityHeatmap,
              child: Icon(
                _showAirQualityHeatmap 
                    ? Icons.layers 
                    : Icons.layers_outlined,
                color: _showAirQualityHeatmap 
                    ? Colors.white 
                    : Colors.black54,
              ),
            ),
          const SizedBox(height: 8),
          // Location button
          FloatingActionButton(
            heroTag: 'locationRouteButton',
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _centerOnUserLocation,
            child: const Icon(
              Icons.my_location,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // Get icon for route type
  IconData _getIconForRouteType(RouteType type) {
    switch (type) {
      case RouteType.fastest:
        return Icons.speed;
      case RouteType.lowestPollution:
        return Icons.eco;
      case RouteType.alternative:
        return Icons.shuffle;
    }
  }
  
  // Determine color based on AQI value
  Color _getColorForAQI(double aqi) {
    if (aqi <= 50) {
      return const Color(0xFF009966); // Good: Deep green
    } else if (aqi <= 100) {
      return const Color(0xFFFFFF00); // Fair: Yellow
    } else if (aqi <= 150) {
      return const Color(0xFFFF7E00); // Mild: Orange
    } else if (aqi <= 200) {
      return const Color(0xFFFF0000); // Moderate: Red
    } else if (aqi <= 300) {
      return const Color(0xFF8F3F97); // Severe: Purple
    } else {
      return const Color(0xFF7E0023); // Hazardous: Brown red
    }
  }
  
  // Calculate distance between two points (in kilometers)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius, in kilometers
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
               cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
               sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    
    return distance;
  }
  
  // Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  // Modify navigation to route method
  void _navigateToRoute() {
    if (_selectedStartPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a starting point')),
      );
      return;
    }
    
    if (_selectedEndPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }
    
    if (_selectedRouteOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a route')),
      );
      return;
    }
    
    // Confirm starting point information
    LatLng startLocation = _selectedStartPlace!.location;
    String startName = _selectedStartPlace!.name;
    
    // If using current location, re-get latest position
    if (_useCurrentLocationAsStart) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      if (locationService.currentPosition != null) {
        startLocation = LatLng(
          locationService.currentPosition!.latitude,
          locationService.currentPosition!.longitude,
        );
        startName = 'Your Location';
      }
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteScreen(
          origin: startLocation,
          destination: _selectedEndPlace!.location,
          destinationName: _selectedEndPlace!.name,
          originName: startName,
        ),
      ),
    );
  }

  // Get marker color based on route type
  double _getMarkerHueForRoute(RouteType routeType) {
    switch (routeType) {
      case RouteType.fastest:
        return BitmapDescriptor.hueBlue; // Fastest route - Blue
      case RouteType.lowestPollution:
        return BitmapDescriptor.hueGreen; // Best air - Green
      case RouteType.alternative:
        return BitmapDescriptor.hueOrange; // Alternative route - Orange
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  // Build route options card
  Widget _buildRouteOptionsCard() {
    if (_routeOptions.isEmpty) return const SizedBox.shrink();
    
    return Card(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Route Options',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _routeOptions.map((option) {
                final isSelected = option == _selectedRouteOption;
                String label;
                IconData icon;
                Color color;
                String subtitle;
                
                switch (option.routeType) {
                  case RouteType.fastest:
                    label = 'Fastest';
                    icon = Icons.speed;
                    color = Colors.blue;
                    subtitle = option.route.duration;
                    break;
                  case RouteType.lowestPollution:
                    label = 'Best Air Quality';
                    icon = Icons.eco;
                    color = Colors.green;
                    subtitle = 'AQI: ${option.avgAirQuality.toStringAsFixed(1)}';
                    break;
                  case RouteType.alternative:
                    label = 'Alternative';
                    icon = Icons.shuffle;
                    color = Colors.orange;
                    subtitle = option.route.duration;
                    break;
                  default:
                    label = 'Other';
                    icon = Icons.route;
                    color = Colors.grey;
                    subtitle = option.route.duration;
                }
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectRouteOption(option),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.2) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? color : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// Location selection screen
class _LocationSelectionScreen extends StatefulWidget {
  final String title;
  final Place? initialLocation;
  final List<Place> recentPlaces;
  final Function(Place) onLocationSelected;

  const _LocationSelectionScreen({
    required this.title,
    this.initialLocation,
    required this.recentPlaces,
    required this.onLocationSelected,
  });

  @override
  _LocationSelectionScreenState createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<_LocationSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Place> _searchResults = [];
  List<Place> _recentSearchPlaces = [];
  bool _isSearching = false;
  bool _useCurrentLocation = false;
  bool _isLoadingRecentSearches = true;
  
  @override
  void initState() {
    super.initState();
    
    // Check if using current location
    _useCurrentLocation = widget.initialLocation?.placeId == 'current_location';
    
    // If there is an initial location, display its name in the search box
    if (widget.initialLocation != null) {
      _searchController.text = widget.initialLocation!.name;
    }
    
    // Load recent searches
    _loadRecentSearches();
  }
  
  // Load recent searches
  Future<void> _loadRecentSearches() async {
    setState(() {
      _isLoadingRecentSearches = true;
    });
    
    try {
      final recentSearches = await GeocodingService.getRecentSearches();
      setState(() {
        _recentSearchPlaces = recentSearches;
      });
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    } finally {
      setState(() {
        _isLoadingRecentSearches = false;
      });
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // Search places
  void _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final results = await GeocodingService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching for places: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }
  
  // Use current location
  void _useCurrentLocationAsStartPoint() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    
    try {
      await locationService.getCurrentLocation();
      if (locationService.currentPosition != null) {
        final currentPlace = Place(
          placeId: 'current_location',
          name: 'Your Location',
          address: 'Current Location',
          location: LatLng(
            locationService.currentPosition!.latitude,
            locationService.currentPosition!.longitude,
          ),
        );
        
        widget.onLocationSelected(currentPlace);
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to get current location')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error getting location, please check location permissions')),
        );
      }
    }
  }
  
  // Select place and return
  void _selectPlace(Place place) {
    // Save to recent search record
    GeocodingService.saveRecentSearch(place);
    
    // Directly select the place, without opening detail page
    widget.onLocationSelected(place);
    Navigator.pop(context);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: widget.initialLocation == null,
          decoration: InputDecoration(
            hintText: widget.title,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            prefixIcon: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchResults = [];
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            if (value.length > 2) {
              _searchPlaces(value);
            } else if (value.isEmpty) {
              setState(() {
                _searchResults = [];
              });
            }
          },
          onSubmitted: _searchPlaces,
        ),
      ),
      body: Column(
        children: [
          // Your location option
          ListTile(
            leading: const Icon(Icons.my_location, color: Colors.blue),
            title: const Text('Your Location'),
            onTap: _useCurrentLocationAsStartPoint,
          ),
          
          // Select location on map
          ListTile(
            leading: const Icon(Icons.map, color: Colors.green),
            title: const Text('Select on Map'),
            onTap: () {
              // Directly implement map selection logic here
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _MapLocationSelectionScreen(
                    onLocationSelected: (place) {
                      _selectPlace(place);
                    },
                  ),
                ),
              );
            },
          ),
          
          // Separator
          const Divider(),
          
          // Search results or history
          Expanded(
            child: Builder(
              builder: (context) {
                // First check if searching
                if (_isSearching) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                } 
                // Then display search results
                else if (_searchResults.isNotEmpty) {
                  return ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final place = _searchResults[index];
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.red),
                        title: Text(place.name),
                        subtitle: Text(
                          place.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  );
                } 
                // Finally display history or empty state
                else if (_isLoadingRecentSearches) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                // Display merged history list
                else if (_recentSearchPlaces.isNotEmpty || widget.recentPlaces.isNotEmpty) {
                  // Merge recent places list, remove duplicates
                  final Map<String, Place> combinedPlaces = {};
                  
                  // First add from API search save record
                  for (var place in _recentSearchPlaces) {
                    combinedPlaces[place.placeId] = place;
                  }
                  
                  // Then add passed history record
                  for (var place in widget.recentPlaces) {
                    if (!combinedPlaces.containsKey(place.placeId)) {
                      combinedPlaces[place.placeId] = place;
                    }
                  }
                  
                  final allRecentPlaces = combinedPlaces.values.toList();
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                        child: Text(
                          'Recent',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: allRecentPlaces.length,
                          itemBuilder: (context, index) {
                            final place = allRecentPlaces[index];
                            return ListTile(
                              leading: const Icon(Icons.history, color: Colors.grey),
                              title: Text(place.name),
                              subtitle: Text(
                                place.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectPlace(place),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                } else {
                  // No results prompt
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Search for a place',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Map location selection screen
class _MapLocationSelectionScreen extends StatefulWidget {
  final Function(Place) onLocationSelected;

  const _MapLocationSelectionScreen({
    required this.onLocationSelected,
  });

  @override
  _MapLocationSelectionScreenState createState() => _MapLocationSelectionScreenState();
}

class _MapLocationSelectionScreenState extends State<_MapLocationSelectionScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLatLng;
  bool _isSearchingLocation = false;
  Marker? _selectedMarker;
  Place? _selectedPlace;
  bool _isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location on Map'),
        actions: [
          if (_selectedPlace != null)
            TextButton.icon(
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('Confirm', style: TextStyle(color: Colors.white)),
              onPressed: () {
                widget.onLocationSelected(_selectedPlace!);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          Consumer<LocationService>(
            builder: (context, locationService, child) {
              final initialPosition = locationService.currentPosition != null
                  ? LatLng(
                      locationService.currentPosition!.latitude,
                      locationService.currentPosition!.longitude,
                    )
                  : const LatLng(39.9042, 116.4074); // Default position (Beijing)

              return GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialPosition,
                  zoom: 15.0,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                onTap: _handleMapTap,
                markers: _selectedMarker != null ? {_selectedMarker!} : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              );
            },
          ),
          
          // Map center indicator
          Center(
            child: Icon(
              Icons.location_pin,
              color: Colors.red.withOpacity(_selectedLatLng == null ? 0.7 : 0),
              size: 40,
            ),
          ),
          
          // Loading indicator
          if (_isSearchingLocation)
            const Center(
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 16),
                      Text('Getting location information...'),
                    ],
                  ),
                ),
              ),
            ),
          
          // Location information card
          if (_selectedPlace != null && !_isSearchingLocation)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedPlace!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedPlace!.address,
                        style: const TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedPlace = null;
                                _selectedMarker = null;
                                _selectedLatLng = null;
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              // Directly select the location
                              widget.onLocationSelected(_selectedPlace!);
                              Navigator.pop(context);
                            },
                            child: const Text('Select This Location'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
          // Control buttons
          Positioned(
            right: 16,
            bottom: _selectedPlace != null ? 140 : 16,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  heroTag: 'locate',
                  child: const Icon(Icons.my_location),
                  onPressed: _centerOnUserLocation,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleMapTap(LatLng latLng) async {
    setState(() {
      _selectedLatLng = latLng;
      _isSearchingLocation = true;
      _selectedMarker = Marker(
        markerId: const MarkerId('selected_location'),
        position: latLng,
      );
    });
    
    try {
      // Use reverse geocoding to get location information
      final place = await _getPlaceFromLatLng(latLng);
      if (place != null) {
        setState(() {
          _selectedPlace = place;
          _selectedMarker = Marker(
            markerId: const MarkerId('selected_location'),
            position: latLng,
            infoWindow: InfoWindow(
              title: place.name,
              snippet: place.address,
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Error getting location information: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to get location information, please try again')),
      );
    } finally {
      setState(() {
        _isSearchingLocation = false;
      });
    }
  }
  
  Future<Place?> _getPlaceFromLatLng(LatLng latLng) async {
    // Show loading state
    setState(() {
      _isLoading = true;
    });

    try {
      // Use reverse geocoding service to get location information
      final place = await GeocodingService.reverseGeocode(latLng);
      
      return place ?? Place(
        placeId: 'place_${latLng.latitude}_${latLng.longitude}',
        name: 'Selected Location',
        address: 'Coordinates: ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
        location: latLng,
      );
    } catch (e) {
      debugPrint('Error getting place from coordinates: $e');
      
      // Error return simplified location information
      return Place(
        placeId: 'place_${latLng.latitude}_${latLng.longitude}',
        name: 'Selected Location',
        address: 'Coordinates: ${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
        location: latLng,
      );
    } finally {
      // Hide loading state
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _centerOnUserLocation() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    try {
      await locationService.getCurrentLocation();
      if (locationService.currentPosition != null && _mapController != null) {
        final position = locationService.currentPosition!;
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
    }
  }
} 