import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/place.dart';

class FavoritesService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Get current user ID
  static String? get _userId => _auth.currentUser?.uid;
  
  // Check if user is logged in
  static bool get isUserLoggedIn => _userId != null;
  
  // Favorites collection reference
  static CollectionReference _getFavoritesCollection() {
    if (_userId == null) {
      throw Exception('User not logged in, cannot access favorites');
    }
    
    return _firestore.collection('users')
                     .doc(_userId)
                     .collection('favorites');
  }
  
  // Add a favorite
  static Future<void> addFavorite(Place place) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot add favorite');
      return;
    }
    
    try {
      // Prepare data to save
      final favoriteData = {
        'placeId': place.placeId,
        'name': place.name,
        'address': place.address,
        'location': {
          'latitude': place.location.latitude,
          'longitude': place.location.longitude,
        },
        'formattedAddress': place.formattedAddress,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      // Check if the same place is already favorited
      final query = await _getFavoritesCollection()
          .where('placeId', isEqualTo: place.placeId)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        // If exists, update timestamp
        await _getFavoritesCollection()
            .doc(query.docs.first.id)
            .update({'timestamp': FieldValue.serverTimestamp()});
      } else {
        // If not exists, create new record
        await _getFavoritesCollection().add(favoriteData);
      }
      
    } catch (e) {
      debugPrint('Failed to add favorite: $e');
    }
  }
  
  // Get user's favorites
  static Future<List<Place>> getFavorites() async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot get favorites');
      return [];
    }
    
    try {
      final snapshot = await _getFavoritesCollection()
          .orderBy('timestamp', descending: true)
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final locationMap = data['location'] as Map<String, dynamic>;
        
        return Place(
          placeId: data['placeId'],
          name: data['name'],
          address: data['address'],
          location: LatLng(
            locationMap['latitude'],
            locationMap['longitude'],
          ),
          formattedAddress: data['formattedAddress'] ?? data['address'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to get favorites: $e');
      return [];
    }
  }
  
  // Remove a favorite
  static Future<void> removeFavorite(String placeId) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot remove favorite');
      return;
    }
    
    try {
      final query = await _getFavoritesCollection()
          .where('placeId', isEqualTo: placeId)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        await _getFavoritesCollection().doc(query.docs.first.id).delete();
      }
    } catch (e) {
      debugPrint('Failed to remove favorite: $e');
    }
  }
  
  // Check if a place is favorited
  static Future<bool> isFavorite(String placeId) async {
    if (!isUserLoggedIn) {
      return false;
    }
    
    try {
      final query = await _getFavoritesCollection()
          .where('placeId', isEqualTo: placeId)
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check favorite status: $e');
      return false;
    }
  }
  
  // Get favorites count
  static Future<int> getFavoritesCount() async {
    if (!isUserLoggedIn) {
      return 0;
    }
    
    try {
      final snapshot = await _getFavoritesCollection().count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Failed to get favorites count: $e');
      return 0;
    }
  }
  
  // Clear all favorites
  static Future<void> clearAllFavorites() async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot clear favorites');
      return;
    }
    
    try {
      final snapshot = await _getFavoritesCollection().get();
      
      for (var doc in snapshot.docs) {
        await _getFavoritesCollection().doc(doc.id).delete();
      }
    } catch (e) {
      debugPrint('Failed to clear favorites: $e');
    }
  }
} 