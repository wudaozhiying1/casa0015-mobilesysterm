import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../services/air_quality_service.dart';
import '../screens/route_screen.dart';

class AirQualityRegionsWidget extends StatefulWidget {
  final LatLng searchLocation;
  final String locationName;
  final VoidCallback? onClose;

  const AirQualityRegionsWidget({
    Key? key,
    required this.searchLocation,
    required this.locationName,
    this.onClose,
  }) : super(key: key);

  @override
  State<AirQualityRegionsWidget> createState() => _AirQualityRegionsWidgetState();
}

class _AirQualityRegionsWidgetState extends State<AirQualityRegionsWidget> {
  bool _isLoading = true;
  Map<String, Map<String, dynamic>> _regionsData = {};
  List<String> _sortedRegions = [];
  List<String> _mainDirections = ['North', 'East', 'South', 'West']; // Four main directions
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAirQualityData();
  }

  // Load air quality data for surrounding regions
  Future<void> _loadAirQualityData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final airQualityService = Provider.of<AirQualityService>(context, listen: false);
      final regionsData = await airQualityService.getNearbyRegionsAirQuality(widget.searchLocation);
      
      // Check if all main directions exist
      bool allMainDirectionsExist = _mainDirections.every((dir) => regionsData.containsKey(dir));
      
      if (!allMainDirectionsExist) {
        print('Warning: Some main directions are missing');
        // If some main directions are missing, continue with the data we have without setting an error
      }
      
      // Custom sorting: main directions first, then sort by AQI
      final sortedKeys = regionsData.keys.toList()
        ..sort((a, b) {
          // Prioritize main directions
          bool aIsMain = _mainDirections.contains(a);
          bool bIsMain = _mainDirections.contains(b);
          
          if (aIsMain && !bIsMain) return -1;
          if (!aIsMain && bIsMain) return 1;
          
          // Within main directions, sort by fixed order (North, East, South, West)
          if (aIsMain && bIsMain) {
            return _mainDirections.indexOf(a) - _mainDirections.indexOf(b);
          }
          
          // Other directions sort by AQI from low to high
          int aqiA = regionsData[a]!['aqi'] as int;
          int aqiB = regionsData[b]!['aqi'] as int;
          return aqiA.compareTo(aqiB);
        });
      
      setState(() {
        _regionsData = regionsData;
        _sortedRegions = sortedKeys;
        _isLoading = false;
      });
      print('Loaded air quality data for ${_regionsData.length} regions');
    } catch (e) {
      print('Error loading air quality data: $e');
      setState(() {
        _isLoading = false;
        _error = 'Unable to get surrounding air quality data: $e';
      });
    }
  }

  // Navigate to specified region
  void _navigateToRegion(String regionName) {
    if (_regionsData.containsKey(regionName)) {
      final region = _regionsData[regionName]!;
      final targetLocation = region['location'] as LatLng;
      
      print('Navigating to region: $regionName, location: ${targetLocation.latitude},${targetLocation.longitude}');
      print('Starting location: ${widget.searchLocation.latitude},${widget.searchLocation.longitude}');
      
      try {
        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Planning route with air quality data...'))
        );
        
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RouteScreen(
              origin: widget.searchLocation,
              originName: widget.locationName,
              destination: targetLocation,
              destinationName: '$regionName (Air Quality: ${region['quality']})',
              startNavigation: false, // Show route first, don't start navigation directly
            ),
          ),
        ).then((value) {
          // Handle logic after returning from navigation
          print('Returned from route screen');
        }).catchError((error) {
          print('Error during navigation: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to navigate to this region: $error')),
          );
        });
      } catch (e) {
        print('Error creating navigation route: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create navigation route: $e')),
        );
      }
    } else {
      print('Region data not found: $regionName');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get location information for this region')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Surrounding Air Quality',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    if (_isLoading == false)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadAirQualityData,
                        tooltip: 'Refresh Data',
                      ),
                    if (widget.onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_error!, style: TextStyle(color: Colors.red)),
            )
          else if (_regionsData.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Unable to get air quality data'),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sortedRegions.length,
              itemBuilder: (context, index) {
                final regionName = _sortedRegions[index];
                final region = _regionsData[regionName]!;
                final aqi = region['aqi'] as int;
                final quality = region['quality'] as String;
                final color = region['color'] as Color;
                final distance = region['distance'] as double;
                final source = region['source'] as String? ?? 'Air Quality Data';
                final pollutant = region['pollutant'] as String?;
                
                // Different style for main directions
                final isMainDirection = _mainDirections.contains(regionName);
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  elevation: isMainDirection ? 2 : 1,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          backgroundColor: color.withOpacity(0.2),
                          child: Text(
                            '$aqi',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (pollutant != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              pollutant,
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Text(
                          regionName,
                          style: isMainDirection 
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            quality,
                            style: TextStyle(
                              fontSize: 12, 
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Distance: ${distance.toStringAsFixed(1)} km',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Text(
                          'Data source: $source',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    trailing: isMainDirection
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.directions, size: 16),
                            label: const Text('Navigate'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color.withOpacity(0.2),
                              foregroundColor: color,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => _navigateToRegion(regionName),
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _navigateToRegion(regionName),
                  ),
                );
              },
            ),
          // Footer note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8.0),
            alignment: Alignment.center,
            child: Text(
              'This feature uses real-time air quality data from OpenWeatherMap',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
} 