import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/air_quality_controller.dart';

class AirQualityButton extends StatelessWidget {
  /// Callback when map boundaries change, used to update heatmap data
  final Function(LatLngBounds bounds)? onMapBoundsChanged;
  
  const AirQualityButton({
    Key? key,
    this.onMapBoundsChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AirQualityController>(
      builder: (context, controller, child) {
        return FloatingActionButton(
          heroTag: 'airQualityButton',
          mini: true,
          backgroundColor: controller.isVisible
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
          foregroundColor: controller.isVisible
              ? Colors.white
              : Colors.black54,
          onPressed: () async {
            // Toggle heatmap visibility
            controller.toggleVisibility();
            
            // If the heatmap becomes visible, try to get air quality data
            if (controller.isVisible) {
              // Show loading notification
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Loading air quality data, please wait...'),
                  duration: Duration(seconds: 2),
                ),
              );
              
              try {
                // Call the callback to get heatmap data for the current location
                if (onMapBoundsChanged != null) {
                  // Create an empty boundary, the actual center position will be determined by the callback function
                  final dummyBounds = LatLngBounds(
                    southwest: const LatLng(0, 0),
                    northeast: const LatLng(0, 0)
                  );
                  
                  // Call the map boundary change callback
                  onMapBoundsChanged!(dummyBounds);
                } else {
                  // If no callback is provided, use the default location
                  LatLng center = const LatLng(51.5074, -0.1278);
                  await controller.generateHeatmapForLocation(center, radius: 0.05);
                }
                
                // Check if data was successfully retrieved
                if (controller.heatmapData.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to get air quality data, please try moving to another area or try again later'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                } else {
                  print('Successfully retrieved ${controller.heatmapData.length} air quality data points');
                }
              } catch (e) {
                print('Failed to get air quality data: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to get air quality data: ${e.toString()}'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          },
          child: Icon(
            controller.isVisible 
                ? Icons.cloud_done 
                : Icons.cloud_outlined,
          ),
          tooltip: controller.isVisible ? 'Hide air quality layer' : 'Show air quality layer',
        );
      },
    );
  }
} 