import '../widgets/air_quality_overlay.dart';

class MapScreen extends StatefulWidget {
  // ... (existing code)
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ... (existing code)

  @override
  Widget build(BuildContext context) {
    // ... (existing code)
    
    return Scaffold(
      // ... (existing code)
      body: Stack(
        children: [
          _buildMap(),
          if (_showAirQuality && _airQualityService.heatmapData.isNotEmpty)
            Positioned.fill(
              child: AirQualityOverlay(
                data: _airQualityService.heatmapData,
                opacity: 0.6,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      // ... (existing GoogleMap attributes)
      markers: _markers,
      polylines: _polylines,
      onMapCreated: _onMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: true,
      initialCameraPosition: _initialCameraPosition,
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
      onTap: _onMapTapped,
      zoomControlsEnabled: false,
    );
  }

  // ... (rest of the existing code)
} 