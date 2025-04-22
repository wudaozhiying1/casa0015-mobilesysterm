import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/place.dart';

class SearchHistoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Get current user ID
  static String? get _userId => _auth.currentUser?.uid;
  
  // Check if user is logged in
  static bool get isUserLoggedIn => _userId != null;
  
  // Search history collection reference
  static CollectionReference _getSearchHistoryCollection() {
    if (_userId == null) {
      throw Exception('User not logged in, cannot access search history');
    }
    
    return _firestore.collection('users')
                     .doc(_userId)
                     .collection('search_history');
  }
  
  // Add search history record
  static Future<void> addSearchHistory(Place place) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot save search history');
      return;
    }
    
    try {
      // Prepare data to save
      final searchData = {
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
      
      // Query if there's already a record with the same place
      final query = await _getSearchHistoryCollection()
          .where('placeId', isEqualTo: place.placeId)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        // If exists, update timestamp
        await _getSearchHistoryCollection()
            .doc(query.docs.first.id)
            .update({'timestamp': FieldValue.serverTimestamp()});
      } else {
        // If not exists, create new record
        await _getSearchHistoryCollection().add(searchData);
      }
      
      // Clean up search history (only keep recent 20 records)
      await _cleanupSearchHistory();
    } catch (e) {
      debugPrint('Failed to save search history: $e');
    }
  }
  
  // Get user's search history
  static Future<List<Place>> getSearchHistory() async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot get search history');
      return [];
    }
    
    try {
      final snapshot = await _getSearchHistoryCollection()
          .orderBy('timestamp', descending: true)
          .limit(20)
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
      debugPrint('Failed to get search history: $e');
      return [];
    }
  }
  
  // Clean up search history (only keep recent 20 records)
  static Future<void> _cleanupSearchHistory() async {
    try {
      final snapshot = await _getSearchHistoryCollection()
          .orderBy('timestamp', descending: true)
          .get();
      
      if (snapshot.docs.length > 20) {
        final docsToDelete = snapshot.docs.sublist(20);
        
        for (var doc in docsToDelete) {
          await _getSearchHistoryCollection().doc(doc.id).delete();
        }
      }
    } catch (e) {
      debugPrint('Failed to clean up search history: $e');
    }
  }
  
  // Clear all search history
  static Future<void> clearAllSearchHistory() async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot clear search history');
      return;
    }
    
    try {
      final snapshot = await _getSearchHistoryCollection().get();
      
      for (var doc in snapshot.docs) {
        await _getSearchHistoryCollection().doc(doc.id).delete();
      }
    } catch (e) {
      debugPrint('Failed to clear search history: $e');
    }
  }
  
  // Get search history count
  static Future<int> getSearchHistoryCount() async {
    if (!isUserLoggedIn) {
      return 0;
    }
    
    try {
      final snapshot = await _getSearchHistoryCollection().count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Failed to get search history count: $e');
      return 0;
    }
  }
} 