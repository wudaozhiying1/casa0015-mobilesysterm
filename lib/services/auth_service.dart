import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // Current user
  User? get currentUser => _auth.currentUser;
  
  // Authentication state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Whether user is logged in
  bool get isLoggedIn => currentUser != null;
  
  // Register with email and password
  Future<UserCredential?> registerWithEmailAndPassword(String email, String password) async {
    try {
      // Create user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Create user document in Firestore
      if (credential.user != null) {
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
      
      notifyListeners();
      return credential;
    } catch (e) {
      rethrow;
    }
  }
  
  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update last login time
      if (credential.user != null) {
        try {
          // First check if user document exists
          final docSnapshot = await _firestore.collection('users').doc(credential.user!.uid).get();
          
          if (docSnapshot.exists) {
            // Document exists, update last login time
            await _firestore.collection('users').doc(credential.user!.uid).update({
              'lastLogin': FieldValue.serverTimestamp(),
            });
          } else {
            // Document doesn't exist, create new document
            await _firestore.collection('users').doc(credential.user!.uid).set({
              'email': email,
              'createdAt': FieldValue.serverTimestamp(),
              'lastLogin': FieldValue.serverTimestamp(),
            });
          }
        } catch (firestoreError) {
          // Even if Firestore operation fails, don't prevent user from logging in
          print('Failed to update user login time: $firestoreError');
        }
      }
      
      notifyListeners();
      return credential;
    } catch (e) {
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
  
  // Get user data
  Future<Map<String, dynamic>?> getUserData() async {
    if (currentUser == null) return null;
    
    try {
      final doc = await _firestore.collection('users').doc(currentUser!.uid).get();
      return doc.data();
    } catch (e) {
      return null;
    }
  }
  
  // Upload user avatar (using Base64 method)
  Future<void> uploadProfileImage(File imageFile) async {
    if (currentUser == null) {
      throw Exception('User not logged in, cannot upload avatar');
    }
    
    try {
      // Read file as byte array
      final bytes = await imageFile.readAsBytes();
      
      // Convert image to Base64 encoded string
      // Note: This method is suitable for small images, larger images will make Firestore document too large
      final base64Image = base64Encode(bytes);
      
      // Ensure user document exists
      final userDoc = await _firestore.collection('users').doc(currentUser!.uid).get();
      if (!userDoc.exists) {
        await _firestore.collection('users').doc(currentUser!.uid).set({
          'email': currentUser!.email,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp()
        });
      }
      
      // Directly update user document, including Base64 encoded avatar
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'profileImageBase64': base64Image,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      notifyListeners();
    } catch (e) {
      print('Failed to save Base64 avatar: $e');
      throw Exception('Failed to upload avatar: $e');
    }
  }
  
  // Handle Firebase error messages
  String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found for that email';
      case 'wrong-password':
        return 'Wrong password';
      case 'email-already-in-use':
        return 'The email address is already in use';
      case 'weak-password':
        return 'The password is too weak';
      case 'invalid-email':
        return 'The email address is invalid';
      case 'operation-not-allowed':
        return 'This operation is not allowed';
      case 'too-many-requests':
        return 'Too many requests, please try again later';
      default:
        return 'An error occurred: ${e.code}';
    }
  }
} 