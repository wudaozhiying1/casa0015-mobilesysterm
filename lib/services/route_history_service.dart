import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/place.dart';

class RouteHistoryItem {
  final String id;
  final Place origin;
  final Place destination;
  final String distance;
  final String duration;
  final DateTime timestamp;
  final String routeType;
  
  RouteHistoryItem({
    required this.id,
    required this.origin,
    required this.destination,
    required this.distance,
    required this.duration,
    required this.timestamp,
    required this.routeType,
  });
  
  factory RouteHistoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final originData = data['origin'] as Map<String, dynamic>;
    final originLocation = originData['location'] as Map<String, dynamic>;
    
    final destinationData = data['destination'] as Map<String, dynamic>;
    final destinationLocation = destinationData['location'] as Map<String, dynamic>;
    
    return RouteHistoryItem(
      id: doc.id,
      origin: Place(
        placeId: originData['placeId'],
        name: originData['name'],
        address: originData['address'],
        location: LatLng(
          originLocation['latitude'],
          originLocation['longitude'],
        ),
        formattedAddress: originData['formattedAddress'] ?? originData['address'],
      ),
      destination: Place(
        placeId: destinationData['placeId'],
        name: destinationData['name'],
        address: destinationData['address'],
        location: LatLng(
          destinationLocation['latitude'],
          destinationLocation['longitude'],
        ),
        formattedAddress: destinationData['formattedAddress'] ?? destinationData['address'],
      ),
      distance: data['distance'],
      duration: data['duration'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      routeType: data['routeType'] ?? 'Fastest Route',
    );
  }
  
  Map<String, dynamic> toFirestore() {
    return {
      'origin': {
        'placeId': origin.placeId,
        'name': origin.name,
        'address': origin.address,
        'location': {
          'latitude': origin.location.latitude,
          'longitude': origin.location.longitude,
        },
        'formattedAddress': origin.formattedAddress,
      },
      'destination': {
        'placeId': destination.placeId,
        'name': destination.name,
        'address': destination.address,
        'location': {
          'latitude': destination.location.latitude,
          'longitude': destination.location.longitude,
        },
        'formattedAddress': destination.formattedAddress,
      },
      'distance': distance,
      'duration': duration,
      'timestamp': Timestamp.fromDate(timestamp),
      'routeType': routeType,
    };
  }
}

class RouteHistoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Get current user ID
  static String? get _userId => _auth.currentUser?.uid;
  
  // Check if user is logged in
  static bool get isUserLoggedIn => _userId != null;
  
  // Route history collection reference
  static CollectionReference _getRouteHistoryCollection() {
    if (_userId == null) {
      throw Exception('User not logged in, cannot access route history');
    }
    
    return _firestore.collection('users')
                     .doc(_userId)
                     .collection('routeHistory');
  }
  
  // Add route history
  static Future<void> addRouteHistory({
    required Place origin,
    required Place destination,
    required String distance,
    required String duration,
    String routeType = 'Fastest Route',
  }) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot add route history');
      return;
    }
    
    try {
      final routeHistoryItem = RouteHistoryItem(
        id: '', // Firestore will automatically generate ID
        origin: origin,
        destination: destination,
        distance: distance,
        duration: duration,
        timestamp: DateTime.now(),
        routeType: routeType,
      );
      
      await _getRouteHistoryCollection().add(routeHistoryItem.toFirestore());
      debugPrint('Route history added successfully: ${origin.name} to ${destination.name}');
    } catch (e) {
      debugPrint('Failed to add route history: $e');
    }
  }
  
  // Get route history
  static Future<List<RouteHistoryItem>> getRouteHistory({int limit = 20}) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot get route history');
      return [];
    }
    
    try {
      final snapshot = await _getRouteHistoryCollection()
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
      
      return snapshot.docs
        .map((doc) => RouteHistoryItem.fromFirestore(doc))
        .toList();
    } catch (e) {
      debugPrint('Failed to get route history: $e');
      return [];
    }
  }
  
  // Delete route history
  static Future<void> deleteRouteHistory(String routeId) async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot delete route history');
      return;
    }
    
    try {
      await _getRouteHistoryCollection().doc(routeId).delete();
    } catch (e) {
      debugPrint('Failed to delete route history: $e');
    }
  }
  
  // Clear all route history
  static Future<void> clearAllRouteHistory() async {
    if (!isUserLoggedIn) {
      debugPrint('User not logged in, cannot clear route history');
      return;
    }
    
    try {
      final snapshot = await _getRouteHistoryCollection().get();
      
      for (var doc in snapshot.docs) {
        await _getRouteHistoryCollection().doc(doc.id).delete();
      }
    } catch (e) {
      debugPrint('Failed to clear route history: $e');
    }
  }
  
  // Get route history count
  static Future<int> getRouteHistoryCount() async {
    if (!isUserLoggedIn) {
      return 0;
    }
    
    try {
      final snapshot = await _getRouteHistoryCollection().count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Failed to get route history count: $e');
      return 0;
    }
  }
} 