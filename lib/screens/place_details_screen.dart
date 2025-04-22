import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/place.dart';
import '../services/geocoding_service.dart';
import '../controllers/air_quality_controller.dart';
import '../widgets/air_quality_button.dart';
import '../services/air_quality_service.dart';
import '../services/favorites_service.dart';
import 'route_screen.dart';
import 'route_planner_screen.dart';
import 'submit_measurement_screen.dart';
import '../services/location_service.dart';

class PlaceDetailsScreen extends StatefulWidget {
  final Place place;
  final LatLng? currentLocation;
  final bool isSelectionScreen;
  final bool isStartPoint;

  const PlaceDetailsScreen({
    super.key,
    required this.place,
    this.currentLocation,
    this.isSelectionScreen = false,
    required this.isStartPoint,
  });

  @override
  State<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}

class _PlaceDetailsScreenState extends State<PlaceDetailsScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final DraggableScrollableController _scrollController = DraggableScrollableController();
  bool _isLoadingAirQualityData = false;
  late AirQualityService _airQualityService;
  bool _isFavorite = false;
  bool _isCheckingFavorite = true;

  @override
  void initState() {
    super.initState();
    // Set initial marker
    _markers = {
      Marker(
        markerId: MarkerId(widget.place.placeId),
        position: widget.place.location,
        infoWindow: InfoWindow(title: widget.place.name),
      ),
    };
    
    // If there's a current location, add a marker for it
    if (widget.currentLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: widget.currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your location'),
        ),
      );
    }
    
    // Get AirQualityService in initState
    Future.microtask(() {
      _airQualityService = Provider.of<AirQualityService>(context, listen: false);
      // Check if this place is already in favorites
      _checkIfFavorite();
    });
  }

  // Check if this place is already in favorites
  Future<void> _checkIfFavorite() async {
    try {
      final isFav = await FavoritesService.isFavorite(widget.place.placeId);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
          _isCheckingFavorite = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
      if (mounted) {
        setState(() {
          _isCheckingFavorite = false;
        });
      }
    }
  }

  // Toggle favorite status
  Future<void> _toggleFavorite() async {
    if (FavoritesService.isUserLoggedIn) {
      try {
        if (_isFavorite) {
          // If already favorited, remove from favorites
          await FavoritesService.removeFavorite(widget.place.placeId);
          if (mounted) {
            setState(() {
              _isFavorite = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Removed from favorites')),
            );
          }
        } else {
          // If not favorited, add to favorites
          await FavoritesService.addFavorite(widget.place);
          if (mounted) {
            setState(() {
              _isFavorite = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added to favorites')),
            );
          }
        }
      } catch (e) {
        debugPrint('Error toggling favorite status: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Operation failed: $e')),
          );
        }
      }
    } else {
      // User not logged in
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to save favorites')),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    try {
      // Try to safely release the map controller
      _mapController?.dispose();
    } catch (e) {
      print('Error releasing map controller: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final airQualityController = Provider.of<AirQualityController>(context);
    // Ensure _airQualityService is initialized
    _airQualityService = Provider.of<AirQualityService>(context, listen: false);
    
    // Create complete marker set, including air quality data point markers
    Set<Marker> allMarkers = Set.from(_markers);
    
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
              snippet: 'Click for detailed air quality data',
            ),
            onTap: () => _showAirQualityInfoBottomSheet(point.position),
          ),
        );
      }
    }

    // Air quality tile overlay
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
    
    return Scaffold(
      appBar: widget.isSelectionScreen 
        ? AppBar(
            title: Text(widget.isStartPoint ? 'Select starting point' : 'Select destination'),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 1,
          ) 
        : null,
      body: Stack(
        children: [
          // Map takes the full screen
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.place.location,
              zoom: 16.0,
            ),
            markers: allMarkers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            tileOverlays: tileOverlays,
            circles: _circles,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: _handleMapTap,
          ),
          
          // Top information bar - floating bar similar to Google Maps
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  // Add back arrow
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12.0),
                      child: Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.place.name,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.4, // Initial height is 40% of the screen
            minChildSize: 0.2, // Minimum height is 20% of the screen
            maxChildSize: 0.6, // Maximum height is 60% of the screen
            controller: _scrollController,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Drag indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    
                    // Place name and rating
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.place.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Rating and walking time
                          Row(
                            children: [
                              const Text('5.0 '),
                              ...List.generate(5, (index) => 
                                const Icon(Icons.star, color: Colors.amber, size: 16)
                              ),
                              const Text(' (2) • '),
                              const Icon(Icons.directions_walk, size: 16),
                              const Text(' 1 min'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Address
                          Text(
                            widget.place.address,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                          const Divider(height: 32),
                        ],
                      ),
                    ),
                    
                    // Bottom buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: _isCheckingFavorite 
                                ? const CircularProgressIndicator(strokeWidth: 2) 
                                : Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
                            label: _isFavorite ? 'Saved' : 'Save',
                            onTap: _toggleFavorite,
                            color: _isFavorite ? Colors.red : Colors.grey,
                          ),
                          _buildActionButton(
                            icon: const Icon(Icons.directions),
                            label: 'Route',
                            onTap: () {
                              // Get current location to use as starting point
                              LatLng? currentLocation;
                              Place startPlace;
                              
                              // Prioritize using the passed-in current location
                              if (widget.currentLocation != null) {
                                currentLocation = widget.currentLocation;
                                startPlace = Place(
                                  placeId: 'current_location',
                                  name: 'Your Location',
                                  address: 'Current Location',
                                  location: widget.currentLocation!,
                                );
                              } else {
                                // Try to get from LocationService
                                final locationService = Provider.of<LocationService>(context, listen: false);
                                if (locationService.currentPosition != null) {
                                  currentLocation = LatLng(
                                    locationService.currentPosition!.latitude,
                                    locationService.currentPosition!.longitude,
                                  );
                                  startPlace = Place(
                                    placeId: 'current_location',
                                    name: 'Your Location',
                                    address: 'Current Location',
                                    location: currentLocation,
                                  );
                                } else {
                                  // Use default location when unable to get position
                                  startPlace = Place(
                                    placeId: 'default_location',
                                    name: 'London City Center',
                                    address: 'London, UK',
                                    location: const LatLng(51.5074, -0.1278),
                                  );
                                }
                              }
                              
                              // Print debug info
                              print('Planning route: From ${startPlace.name} to ${widget.place.name}');
                              
                              // Navigate to route planning page and pass starting and ending points
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RoutePlannerScreenWithParams(
                                    initialStartPlace: startPlace,
                                    initialEndPlace: widget.place,
                                  ),
                                ),
                              ).then((_) {
                                // Ensure page refreshes correctly when returning
                                if (mounted) {
                                  setState(() {});
                                }
                              });
                            },
                            color: Colors.blue,
                          ),
                          _buildActionButton(
                            icon: const Icon(Icons.navigation),
                            label: 'Navigate',
                            onTap: () async {
                              if (widget.currentLocation != null) {
                                print('Depart button clicked - from ${widget.currentLocation!.latitude},${widget.currentLocation!.longitude} to ${widget.place.location.latitude},${widget.place.location.longitude}');
                                
                                // Show loading indicator
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Planning route with air quality data...'))
                                );
                                
                                // Direct navigation from current location to destination
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RouteScreen(
                                      origin: widget.currentLocation!,
                                      destination: widget.place.location,
                                      destinationName: widget.place.name,
                                      originName: 'Your Location',
                                      // Don't start navigation immediately to ensure route is displayed correctly first
                                      startNavigation: false,
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Unable to get current location')),
                                );
                              }
                            },
                            color: Colors.green,
                          ),
                          _buildActionButton(
                            icon: const Icon(Icons.share),
                            label: 'Share',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Share function')),
                              );
                            },
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Air quality control button
          Positioned(
            right: 16,
            bottom: 100,
            child: AirQualityButton(
              onMapBoundsChanged: (bounds) {
                // Generate heatmap data for current location
                final airQualityController = Provider.of<AirQualityController>(context, listen: false);
                airQualityController.generateHeatmapForLocation(widget.place.location, radius: 0.05);
              },
            ),
          ),
          
          // Loading indicator
          if (_isLoadingAirQualityData)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Handle map tap event
  void _handleMapTap(LatLng position) {
    // Show air quality information for that location
    _showAirQualityInfoBottomSheet(position);
  }
  
  // Show air quality information bottom sheet
  void _showAirQualityInfoBottomSheet(LatLng location) async {
    setState(() {
      _isLoadingAirQualityData = true;
    });
    
    try {
      // Get air quality data for this location
      final data = await _airQualityService.fetchGoogleAirQualityData(location);
      
      if (!mounted) return;
      
      // Show bottom sheet if data is available
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
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
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
      print('Error showing air quality information: $e');
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
  
  // Get marker color based on AQI
  double _getMarkerHue(double aqi) {
    if (aqi <= 50) {
      return BitmapDescriptor.hueGreen; // Excellent
    } else if (aqi <= 100) {
      return BitmapDescriptor.hueGreen + 20; // Good
    } else if (aqi <= 150) {
      return BitmapDescriptor.hueYellow; // Light pollution
    } else if (aqi <= 200) {
      return BitmapDescriptor.hueOrange; // Moderate pollution
    } else if (aqi <= 300) {
      return BitmapDescriptor.hueRed; // Heavy pollution
    } else {
      return BitmapDescriptor.hueViolet; // Severe pollution
    }
  }
  
  // Build information row
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  
  // Format date time
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'Unknown';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }

  Widget _buildActionButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: color,
                size: 24,
              ),
              child: icon,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
} 