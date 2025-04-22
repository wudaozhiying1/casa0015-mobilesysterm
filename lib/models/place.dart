import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';

class Place {
  final String placeId;
  final String name;
  final String address;
  final LatLng location;
  final String formattedAddress;
  
  Place({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
    this.formattedAddress = '',
  });
  
  @override
  String toString() {
    return 'Place{name: $name, address: $address, location: $location}';
  }
  
  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'name': name,
      'address': address,
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'formattedAddress': formattedAddress,
    };
  }
  
  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      placeId: json['placeId'],
      name: json['name'],
      address: json['address'],
      location: LatLng(
        json['location']['latitude'],
        json['location']['longitude'],
      ),
      formattedAddress: json['formattedAddress'] ?? json['address'] ?? '',
    );
  }
} 