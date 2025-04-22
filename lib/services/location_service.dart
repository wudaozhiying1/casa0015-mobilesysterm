import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../models/place.dart';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';

class LocationService with ChangeNotifier {
  Position? _currentPosition;
  bool _isLoading = false;

  Position? get currentPosition => _currentPosition;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    await _checkPermissions();
    await getCurrentLocation();
  }

  Future<void> _checkPermissions() async {
    try {
      var locationStatus = await Permission.location.status;
      if (locationStatus.isDenied) {
        locationStatus = await Permission.location.request();
        if (locationStatus.isDenied) {
          debugPrint('Location permission denied');
          return;
        }
      }
      
      if (locationStatus.isPermanentlyDenied) {
        debugPrint('Location permission permanently denied');
        return;
      }
    } catch (e) {
      debugPrint('Error checking permissions: $e');
    }
  }

  Future<void> getCurrentLocation() async {
    try {
      _isLoading = true;
      notifyListeners();

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        _isLoading = false;
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          _isLoading = false;
          notifyListeners();
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        _isLoading = false;
        notifyListeners();
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Error getting location: $e');
    }
  }

  // Request location permission and return whether permission was granted
  Future<bool> requestPermission() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return false;
      }

      // Check application permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return false;
      }
      
      // Permission granted
      return true;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  // Get address from coordinates using official geocoding package
  Future<Place> getPlaceFromCoordinatesUsingGeocoding(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        String address = [
          placemark.street,
          placemark.subLocality,
          placemark.locality,
          placemark.postalCode,
          placemark.country,
        ].where((element) => element != null && element.isNotEmpty).join(', ');
        
        return Place(
          placeId: DateTime.now().millisecondsSinceEpoch.toString(),
          name: placemark.name ?? placemark.locality ?? 'Unknown location',
          address: address,
          location: latLng,
          formattedAddress: address,
        );
      } else {
        return Place(
          placeId: DateTime.now().millisecondsSinceEpoch.toString(),
          name: 'Unknown location',
          address: 'Coordinates: ${latLng.latitude}, ${latLng.longitude}',
          location: latLng,
          formattedAddress: 'Coordinates: ${latLng.latitude}, ${latLng.longitude}',
        );
      }
    } catch (e) {
      debugPrint('Error getting place from coordinates using geocoding: $e');
      return Place(
        placeId: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Unknown location',
        address: 'Coordinates: ${latLng.latitude}, ${latLng.longitude}',
        location: latLng,
        formattedAddress: 'Coordinates: ${latLng.latitude}, ${latLng.longitude}',
      );
    }
  }

  // Get coordinates from address using official geocoding package
  Future<List<Place>> searchPlacesUsingGeocoding(String query) async {
    try {
      List<Location> locations = await locationFromAddress(query);
      
      List<Place> places = [];
      
      for (var location in locations) {
        LatLng latLng = LatLng(location.latitude, location.longitude);
        
        // Get detailed address information for this coordinate
        Place place = await getPlaceFromCoordinatesUsingGeocoding(latLng);
        places.add(place);
      }
      
      return places;
    } catch (e) {
      debugPrint('Error searching places using geocoding: $e');
      return [];
    }
  }
} 