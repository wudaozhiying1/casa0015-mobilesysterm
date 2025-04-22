import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../screens/route_planner_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/air_quality_overlay.dart';
import '../widgets/air_quality_info_sheet.dart';
import '../services/location_service.dart';
import '../services/air_quality_service.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../screens/submit_measurement_screen.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../widgets/air_quality_regions_widget.dart';
import '../models/place.dart';
import '../controllers/air_quality_controller.dart';
import '../widgets/air_quality_button.dart';
import '../screens/place_details_screen.dart';
import '../services/search_history_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  bool _mapLoadError = false;
  bool _isNavigating = false;
  bool _isLoading = false;
  TextEditingController _searchController = TextEditingController();
  double _currentZoom = 15.0;
  
  // Autocomplete related variables
  List<Place> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  // Recent search history variables
  List<Place> _recentSearches = [];
  bool _showRecentSearches = false;
  bool _isLoadingRecentSearches = false;
  
  // Add _isFetchingPlace property
  bool _isFetchingPlace = false;
  
  // Add FocusNode
  final FocusNode _searchFocusNode = FocusNode();

  // Place selection related variables
  Place? _selectedDestination;
  Place? _selectedPlace;

  // Heatmap related variables
  bool _showAirQualityHeatmap = false;
  List<AirQualityPoint> _airQualityPoints = [];
  Set<Circle> _airQualityCircles = {};
  bool _isLoadingAirQualityData = false;
  late AirQualityService _airQualityService;
  // Delayed update when map movement ends - using variable to track last update time
  DateTime? _lastHeatmapUpdate;
  // Add variable to track if map is moving
  bool _isMapMoving = false;
  // Add variable to track last visible region
  LatLngBounds? _lastVisibleRegion;
  // Add variable to track last zoom level
  double? _lastZoomLevel;
  // Add variable to control heatmap quality
  bool _useHighQualityHeatmap = true;
  // Add variable to track map position
  CameraPosition? _lastMapPosition;
  // Add variable to track user position
  Position? _currentPosition;
  // Add variable to track current location Placemark
  Placemark? _currentPlacemark;
  // Add default location
  final LatLng _defaultLocation = LatLng(51.5074, -0.1278); // London

  // Add map initialization flag
  bool _isMapInitialized = false;
  // Add map initialization callback
  Function(GoogleMapController)? _onMapInitialized;
  // Add map style
  String _mapStyle = '';
  // Add map center location
  LatLng? _currentLocation;
  // Add search location
  LatLng? _searchLocation;
  // Add search location name
  String? _searchPlaceName;
  // Add whether location permission has been requested
  bool _hasRequestedLocationPermission = false;

  @override
  void initState() {
    super.initState();
    print('HomeScreen: initState called');
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(_onSearchFocused);
    
    // Initialize heatmap update time
    _lastHeatmapUpdate = null;
    _lastVisibleRegion = null;
    _lastZoomLevel = null;
    
    // Load saved recent places
    _loadRecentPlaces();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure location permission is requested after widget is fully built
      _requestLocationPermission();
      
      // Pre-generate some heatmap data for first button click
      _preGenerateHeatmapData();
      
      // Automatically locate to user position after app launch
      Future.delayed(Duration(milliseconds: 500), () {
        _centerOnUserLocation();
      });
    });

    // Initialize air quality service
    _airQualityService = Provider.of<AirQualityService>(context, listen: false);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mapController?.dispose();
    super.dispose();
  }
  
  // Show recent searches when search box gets focus
  void _onSearchFocused() {
    if (_searchFocusNode.hasFocus && _searchController.text.isEmpty && !_isSearching) {
      setState(() {
        _showRecentSearches = true;
        _showSearchResults = false;
      });
    }
  }
  
  // Load recent search records
  Future<void> _loadRecentPlaces() async {
    setState(() {
      _isLoadingRecentSearches = true;
    });
    
    try {
      final recentSearches = await GeocodingService.getRecentSearches();
      setState(() {
        _recentSearches = recentSearches;
        _isLoadingRecentSearches = false;
      });
    } catch (e) {
      print('HomeScreen: Error loading recent searches: $e');
      setState(() {
        _isLoadingRecentSearches = false;
      });
    }
  }
  
  // Search for places
  void _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
      _showRecentSearches = false;
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
      print('Error searching places: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }
  
  // Select a place and navigate to that location
  void _selectPlace(Place place) async {
    // Save to recent searches
    GeocodingService.saveRecentSearch(place);
    
    // Also save to Firebase search history
    try {
      await SearchHistoryService.addSearchHistory(place);
    } catch (e) {
      print('Failed to save to Firebase search history: $e');
    }
    
    // Clear search state
    setState(() {
      _showSearchResults = false;
      _showRecentSearches = false;
      _selectedPlace = place;
      _searchController.text = place.name;
      // Save search location for air quality feature
      _searchLocation = place.location;
      _searchPlaceName = place.name;
      FocusScope.of(context).unfocus();
    });
    
    // Add marker
    final marker = Marker(
      markerId: MarkerId(place.placeId),
      position: place.location,
      infoWindow: InfoWindow(
        title: place.name,
        snippet: place.address,
      ),
    );
    
    setState(() {
      // Remove previous destination markers
      _markers.removeWhere((m) => m.markerId.value != 'my_location');
      _markers.add(marker);
    });
    
    // Move map to selected location
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: place.location,
          zoom: 15.0,
        ),
      ),
    );
    
    // If air quality controller is visible, update heatmap data
    final airQualityController = Provider.of<AirQualityController>(context, listen: false);
    if (airQualityController.isVisible) {
      try {
        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updating air quality data...'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Generate heatmap data for new location
        await airQualityController.generateHeatmapForLocation(place.location, radius: 0.05);
      } catch (e) {
        print('Failed to update destination air quality data: $e');
      }
    }
    
    // Open place details
    _showPlaceDetails(place);
  }
  
  // Show place details page
  void _showPlaceDetails(Place place) async {
    // Get current location for navigation
    LocationService locationService = Provider.of<LocationService>(context, listen: false);
    LatLng? currentLocation;
    
    if (locationService.currentPosition != null) {
      currentLocation = LatLng(
        locationService.currentPosition!.latitude,
        locationService.currentPosition!.longitude,
      );
    }
    
    // Navigate to place details page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaceDetailsScreen(
          place: place,
          currentLocation: currentLocation,
          isStartPoint: false, // Places selected from home screen typically serve as endpoints
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final airQualityController = Provider.of<AirQualityController>(context);
    
    return Scaffold(
      body: Stack(
        children: [
          // Map
          _buildMap(),
          
          // Search box
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 70, // Made smaller to leave space for the right button
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search places...',
                    prefixIcon: const Icon(Icons.search),
                    border: InputBorder.none,
                    suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchResults = [];
                              _showSearchResults = false;
                            });
                          },
                        )
                      : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  onChanged: (value) {
                    if (value.length > 2) {
                      _searchPlaces(value);
                    } else if (value.isEmpty) {
                      setState(() {
                        _searchResults = [];
                        _showSearchResults = false;
                      });
                    }
                  },
                  onSubmitted: _searchPlaces,
                ),
              ),
            ),
          ),
          
          // Profile button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.person, color: Colors.white),
                  tooltip: 'Profile',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // Search results list
          if (_showSearchResults || _showRecentSearches)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isSearching
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _showSearchResults && _searchResults.isNotEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _searchResults.length,
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      physics: const ClampingScrollPhysics(),
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
                                    ),
                                  ),
                                ],
                              )
                            : _showRecentSearches && _recentSearches.isNotEmpty
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
                                        child: Text(
                                          'Recent Searches',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      // Use Expanded and scrollable view
                                      Expanded(
                                        child: ListView.builder(
                                          itemCount: _recentSearches.length,
                                          shrinkWrap: true,
                                          physics: const ClampingScrollPhysics(),
                                          padding: EdgeInsets.zero,
                                          itemBuilder: (context, index) {
                                            final place = _recentSearches[index];
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
                                  )
                                : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          
          // Air quality control button
          Positioned(
            right: 16,
            bottom: 100,
            child: AirQualityButton(
              // Provide current location information to AirQualityButton
              onMapBoundsChanged: (bounds) {
                // Use current search location or map center location
                LatLng center;
                if (_searchLocation != null) {
                  center = _searchLocation!;
                } else if (_lastMapPosition != null) {
                  center = _lastMapPosition!.target;
                } else if (_currentLocation != null) {
                  center = _currentLocation!;
                } else {
                  center = const LatLng(51.5074, -0.1278); // London center
                }
                
                // Generate heatmap data for current location
                final airQualityController = Provider.of<AirQualityController>(context, listen: false);
                airQualityController.generateHeatmapForLocation(center, radius: 0.05);
              },
            ),
          ),
          
          // Location button
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: _centerOnUserLocation,
              child: const Icon(Icons.my_location),
              tooltip: 'My location',
            ),
          ),
          
          // Route planning button
          Positioned(
            right: 16,
            bottom: 160,
            child: FloatingActionButton(
              heroTag: 'routePlannerBtn',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoutePlannerScreen(
                      initialEndPlace: _selectedPlace,
                    ),
                  ),
                );
              },
              backgroundColor: Colors.green,
              child: const Icon(Icons.directions),
              tooltip: 'Route Planner',
            ),
          ),
          
          // Loading indicator
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
  
  // Create a map
  Widget _buildMap() {
    final airQualityController = Provider.of<AirQualityController>(context);
    Set<Marker> allMarkers = {};
    
  // Add current location marker
    if (_currentLocation != null) {
      allMarkers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(
            title: 'Current location',
            snippet: 'Click to view air quality data',
          ),
          onTap: () => _showAirQualityInfoBottomSheet(_currentLocation!),
        ),
      );
    }
    
    // Add search location tags
    if (_searchLocation != null) {
      allMarkers.add(
        Marker(
          markerId: const MarkerId('search_location'),
          position: _searchLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: _searchPlaceName ?? 'Search location',
            snippet: 'Click to view air quality data',
          ),
          onTap: () => _showAirQualityInfoBottomSheet(_searchLocation!),
        ),
      );
    }
    
    // Add air quality data point markers
    if (airQualityController.isVisible && airQualityController.heatmapData.isNotEmpty) {
      for (var point in airQualityController.heatmapData) {
        allMarkers.add(
          Marker(
            markerId: MarkerId('air_quality_${point.position.latitude}_${point.position.longitude}'),
            position: point.position,
            icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHue(point.aqi)),
            infoWindow: InfoWindow(
              title: 'AQI: ${point.aqi.round()}',
              snippet: 'Click to view detailed air quality data',
            ),
            onTap: () => _showAirQualityInfoBottomSheet(point.position),
          ),
        );
      }
    }
    
    // Add all custom tags
    allMarkers.addAll(_markers);
    
    // Air quality tile coverage map
    Set<TileOverlay> tileOverlays = {};
    if (airQualityController.isVisible && airQualityController.useTileOverlay && airQualityController.tileUrlTemplate != null) {
      tileOverlays.add(
        TileOverlay(
          tileOverlayId: const TileOverlayId('air_quality_tile'),
          tileProvider: UrlTileProvider(urlTemplate: airQualityController.tileUrlTemplate!),
          transparency: 0.3,
          zIndex: 1,
          fadeIn: true,
        ),
      );
    }
    
    return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(51.5074, -0.1278), 
        zoom: 12,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      markers: allMarkers,
      tileOverlays: tileOverlays,
      polylines: _polylines,
      circles: _circles,
      onMapCreated: _initializeMapController,
      onCameraMove: _checkAndUpdateHeatmapOnMove,
      onTap: _handleMapTap,
    );
  }
  
  // Get marker color based on AQI
  double _getMarkerHue(double aqi) {
    if (aqi <= 50) {
      return BitmapDescriptor.hueGreen; // Excellent
    } else if (aqi <= 100) {
      return BitmapDescriptor.hueGreen + 20; // Good
    } else if (aqi <= 150) {
      return BitmapDescriptor.hueYellow; // light pollution
    } else if (aqi <= 200) {
      return BitmapDescriptor.hueOrange; // moderate pollution
    } else if (aqi <= 300) {
      return BitmapDescriptor.hueRed; // heavy pollution
    } else {
      return BitmapDescriptor.hueViolet; // severe contamination
    }
  }
  
  // Toggle air quality heatmap
  void _toggleAirQualityHeatmap() async {
    final airQualityController = Provider.of<AirQualityController>(context, listen: false);
    
    // Check if heatmap is already visible
    bool isVisible = airQualityController.isVisible;
    
    // Show loading notification
    if (!isVisible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading air quality sampling points, please wait...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    // Toggle heatmap visibility
    airQualityController.toggleVisibility();
    
    // If becoming visible, get actual air quality data
    if (!isVisible) {
      setState(() {
        _isLoadingAirQualityData = true;
      });
      
      try {
        // Determine center position
        LatLng center;
        if (_currentLocation != null) {
          center = _currentLocation!;
        } else if (_searchLocation != null) {
          center = _searchLocation!;
        } else {
          center = const LatLng(51.5074, -0.1278); // London center
        }
        
        // Use the actual API to get data
        // We set a fixed radius to get sampling points around
        await airQualityController.generateHeatmapForLocation(center, radius: 0.05);
        
        // If not enough data points, notify the user
        if (airQualityController.heatmapData.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to get air quality data points, try moving to another area or try again later'),
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          // Show data point information
          print('Retrieved ${airQualityController.heatmapData.length} air quality sampling points');
          for (var point in airQualityController.heatmapData) {
            print('Sampling point: position=(${point.position.latitude}, ${point.position.longitude}), AQI=${point.aqi}');
          }
        }
      } catch (e) {
        print('Failed to get air quality data: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to get air quality data: ${e.toString()}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingAirQualityData = false;
          });
        }
      }
    }
  }
  
  // Request Location Permission
  Future<void> _requestLocationPermission() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    await locationService.requestPermission();
  }
  
  // Pre-generate heatmap data
  void _preGenerateHeatmapData() async {
    print('Preparing to pre-fetch initial air quality data');
    
    try {
      final airQualityController = Provider.of<AirQualityController>(context, listen: false);
      
      // Use default location (London center) to pre-fetch data
      await airQualityController.generateHeatmapForLocation(
        _defaultLocation, 
        radius: 0.05
      );
      
      print('Pre-fetch complete, retrieved ${airQualityController.heatmapData.length} air quality data points');
      
      // Ensure heatmap is invisible, only pre-fetching data
      if (airQualityController.isVisible) {
        airQualityController.setVisibility(false);
      }
    } catch (e) {
      print('Failed to pre-fetch air quality data: $e');
    }
  }

  void _initializeMapController(GoogleMapController controller) {
    _mapController = controller;
    _mapController!.setMapStyle(_mapStyle);
    
    print('Map controller initialized');
    
    // Check if location permission has already been requested
    if (!_hasRequestedLocationPermission) {
      _requestLocationPermission();
      _hasRequestedLocationPermission = true;
    }
    
    // Try to get user location immediately after initialization
    _centerOnUserLocation();
    
    setState(() {
      _isMapInitialized = true;
    });
    
    // Notify other components that map has been initialized
    if (_onMapInitialized != null) {
      _onMapInitialized!(_mapController!);
    }
  }

  // Center map on user location
  void _centerOnUserLocation() async {
    // If map controller is null, wait for it to initialize
    if (_mapController == null) {
      print('Map controller not initialized yet, retrying in 500ms');
      await Future.delayed(Duration(milliseconds: 500));
      if (_mapController == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Map not initialized yet, please try again later'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get current location
      final locationService = Provider.of<LocationService>(context, listen: false);
      await locationService.getCurrentLocation();
      
      if (locationService.currentPosition != null) {
        // Update current position
        _currentPosition = locationService.currentPosition;
        
        // Get user location
        final userLocation = LatLng(
          locationService.currentPosition!.latitude,
          locationService.currentPosition!.longitude,
        );
        
        // Save as current location
        _currentLocation = userLocation;
        
        // Update marker
        setState(() {
          _markers.removeWhere((marker) => marker.markerId.value == 'my_location');
          _markers.add(
            Marker(
              markerId: const MarkerId('my_location'),
              position: userLocation,
              infoWindow: const InfoWindow(title: 'My location'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            ),
          );
        });
        
        // Move map
        if (_mapController != null && mounted) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: userLocation,
                zoom: 15.0,
              ),
            ),
          );
          
          // Show notification
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Located to your position'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Cannot get location
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to get your location, please check location permissions'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Check if the heat map needs to be updated when the map is moved
  void _checkAndUpdateHeatmapOnMove(CameraPosition position) async {
    final airQualityController = Provider.of<AirQualityController>(context, listen: false);
    
    // Update Current Position
    _lastMapPosition = position;
    _currentZoom = position.zoom;
    
    // If the heat map is not visible and does not need to be updated
    if (!airQualityController.isVisible) {
      return;
    }
    
    // Set to be moving map
    _isMapMoving = true;
    
    // Delay updating the heat map for a while to avoid frequent updates during map movement
    if (_lastHeatmapUpdate == null || 
        DateTime.now().difference(_lastHeatmapUpdate!).inSeconds >= 5) {
      
      // Delay a bit, wait for the map to stabilize
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Check if it's still moving
      if (!mounted || !airQualityController.isVisible) return;
      
      try {
        // Get the current visible area of the map
        LatLngBounds? visibleRegion;
        if (_mapController != null) {
          try {
            visibleRegion = await _mapController!.getVisibleRegion();
          } catch (e) {
            print('Failed to get map visible area: $e');
            return;
          }
        }
        
        // If the visible area is not available, use the current position
        if (visibleRegion == null) {
          return;
        }
        
        // Check if the area has changed enough
        bool shouldUpdate = _lastVisibleRegion == null ||
            _isSignificantMapChange(visibleRegion, _lastVisibleRegion!);
        
        // Check if the zoom level has changed much
        bool zoomChanged = _lastZoomLevel == null ||
            (_lastZoomLevel! - position.zoom).abs() >= 1.0;
        
        if (shouldUpdate || zoomChanged) {
          _lastVisibleRegion = visibleRegion;
          _lastZoomLevel = position.zoom;
          _lastHeatmapUpdate = DateTime.now();
          
          // Show Tip
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Air quality data being updated...'),
                duration: Duration(seconds: 1),
              ),
            );
          }
          
          // Generate heat map data
          if (mounted) {
            await airQualityController.generateHeatmapForLocation(
              position.target,
              radius: _calculateRadiusForZoom(position.zoom),
              zoomLevel: position.zoom
            );
          }
        }
      } catch (e) {
        print('Error updating heat map data: $e');
      } finally {
        _isMapMoving = false;
      }
    } else {
      _isMapMoving = false;
    }
  }
  
  // Determine if the map area has changed enough
  bool _isSignificantMapChange(LatLngBounds current, LatLngBounds previous) {
    // If the center point of the map moves more than 25% of the currently visible area, it is considered a significant change
    double currentWidth = (current.northeast.longitude - current.southwest.longitude).abs();
    double currentHeight = (current.northeast.latitude - current.southwest.latitude).abs();
    
    double prevCenterLat = (previous.northeast.latitude + previous.southwest.latitude) / 2;
    double prevCenterLng = (previous.northeast.longitude + previous.southwest.longitude) / 2;
    double currCenterLat = (current.northeast.latitude + current.southwest.latitude) / 2;
    double currCenterLng = (current.northeast.longitude + current.southwest.longitude) / 2;
    
    double latChange = (currCenterLat - prevCenterLat).abs();
    double lngChange = (currCenterLng - prevCenterLng).abs();
    
    // If the horizontal or vertical movement exceeds 25% of the visible area, it is considered a significant change
    return (latChange > currentHeight * 0.25) || (lngChange > currentWidth * 0.25);
  }
  
  // Calculate the appropriate radius based on the zoom level
  double _calculateRadiusForZoom(double zoom) {
    // The larger the zoom level, the smaller the radius
    if (zoom >= 16) {
      return 0.01; // very close
    } else if (zoom >= 14) {
      return 0.02; // closer
    } else if (zoom >= 12) {
      return 0.04; // moderate
    } else if (zoom >= 10) {
      return 0.08; // more distant
    } else {
      return 0.12; // far away
    }
  }

  // Processing map clicks
  void _handleMapTap(LatLng position) async {
    final airQualityController = Provider.of<AirQualityController>(context, listen: false);
    
    // Clear search result display
    setState(() {
      _showSearchResults = false;
      _showRecentSearches = false;
    });
    
    // If the heat map is visible, display air quality information for the location
    if (airQualityController.isVisible) {
      _showAirQualityInfoBottomSheet(position);
    }
  }
  
  // Show air quality info bottom sheet
  void _showAirQualityInfoBottomSheet(LatLng location) async {
    setState(() {
      _isLoadingAirQualityData = true;
    });
    
    try {
      // Get air quality data for this location
      final data = await _airQualityService.fetchGoogleAirQualityData(location);
      
      if (!mounted) return;
      
      // If there is data, show bottom sheet
      if (data['aqi'] != null) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            height: MediaQuery.of(context).size.height * 0.4,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bottom sheet drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                
                // Title area
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Air Quality Index',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Longitude: ${location.longitude.toStringAsFixed(5)}, Latitude: ${location.latitude.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (data['warning'] != null)
                            Text(
                              data['warning'],
                              style: const TextStyle(
                                color: Colors.orange,
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: data['color'] ?? Colors.grey,
                        child: Text(
                          '${data['aqi']}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Divider
                const Divider(),
                
                // Detailed information
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildInfoRow('Air Quality Level', data['quality'] ?? 'Unknown'),
                      _buildInfoRow('Main Pollutant', data['pollutant'] ?? 'Unknown'),
                      _buildInfoRow('Data Source', data['source'] ?? 'Unknown'),
                      _buildInfoRow('Update Time', _formatDateTime(data['dateTime'])),
                      
                      // Add measurement button
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SubmitMeasurementScreen(
                              location: location,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add My Measurement Data'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Show notification when no data
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get air quality data for this location'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error showing air quality info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get air quality data: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAirQualityData = false;
        });
      }
    }
  }
  

  Widget _buildInfoRow(String title, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value ?? 'Unknown',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  // Formatting Date Time
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'Unknown';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }
} 