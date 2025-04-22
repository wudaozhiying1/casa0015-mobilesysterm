import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place.dart'; // Import unified Place model
import '../services/search_history_service.dart'; // Import search history service

class GeocodingService {
  // Use provided Google API key
  static const String apiKey = 'AIzaSyB3kdDgM5e1UKLXtdw6CTfaoiOzR66-cmU';
  static const String recentSearchesKey = 'recent_searches';
  static const int maxRecentSearches = 10;
  
  // Save searched places
  static Future<void> saveRecentSearch(Place place) async {
    try {
      // Save to local SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final recentSearchesJson = prefs.getStringList(recentSearchesKey) ?? [];
      final recentSearches = recentSearchesJson
          .map((json) => Place.fromJson(jsonDecode(json)))
          .toList();
      
      // Remove existing places with the same ID
      recentSearches.removeWhere((p) => p.placeId == place.placeId);
      
      // Add new place to the beginning of the list
      recentSearches.insert(0, place);
      
      // If exceeds maximum count, remove the oldest
      if (recentSearches.length > maxRecentSearches) {
        recentSearches.removeLast();
      }
      
      // Save back to SharedPreferences
      final updatedJson = recentSearches
          .map((place) => jsonEncode(place.toJson()))
          .toList();
      
      await prefs.setStringList(recentSearchesKey, updatedJson);
      
      // Also save to Firebase (if user is logged in)
      await SearchHistoryService.addSearchHistory(place);
    } catch (e) {
      debugPrint('Error saving recent search: $e');
    }
  }
  
  // Get recently searched places
  static Future<List<Place>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentSearchesJson = prefs.getStringList(recentSearchesKey) ?? [];
      
      return recentSearchesJson
          .map((json) => Place.fromJson(jsonDecode(json)))
          .toList();
    } catch (e) {
      debugPrint('Error getting recent searches: $e');
      return [];
    }
  }
  
  // Search places - Using the actual Places API
  static Future<List<Place>> searchPlaces(String query) async {
    if (query.isEmpty) return [];
    
    try {
      // Real API call - Place Autocomplete API
      final response = await http.get(
        Uri.parse('https://maps.googleapis.com/maps/api/place/autocomplete/json'
            '?input=${Uri.encodeComponent(query)}'
            '&key=$apiKey'
            '&language=en'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
          debugPrint('Places API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return []; // Return empty list on failure
        }
        
        final predictions = data['predictions'] as List;
        final places = <Place>[];
        
        // Get detailed information for the first 5 results
        for (var i = 0; i < predictions.length && i < 5; i++) {
          final prediction = predictions[i];
          final placeId = prediction['place_id'];
          
          // Get place details to get coordinates
          final placeDetails = await getPlaceDetails(placeId);
          if (placeDetails != null) {
            places.add(placeDetails);
          }
        }
        
        return places;
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        return []; // Return empty list on failure
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
      return []; // Return empty list on error
    }
  }
  
  // Get place details - Using the actual Place Details API
  static Future<Place?> getPlaceDetails(String placeId) async {
    try {
      final response = await http.get(
        Uri.parse('https://maps.googleapis.com/maps/api/place/details/json'
            '?place_id=$placeId'
            '&key=$apiKey'
            '&fields=name,formatted_address,geometry/location'
            '&language=en'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] != 'OK') {
          debugPrint('Place Details API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
        
        final result = data['result'];
        final location = result['geometry']['location'];
        
        return Place(
          placeId: placeId,
          name: result['name'],
          address: result['formatted_address'],
          location: LatLng(
            location['lat'],
            location['lng'],
          ),
          formattedAddress: result['formatted_address'],
        );
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting place details: $e');
      return null;
    }
  }
  
  // Address to coordinates (geocoding) - Using Geocoding API
  static Future<LatLng?> geocodeAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse('https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(address)}'
            '&key=$apiKey'
            '&language=en'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] != 'OK') {
          debugPrint('Geocoding API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return null;
        }
        
        if (data['results'].isEmpty) {
          return null;
        }
        
        final location = data['results'][0]['geometry']['location'];
        return LatLng(location['lat'], location['lng']);
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error geocoding address: $e');
      return null;
    }
  }

  // Reverse geocoding - Get address from coordinates
  static Future<Place?> reverseGeocode(LatLng coordinates) async {
    try {
      final response = await http.get(
        Uri.parse('https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${coordinates.latitude},${coordinates.longitude}'
            '&key=$apiKey'
            '&language=en'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] != 'OK') {
          debugPrint('Reverse Geocoding API error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
          return _createFallbackPlace(coordinates);
        }
        
        if (data['results'].isEmpty) {
          return _createFallbackPlace(coordinates);
        }
        
        final result = data['results'][0];
        final formattedAddress = result['formatted_address'];
        
        // Try to get a more friendly name
        String name = formattedAddress;
        if (result['address_components'] != null) {
          final components = result['address_components'] as List;
          // Try to use POI, street name, or other meaningful component as name
          for (var component in components) {
            final types = component['types'] as List;
            if (types.contains('point_of_interest') || 
                types.contains('establishment') ||
                types.contains('route') ||
                types.contains('neighborhood') ||
                types.contains('sublocality_level_1')) {
              name = component['long_name'];
              break;
            }
          }
        }
        
        return Place(
          placeId: result['place_id'] ?? 'place_${coordinates.latitude}_${coordinates.longitude}',
          name: name,
          address: formattedAddress,
          location: coordinates,
          formattedAddress: formattedAddress,
        );
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        return _createFallbackPlace(coordinates);
      }
    } catch (e) {
      debugPrint('Error in reverse geocoding: $e');
      return _createFallbackPlace(coordinates);
    }
  }
  
  // Create fallback place (when API fails)
  static Place _createFallbackPlace(LatLng coordinates) {
    final lat = coordinates.latitude.toStringAsFixed(5);
    final lng = coordinates.longitude.toStringAsFixed(5);
    final address = 'Coordinates: $lat, $lng';
    
    return Place(
      placeId: 'place_${coordinates.latitude}_${coordinates.longitude}',
      name: 'Selected Location',
      address: address,
      location: coordinates,
      formattedAddress: address,
    );
  }

  // Get geocoding information - Get Placemark from coordinates
  static Future<List<Place>> getPlacemarkFromCoordinates(double latitude, double longitude) async {
    try {
      final place = await reverseGeocode(LatLng(latitude, longitude));
      
      if (place != null) {
        return [place];
      }
      return [];
    } catch (e) {
      debugPrint('Error getting placemark from coordinates: $e');
      return [];
    }
  }
} 