import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/air_quality_service.dart';

class SubmitMeasurementScreen extends StatefulWidget {
  final LatLng? location;
  
  const SubmitMeasurementScreen({
    super.key,
    this.location,
  });

  @override
  State<SubmitMeasurementScreen> createState() => _SubmitMeasurementScreenState();
}

class _SubmitMeasurementScreenState extends State<SubmitMeasurementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aqiController = TextEditingController();
  final _pm25Controller = TextEditingController();
  final _pm10Controller = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _aqiController.dispose();
    _pm25Controller.dispose();
    _pm10Controller.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Air Quality Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _aqiController,
                decoration: const InputDecoration(
                  labelText: 'AQI Index',
                  hintText: 'Please enter AQI index',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter AQI index';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pm25Controller,
                decoration: const InputDecoration(
                  labelText: 'PM2.5 (μg/m³)',
                  hintText: 'Please enter PM2.5 value',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter PM2.5 value';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pm10Controller,
                decoration: const InputDecoration(
                  labelText: 'PM10 (μg/m³)',
                  hintText: 'Please enter PM10 value',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter PM10 value';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Please enter notes (optional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitMeasurement,
                child: const Text('Submit Data'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitMeasurement() async {
    if (_formKey.currentState!.validate()) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      final airQualityService = Provider.of<AirQualityService>(context, listen: false);
      
      if (locationService.currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get location information')),
        );
        return;
      }

      final measurement = {
        'aqi': int.parse(_aqiController.text),
        'pm25': double.parse(_pm25Controller.text),
        'pm10': double.parse(_pm10Controller.text),
        'notes': _notesController.text,
      };

      await airQualityService.submitUserMeasurement(
        locationService.currentPosition!.latitude,
        locationService.currentPosition!.longitude,
        measurement,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data submitted successfully')),
        );
        Navigator.pop(context);
      }
    }
  }
} 