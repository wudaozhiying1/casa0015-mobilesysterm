import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'controllers/air_quality_controller.dart';
import 'services/air_quality_service.dart';
import 'services/geocoding_service.dart';
import 'services/location_service.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/place_details_screen.dart';
import 'screens/route_planner_screen.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

// Add global route observer for debugging
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Capture global errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };
  
  // Capture platform exceptions
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform error: $error');
    return true;
  };
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => LocationService()),
        ChangeNotifierProvider(create: (context) => AirQualityService()),
        ChangeNotifierProxyProvider<AirQualityService, AirQualityController>(
          create: (context) => AirQualityController(
            Provider.of<AirQualityService>(context, listen: false)
          ),
          update: (context, service, controller) => 
              controller ?? AirQualityController(service),
        ),
        ChangeNotifierProvider(create: (context) => AuthService()),
      ],
      child: MaterialApp(
        title: 'Air Quality Map',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        navigatorObservers: [routeObserver], // Add route observer
        home: _AuthWrapper(),
        routes: {
          // Remove '/' route as the initial page is already set in the home property
          // '/': (context) => FutureBuilder(...),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/placeDetails') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => PlaceDetailsScreen(
                place: args['place'],
                currentLocation: args['currentLocation'],
                isStartPoint: args['isStartPoint'] ?? false,
              ),
            );
          } else if (settings.name == '/routePlanner') {
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (context) => RoutePlannerScreen(
                initialEndPlace: args?['endPlace'],
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}

// Authentication wrapper that decides which page to display based on auth status
class _AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Firebase has already been initialized in the main() method, no need to initialize again
    // Directly monitor authentication status
    return StreamBuilder<User?>(
      stream: Provider.of<AuthService>(context).authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        
        // User is logged in, show home screen
        if (authSnapshot.hasData) {
          return const HomeScreen();
        }
        
        // User is not logged in, show login screen
        return const LoginScreen();
      },
    );
  }
}
