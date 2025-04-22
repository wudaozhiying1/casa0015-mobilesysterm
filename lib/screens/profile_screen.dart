import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/search_history_service.dart';
import '../services/favorites_service.dart';
import '../services/route_history_service.dart';
import 'login_screen.dart';
import 'search_history_screen.dart';
import 'favorites_screen.dart';
import 'route_history_screen.dart';
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  int _searchHistoryCount = 0;
  int _favoritesCount = 0;
  int _routeHistoryCount = 0;
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSearchHistoryCount();
    _loadFavoritesCount();
    _loadRouteHistoryCount();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userData = await authService.getUserData();
      
      if (mounted) {
        setState(() {
          _userData = userData;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load user data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSearchHistoryCount() async {
    try {
      final count = await SearchHistoryService.getSearchHistoryCount();
      if (mounted) {
        setState(() {
          _searchHistoryCount = count;
        });
      }
    } catch (e) {
      debugPrint('Failed to get search history count: $e');
    }
  }

  Future<void> _loadFavoritesCount() async {
    try {
      final count = await FavoritesService.getFavoritesCount();
      if (mounted) {
        setState(() {
          _favoritesCount = count;
        });
      }
    } catch (e) {
      debugPrint('Failed to get favorites count: $e');
    }
  }

  Future<void> _loadRouteHistoryCount() async {
    try {
      final count = await RouteHistoryService.getRouteHistoryCount();
      if (mounted) {
        setState(() {
          _routeHistoryCount = count;
        });
      }
    } catch (e) {
      debugPrint('Failed to get route history count: $e');
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      
      // After signing out, close the current page and return to the app's root navigation
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign out: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _viewSearchHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchHistoryScreen(),
      ),
    ).then((_) => _loadSearchHistoryCount());
  }

  void _viewFavorites() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FavoritesScreen(),
      ),
    ).then((_) => _loadFavoritesCount());
  }

  void _viewRouteHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RouteHistoryScreen(),
      ),
    ).then((_) => _loadRouteHistoryCount());
  }

  Future<void> _clearSearchHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Search History'),
        content: const Text('Are you sure you want to clear all search history? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await SearchHistoryService.clearAllSearchHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Search history has been cleared')),
          );
          _loadSearchHistoryCount();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear search history: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Choose and upload user avatar
  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500, // Reduce resolution to decrease Base64 data size
        maxHeight: 500,
        imageQuality: 80, // Appropriate compression
      );
      
      if (image == null) return;
      
      setState(() {
        _isLoading = true;
      });
      
      // Convert image to File object
      final File imageFile = File(image.path);
      _profileImage = imageFile;
      
      // Upload avatar using Base64 method
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.uploadProfileImage(imageFile);
      
      // Refresh user data
      _loadUserData();
      
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar uploaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload avatar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;
    final String? profileImageUrl = _userData?['profileImageUrl'];
    final String? profileImageBase64 = _userData?['profileImageBase64'];
    
    // Function to display user avatar
    Widget userAvatar() {
      if (profileImageUrl != null) {
        // Load avatar from URL
        return CircleAvatar(
          radius: 40,
          backgroundColor: Theme.of(context).primaryColor,
          backgroundImage: NetworkImage(profileImageUrl),
        );
      } else if (profileImageBase64 != null) {
        // Load avatar from Base64
        return CircleAvatar(
          radius: 40,
          backgroundColor: Theme.of(context).primaryColor,
          backgroundImage: MemoryImage(base64Decode(profileImageBase64)),
        );
      } else {
        // Display default avatar (user's first letter)
        return CircleAvatar(
          radius: 40,
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            currentUser?.email?.substring(0, 1).toUpperCase() ?? 'U',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadUserData();
              _loadSearchHistoryCount();
              _loadFavoritesCount();
              _loadRouteHistoryCount();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User avatar and basic info card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // User avatar
                          Stack(
                            children: [
                              userAvatar(),
                              // Upload avatar button
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: currentUser != null ? _pickAndUploadImage : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          
                          // User basic info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Email: ${currentUser?.email ?? 'Not logged in'}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'User ID: ${currentUser?.uid ?? 'N/A'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (_userData != null && _userData!['lastLogin'] != null)
                                  Text(
                                    'Last login: ${_formatTimestamp(_userData!['lastLogin'])}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Data statistics card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Data',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  icon: Icons.history,
                                  label: 'Search History',
                                  value: _searchHistoryCount.toString(),
                                  onTap: _viewSearchHistory,
                                ),
                              ),
                              Expanded(
                                child: _buildStatItem(
                                  icon: Icons.favorite,
                                  label: 'Favorites',
                                  value: _favoritesCount.toString(),
                                  onTap: _viewFavorites,
                                ),
                              ),
                              Expanded(
                                child: _buildStatItem(
                                  icon: Icons.route,
                                  label: 'Route History',
                                  value: _routeHistoryCount.toString(),
                                  onTap: _viewRouteHistory,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Features list
                  Card(
                    elevation: 4,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: const Text('Search History'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _viewSearchHistory,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.favorite, color: Colors.red),
                          title: const Text('My Favorites'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _viewFavorites,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.route, color: Colors.blue),
                          title: const Text('Route History'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _viewRouteHistory,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Account management
                  Card(
                    elevation: 4,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.delete_forever, color: Colors.orange),
                          title: const Text('Clear Search History'),
                          onTap: _clearSearchHistory,
                        ),
                        const Divider(height: 1),
                        if (currentUser != null)
                          ListTile(
                            leading: const Icon(Icons.exit_to_app, color: Colors.red),
                            title: const Text('Sign Out'),
                            onTap: _signOut,
                          )
                        else
                          ListTile(
                            leading: const Icon(Icons.login, color: Colors.green),
                            title: const Text('Login/Register'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              ).then((_) => _loadUserData());
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Version info
                  Center(
                    child: Text(
                      'AirMark Version 1.0.0',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
  
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTimestamp(dynamic timestamp) {
    try {
      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else if (timestamp.runtimeType.toString().contains('Timestamp')) {
        // Firebase Timestamp object
        dateTime = DateTime.fromMillisecondsSinceEpoch(
          timestamp.millisecondsSinceEpoch
        );
      } else {
        return 'Unknown format';
      }
      
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('Error formatting timestamp: $e');
      return 'Invalid date';
    }
  }
} 