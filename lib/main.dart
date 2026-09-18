// নিম্নলিখিত প্যাকেজগুলি অবশ্যই pubspec.yaml-এ যুক্ত করতে হবে:
// geolocator: ^11.0.0
// share_plus: ^8.0.0
// url_launcher: ^6.2.2
// image_cropper: ^5.1.0
// image_picker: ^1.1.2
// file_picker: ^6.1.1
// path_provider: ^2.1.1
import 'dart:convert';
import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as prefs;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

String? _firebaseInitializationError;

class SharedPreferences {
  final prefs.SharedPreferences _local;
  static StreamSubscription<DocumentSnapshot>? _firestoreSubscription;

  SharedPreferences._(this._local);

  static Future<SharedPreferences> getInstance() async {
    final local = await prefs.SharedPreferences.getInstance();
    if (Firebase.apps.isNotEmpty) {
      _backgroundRefresh(local);
    }
    return SharedPreferences._(local);
  }

  static Future<void> _backgroundRefresh(prefs.SharedPreferences local) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('wifihaat').doc('app_data').get();
      final data = snapshot.data();
      if (data != null) {
        for (final entry in data.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is String) {
            final current = local.getString(key);
            if (current != value) await local.setString(key, value);
          } else if (value is bool) {
            final current = local.getBool(key);
            if (current != value) await local.setBool(key, value);
          } else if (value is int) {
            final current = local.getInt(key);
            if (current != value) await local.setInt(key, value);
          } else if (value is double) {
            final current = local.getDouble(key);
            if (current != value) await local.setDouble(key, value);
          } else if (value is List) {
            final current = local.getStringList(key);
            final listValue = value.cast<String>();
            if (current != listValue) await local.setStringList(key, listValue);
          }
        }
      }
    } catch (error) {
      debugPrint('Firebase background refresh failed: $error');
    }
  }

  static Future<void> refresh() async {
    final local = await prefs.SharedPreferences.getInstance();
    await _backgroundRefresh(local);
  }

  static void startFirestoreListener() {
    if (_firestoreSubscription != null) return;
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('wifihaat')
        .doc('app_data')
        .snapshots()
        .listen((snapshot) {
      _applyFirestoreData(snapshot.data());
    });
  }

  static Future<void> _applyFirestoreData(Map<String, dynamic>? data) async {
    if (data == null) return;
    try {
      final local = await prefs.SharedPreferences.getInstance();
      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value is String) {
          final current = local.getString(key);
          if (current != value) await local.setString(key, value);
        } else if (value is bool) {
          final current = local.getBool(key);
          if (current != value) await local.setBool(key, value);
        } else if (value is int) {
          final current = local.getInt(key);
          if (current != value) await local.setInt(key, value);
        } else if (value is double) {
          final current = local.getDouble(key);
          if (current != value) await local.setDouble(key, value);
        } else if (value is List) {
          final current = local.getStringList(key);
          final listValue = value.cast<String>();
          if (current != listValue) await local.setStringList(key, listValue);
        }
      }
    } catch (error) {
      debugPrint('Firestore listener update failed: $error');
    }
  }

  String? getString(String key) => _local.getString(key);
  List<String>? getStringList(String key) => _local.getStringList(key);
  double? getDouble(String key) => _local.getDouble(key);
  int? getInt(String key) => _local.getInt(key);

  Future<void> _sync(String key, Object? value) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('wifihaat').doc('app_data').set({key: value}, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Firebase write skipped: $error');
    }
  }

  Future<bool> setString(String key, String value) async {
    final result = await _local.setString(key, value);
    await _sync(key, value);
    return result;
  }
  Future<bool> setStringList(String key, List<String> value) async {
    final result = await _local.setStringList(key, value);
    await _sync(key, value);
    return result;
  }
  Future<bool> setDouble(String key, double value) async {
    final result = await _local.setDouble(key, value);
    await _sync(key, value);
    return result;
  }
  Future<bool> setInt(String key, int value) async {
    final result = await _local.setInt(key, value);
    await _sync(key, value);
    return result;
  }
  Future<bool> remove(String key) async {
    final result = await _local.remove(key);
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('wifihaat').doc('app_data').update({key: FieldValue.delete()});
      } catch (error) {
        debugPrint('Firebase delete skipped: $error');
      }
    }
    return result;
  }
}

Future<void> _initializeFirebase() async {
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      await Firebase.initializeApp();
    }
    SharedPreferences.startFirestoreListener();
  } catch (error) {
    _firebaseInitializationError = error.toString();
    debugPrint('Firebase is not configured: $error');
  }
}
// ** NOTE: Uncomment this if you have added image_cropper to pubspec.yaml **
// import 'package:image_cropper/image_cropper.dart';
class FirebaseLoadingScreen extends StatelessWidget {
  const FirebaseLoadingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('চলছে...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WifiCardApp());
}

ImageProvider? _logoImage(String? encodedLogo) {
  if (encodedLogo == null || encodedLogo.isEmpty) return null;
  try {
    return MemoryImage(Uint8List.fromList(base64Decode(encodedLogo)));
  } catch (_) {
    return null;
  }
}

class WifiCardApp extends StatelessWidget {
  const WifiCardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi Zone Manager',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        // Cobalt Sky Color Scheme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0047AB), // Cobalt Blue
          primary: const Color(0xFF0047AB), // Deep Cobalt
          secondary: const Color(0xFF00B4D8), // Bright Sky Blue
          tertiary: const Color(0xFFCAF0F8), // Pale Sky
          surface: const Color(0xFFF0F9FF), // Very Light Alice Blue
          surfaceContainer: Colors.white,
          onSurface: const Color(0xFF0F172A), // Dark Slate for Text
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F9FF),
       
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: const Color(0xFF00B4D8).withOpacity(0.2)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF0047AB),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0047AB), letterSpacing: -0.5),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0047AB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            elevation: 4,
            shadowColor: const Color(0xFF0047AB).withOpacity(0.4),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF00B4D8).withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF00B4D8).withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0047AB), width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          prefixIconColor: const Color(0xFF0047AB),
          labelStyle: TextStyle(color: const Color(0xFF0047AB).withOpacity(0.7)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  bool _firebaseReady = false;
  String? _firebaseError;

  @override
  void initState() {
    super.initState();
    _initFirebaseWithTimeout();
  }

  Future<void> _initFirebaseWithTimeout() async {
    try {
      final timeout = Future.delayed(const Duration(seconds: 30));
      final init = _initializeFirebase();
      final result = await Future.any([init, timeout]);
      if (result == timeout) {
        setState(() => _firebaseError = 'Firebase সার্ভারে সংযোগ করতে সময় শেষ হয়েছে।');
      } else {
        setState(() => _firebaseReady = true);
      }
    } catch (e) {
      setState(() => _firebaseError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_firebaseReady && _firebaseError == null) {
      return const FirebaseLoadingScreen();
    }
    if (_firebaseError != null) {
      debugPrint('Firebase init error: $_firebaseError');
    }
    if (Firebase.apps.isEmpty) return const LoginScreen();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == null ? const LoginScreen() : const HomeScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  late final AnimationController _logoAnimCtrl;
  late final Animation<double> _logoPulse;

  @override
  void initState() {
    super.initState();
    _logoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _logoPulse = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _logoAnimCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _logoAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'ইমেইল এবং পাসওয়ার্ড দিন।');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      setState(() => _error = switch (error.code) {
            'invalid-credential' || 'wrong-password' || 'user-not-found' =>
                'ইমেইল বা পাসওয়ার্ড সঠিক নয়।',
            'operation-not-allowed' =>
                'Firebase Console-এ Email/Password sign-in চালু করুন।',
            'invalid-email' => 'সঠিক email address লিখুন।',
            'user-disabled' => 'এই admin account বন্ধ করা আছে।',
            'too-many-requests' =>
                'অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।',
            _ => 'লগইন করা যায়নি (${error.code})। আবার চেষ্টা করুন।',
          });
    } catch (_) {
      setState(() => _error = Firebase.apps.isEmpty
          ? 'Firebase চালু হয়নি: ${_firebaseInitializationError ?? 'configuration error'}'
          : 'লগইন সেবায় সংযোগ করা যাচ্ছে না। আবার চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0047AB), Color(0xFF00296B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedBuilder(
                      animation: _logoPulse,
                      builder: (_, child) => Center(
                        child: Transform.scale(
                          scale: _logoPulse.value,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            child: const Icon(Icons.wifi,
                                size: 48, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'WiFi Zone Manager',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Admin login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16),
                    ),
                    const SizedBox(height: 40),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Admin email',
                                  labelStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.8)),
                                  prefixIcon: Icon(Icons.email_outlined,
                                      color: Colors.white.withOpacity(0.8)),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                onSubmitted: (_) => _login(),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: TextStyle(
                                      color: Colors.white.withOpacity(0.8)),
                                  prefixIcon: Icon(Icons.lock_outline,
                                      color: Colors.white.withOpacity(0.8)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline,
                                          color: Colors.red.shade200, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Colors.red.shade200,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: _loading ? null : _login,
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.login,
                                          color: Colors.white),
                                  label: Text(
                                    _loading ? 'লগইন হচ্ছে...' : 'লগইন করুন',
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0047AB)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0047AB),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 4,
                                    shadowColor:
                                        const Color(0xFF0047AB).withOpacity(0.4),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _error =
                                            'Password reset link sent to your email.';
                                      });
                                    },
                                    child: Text(
                                      'পাসওয়ার্ড ভুলে গেছেন?',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                  ),
                                  const Text(' | ',
                                      style: TextStyle(color: Colors.white54)),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _error = 'Sign up feature coming soon.';
                                      });
                                    },
                                    child: Text(
                                      'একাউন্ট আছে না?',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          decoration:
                                              TextDecoration.underline),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                      child: Divider(
                                          height: 1,
                                          color: Colors.white.withOpacity(0.2))),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text('অথবা',
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(0.5),
                                            fontSize: 12)),
                                  ),
                                  Expanded(
                                      child: Divider(
                                          height: 1,
                                          color: Colors.white.withOpacity(0.2))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _error = 'Google login coming soon.';
                                      });
                                    },
                                    icon: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.g_mobiledata,
                                          color: Colors.white, size: 26),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _error = 'Facebook login coming soon.';
                                      });
                                    },
                                    icon: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.facebook,
                                          color: Colors.white, size: 26),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'v1.0.0 · WiFi Zone Manager',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Custom Modern Header Widget (With Logo) ---
class ModernHeader extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? logoPath;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onNotificationsTap;
  const ModernHeader({
    super.key,
    required this.title,
    this.subtitle = "",
    this.logoPath,
    this.onSettingsTap,
    this.onNotificationsTap,
  });
  @override
  State<ModernHeader> createState() => _ModernHeaderState();
}

class _ModernHeaderState extends State<ModernHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;
  DateTime _currentTime = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime =>
      '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';
  String get _formattedDate =>
      '${_currentTime.day} ${_monthNames[_currentTime.month]} ${_currentTime.year}';
  static const _monthNames = [
    '', 'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
  ];

  @override
  Widget build(BuildContext context) {
    final logoImage = _logoImage(widget.logoPath);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 36),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0047AB), Color(0xFF00296B), Color(0xFF001A4D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x400047AB),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.4), width: 2),
                ),
                child: Center(
                  child: Text(
                    'A',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      'admin@wifihaat.com',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formattedTime,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _formattedDate,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              if (widget.onNotificationsTap != null)
                Stack(
                  children: [
                    IconButton(
                      onPressed: widget.onNotificationsTap,
                      icon: Icon(Icons.notifications_none,
                          color: Colors.white.withOpacity(0.8), size: 22),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              if (widget.onSettingsTap != null)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2)),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.settings_outlined,
                        color: Colors.white.withOpacity(0.8)),
                    onPressed: widget.onSettingsTap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              AnimatedBuilder(
                animation: _shimmer,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shimmer.value * 8, 0),
                  child: child,
                ),
                child: Container(
                  margin: const EdgeInsets.only(right: 14),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 2),
                  ),
                  child: logoImage != null
                      ? ClipOval(
                          child: Image(image: logoImage,
                              fit: BoxFit.cover, width: 48, height: 48))
                      : const Icon(Icons.wifi, color: Colors.white, size: 26),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFCAF0F8)],
                      ).createShader(bounds),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Models ---
class SaleRecord {
  final String invoiceNumber;
  final String retailerName;
  final String retailerPhone;
  final double grandTotal;
  final double discountAmount;
  final double discountRate;
  final double cashAmount;
  final String date;
  final Map<String, int> items;
  SaleRecord({
    required this.invoiceNumber,
    required this.retailerName,
    required this.retailerPhone,
    required this.grandTotal,
    required this.discountAmount,
    required this.discountRate,
    required this.cashAmount,
    required this.date,
    required this.items,
  });
  Map<String, dynamic> toJson() => {
        'invoiceNumber': invoiceNumber,
        'retailerName': retailerName,
        'retailerPhone': retailerPhone,
        'grandTotal': grandTotal,
        'discountAmount': discountAmount,
        'discountRate': discountRate,
        'cashAmount': cashAmount,
        'date': date,
        'items': items,
      };
  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
        invoiceNumber: json['invoiceNumber'] ?? 'OLD',
        retailerName: json['retailerName'],
        retailerPhone: json['retailerPhone'],
        grandTotal: (json['grandTotal'] as num).toDouble(),
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
        discountRate: (json['discountRate'] as num?)?.toDouble() ?? 10.0,
        cashAmount: (json['cashAmount'] as num).toDouble(),
        date: json['date'],
        items: Map<String, int>.from(json['items']),
      );
}
class WifiZone {
  final String id;
  String zoneId;
  String title;
  String address;
  String onuMac;
  String deviceType;
  String gps;
  String status;
  WifiZone({
    required this.id,
    required this.zoneId,
    required this.title,
    required this.address,
    required this.onuMac,
    required this.deviceType,
    required this.gps,
    required this.status,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'zoneId': zoneId,
    'title': title,
    'address': address,
    'onuMac': onuMac,
    'deviceType': deviceType,
    'gps': gps,
    'status': status,
  };
  factory WifiZone.fromJson(Map<String, dynamic> json) => WifiZone(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    zoneId: json['zoneId'] ?? '',
    title: json['title'] ?? '',
    address: json['address'] ?? '',
    onuMac: json['onuMac'] ?? '',
    deviceType: json['deviceType'] ?? '',
    gps: json['gps'] ?? '',
    status: json['status'] ?? 'Active',
  );
}
class AppConfig {
  static const String companyName = 'company_name';
  static const String companyPhone = 'company_phone';
  static const String commissionRate = 'commission_rate';
  static const String invoiceCounter = 'invoice_counter';
  static const String companyLogo = 'company_logo';
  static const String wifiZones = 'wifi_zones';
}
// --- Home Screen ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
 
  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const DashboardScreen(),
      const SalesEntryScreen(),
      const HistoryScreen(),
      WifiZoneScreen(key: UniqueKey()),
    ];
    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        height: 65,
        backgroundColor: Colors.white,
        elevation: 10,
        shadowColor: const Color(0x200047AB),
        indicatorColor: const Color(0xFFCAF0F8),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded, color: Color(0xFF0047AB)),
            label: 'ড্যাশবোর্ড',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle_rounded, color: Color(0xFF0047AB)),
            label: 'নতুন বিক্রয়',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded, color: Color(0xFF0047AB)),
            label: 'ইতিহাস',
          ),
          NavigationDestination(
            icon: Icon(Icons.router_outlined),
            selectedIcon: Icon(Icons.router_rounded, color: Color(0xFF0047AB)),
            label: 'ওয়াইফাই জোন',
          ),
        ],
      ),
    );
  }
}
// --- Dashboard Screen ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, double> salesSummary = {'Today': 0, 'Weekly': 0, 'Monthly': 0};
  Map<String, int> cardWiseSales = {};
  Map<String, int> stock = {};
  List<int> cardPrices = [];
  String companyName = "My WiFi Zone";
  String? logoPath;
  List<double> weeklyChartData = List.filled(7, 0.0);
  List<String> weekDaysLabels = [];
  bool _isLoading = true;
  double totalStockValue = 0.0;
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }
  Future<void> _loadDashboardData() async {
    final prefs = await SharedPreferences.getInstance();
    companyName = prefs.getString(AppConfig.companyName) ?? "WiFi Zone Manager";
    logoPath = prefs.getString(AppConfig.companyLogo);
   
    List<String>? savedPrices = prefs.getStringList('saved_card_prices');
    if (savedPrices != null) {
      cardPrices = savedPrices.map((e) => int.parse(e)).toList();
      cardPrices.sort();
    } else {
      cardPrices = [9, 15, 25, 50, 89, 249];
    }
   
    String? stockJson = prefs.getString('card_stock');
    if (stockJson != null) stock = Map<String, int>.from(jsonDecode(stockJson));
   
    String? historyJson = prefs.getString('sales_history');
    List<SaleRecord> history = [];
    if (historyJson != null) {
      List<dynamic> decoded = jsonDecode(historyJson);
      history = decoded.map((e) => SaleRecord.fromJson(e)).toList();
    }
    _calculateReports(history);
    _calculateTotalStock();
    setState(() => _isLoading = false);
  }
  void _calculateReports(List<SaleRecord> history) {
    DateTime now = DateTime.now();
    DateFormat formatter = DateFormat('yyyy-MM-dd hh:mm a');
   
    double todayTotal = 0;
    double weeklyTotal = 0;
    double monthlyTotal = 0;
    Map<String, int> tempCardSales = {};
   
    weeklyChartData = List.filled(7, 0.0);
    weekDaysLabels = [];
   
    for (int i = 6; i >= 0; i--) {
      weekDaysLabels.add(DateFormat('E').format(now.subtract(Duration(days: i))));
    }
    for (var sale in history) {
      try {
        DateTime saleDate = formatter.parse(sale.date);
        DateTime justDateNow = DateTime(now.year, now.month, now.day);
        DateTime justDateSale = DateTime(saleDate.year, saleDate.month, saleDate.day);
       
        int diffDays = justDateNow.difference(justDateSale).inDays;
       
        if (diffDays == 0) todayTotal += sale.cashAmount;
        if (diffDays <= 7) weeklyTotal += sale.cashAmount;
        if (diffDays <= 30) monthlyTotal += sale.cashAmount;
        if (diffDays >= 0 && diffDays < 7) {
          weeklyChartData[6 - diffDays] += sale.cashAmount;
        }
        sale.items.forEach((price, qty) {
          tempCardSales[price] = (tempCardSales[price] ?? 0) + qty;
        });
      } catch (e) { }
    }
    salesSummary['Today'] = todayTotal;
    salesSummary['Weekly'] = weeklyTotal;
    salesSummary['Monthly'] = monthlyTotal;
    cardWiseSales = tempCardSales;
  }
  void _calculateTotalStock() {
    totalStockValue = 0.0;
    for (var price in cardPrices) {
      totalStockValue += price * (stock[price.toString()] ?? 0);
    }
  }
  // --- Stock Management Dialog (ADD/UPDATE) ---
  void _showManageStockDialog(String price) {
    TextEditingController qtyController = TextEditingController();
    int currentStock = stock[price] ?? 0;
   
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("স্টক ম্যানেজ করুন ($price Tk)", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("বর্তমান স্টক: $currentStock টি", style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: "সংখ্যা লিখুন (pcs)", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("বাতিল")
          ),
          // Update/Set Button (Corrects mistake)
          TextButton(
            onPressed: () async {
              int? qty = int.tryParse(qtyController.text);
              if (qty != null) {
                await _updateStock(price, qty, isOverwrite: true);
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("সেট করুন (Set)", style: TextStyle(color: Colors.orange)),
          ),
          // Add Button (Normal flow)
          ElevatedButton(
            onPressed: () async {
              int? qty = int.tryParse(qtyController.text);
              if (qty != null) {
                await _updateStock(price, qty, isOverwrite: false);
                if (mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0047AB), foregroundColor: Colors.white),
            child: const Text("যোগ করুন (Add)"),
          )
        ],
      ),
    );
  }
  Future<void> _updateStock(String price, int qty, {required bool isOverwrite}) async {
    await SharedPreferences.refresh();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (isOverwrite) {
        stock[price] = qty;
      } else {
        stock[price] = (stock[price] ?? 0) + qty;
      }
      _calculateTotalStock();
    });
    await prefs.setString('card_stock', jsonEncode(stock));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isOverwrite ? "স্টক সংশোধন করা হয়েছে (Updated)!" : "স্টক যোগ করা হয়েছে (Added)!")));
  }
  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen(currentPrices: List.from(cardPrices))),
    );
    _loadDashboardData();
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    List<BarChartGroupData> qtyChartGroups = [];
    double maxQty = 0;
   
    for (int i = 0; i < cardPrices.length; i++) {
      String price = cardPrices[i].toString();
      double qty = (cardWiseSales[price] ?? 0).toDouble();
      if (qty > maxQty) maxQty = qty;
      qtyChartGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: qty,
              gradient: const LinearGradient(
                colors: [Color(0xFF0047AB), Color(0xFF00B4D8)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxQty == 0 ? 10 : maxQty * 1.1, color: const Color(0xFFF0F9FF)),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          ModernHeader(
            title: "ড্যাশবোর্ড",
            subtitle: companyName,
            logoPath: logoPath,
            onSettingsTap: _openSettings,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildSummaryCard("আজকের বিক্রয়", salesSummary['Today']!, const Color(0xFF0047AB)),
                      const SizedBox(width: 12),
                      _buildSummaryCard("এই মাস", salesSummary['Monthly']!, const Color(0xFF00B4D8)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFullSummaryCard("মোট স্টক মূল্য", totalStockValue, const Color(0xFF00296B)),
                  const SizedBox(height: 24),
                  const Text("সাপ্তাহিক রেভিনিউ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: const Color(0xFF0047AB).withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        // Ensure maxY scales correctly even if all values are 0
                        maxY: (weeklyChartData.reduce((a, b) => a > b ? a : b)) == 0 ? 10 : weeklyChartData.reduce((a, b) => a > b ? a : b) * 1.2,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (group) => Colors.black.withOpacity(0.8),
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(0),
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Padding(padding: const EdgeInsets.only(top: 10), child: Text(weekDaysLabels.length > val.toInt() ? weekDaysLabels[val.toInt()] : '', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))))),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(
                          toY: weeklyChartData[i],
                          color: weeklyChartData[i] > 0 ? const Color(0xFF0047AB) : const Color(0xFFCAF0F8),
                          width: 12,
                          borderRadius: BorderRadius.circular(4)
                        )])),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("কার্ড অনুযায়ী বিক্রয়", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: const Color(0xFF0047AB).withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxQty == 0 ? 10 : maxQty * 1.2,
                        barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(getTooltipColor: (group) => const Color(0xFF00B4D8))),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Padding(padding: const EdgeInsets.only(top: 10), child: Text(cardPrices.length > val.toInt() ? "${cardPrices[val.toInt()]}" : '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))))),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: qtyChartGroups,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("স্টক আপডেট", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
                    itemCount: cardPrices.length,
                    itemBuilder: (context, index) {
                      String price = cardPrices[index].toString();
                      int qty = stock[price] ?? 0;
                      return InkWell(
                        onTap: () => _showManageStockDialog(price),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: qty < 10 ? [Colors.red.shade50, Colors.red.shade100] : [const Color(0xFFCAF0F8), const Color(0xFFF0F9FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: qty < 10 ? Colors.red.withOpacity(0.2) : const Color(0xFF0047AB).withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: qty < 10 ? Colors.red.shade100 : const Color(0xFF0047AB).withOpacity(0.1),
                                child: Icon(Icons.credit_card, color: qty < 10 ? Colors.red : const Color(0xFF0047AB), size: 24),
                              ),
                              const SizedBox(height: 12),
                              Text("$price Tk", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: qty < 10 ? Colors.red.shade800 : const Color(0xFF0047AB))),
                              const SizedBox(height: 4),
                              Text("$qty pcs", style: TextStyle(color: qty < 10 ? Colors.red.shade600 : const Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSummaryCard(String title, double amount, Color accentColor) {
    return Expanded(
      child: _summaryCardContent(title, amount, accentColor),
    );
  }
  Widget _buildFullSummaryCard(String title, double amount, Color accentColor) {
    return _summaryCardContent(title, amount, accentColor);
  }
  Widget _summaryCardContent(String title, double amount, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor, accentColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.attach_money, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount >= 1000 ? "${(amount/1000).toStringAsFixed(1)}k" : amount.toStringAsFixed(0),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
// --- Sales Entry Screen (Cobalt & White) ---
class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});
  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}
class _SalesEntryScreenState extends State<SalesEntryScreen> {
  List<int> cardPrices = [];
  Map<String, int> stock = {};
  final Map<int, int> _quantities = {};
  final Map<int, TextEditingController> _controllers = {};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  List<String> _retailerNames = [];
  final Map<String, String> _retailerPhoneMap = {};
  double _commissionRate = 10.0;
  bool _isLoading = true;
  @override
  void initState() { super.initState(); _loadData(); }
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _commissionRate = (prefs.getDouble(AppConfig.commissionRate) ?? 10.0);
    List<String>? savedPrices = prefs.getStringList('saved_card_prices');
    if (savedPrices != null) { cardPrices = savedPrices.map((e) => int.parse(e)).toList(); cardPrices.sort(); } else { cardPrices = [9, 15, 25, 50, 89, 249]; }
    String? stockJson = prefs.getString('card_stock'); if (stockJson != null) stock = Map<String, int>.from(jsonDecode(stockJson));
    String? historyJson = prefs.getString('sales_history'); if (historyJson != null) { List<dynamic> decoded = jsonDecode(historyJson); for (var item in decoded) { var sale = SaleRecord.fromJson(item); _retailerNames.add(sale.retailerName); _retailerPhoneMap[sale.retailerName] = sale.retailerPhone; } _retailerNames = _retailerNames.toSet().toList(); }
    _initializeControllers(); setState(() => _isLoading = false);
  }
  void _initializeControllers() { for (var price in cardPrices) { if (!_quantities.containsKey(price)) _quantities[price] = 0; if (!_controllers.containsKey(price)) _controllers[price] = TextEditingController(); } }
  void _updateQuantity(int price, String value) { setState(() => _quantities[price] = int.tryParse(value) ?? 0); }
  void _clearAll() { setState(() { for (var price in cardPrices) { _quantities[price] = 0; _controllers[price]?.clear(); } _nameController.clear(); _phoneController.clear(); FocusScope.of(context).unfocus(); }); }
  Future<String> _generateInvoiceNumber() async { final prefs = await SharedPreferences.getInstance(); int counter = prefs.getInt(AppConfig.invoiceCounter) ?? 1000; counter++; await prefs.setInt(AppConfig.invoiceCounter, counter); return "INV-$counter"; }
  void _submitSale() async {
    if (_nameController.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডিলার নাম লিখুন'))); return; }
    double grandTotal = 0; Map<String, int> soldItems = {}; List<String> outOfStockItems = [];
    for (var price in cardPrices) { int reqQty = _quantities[price] ?? 0; if (reqQty > 0) { String priceKey = price.toString(); int available = stock[priceKey] ?? 0; if (available < reqQty) { outOfStockItems.add("$price Tk (আছে: $available)"); } else { grandTotal += price * reqQty; soldItems[priceKey] = reqQty; } } }
    if (outOfStockItems.isNotEmpty) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("স্টক সমস্যা"), content: Text("স্টক পর্যাপ্ত নয়:\n\n${outOfStockItems.join('\n')}"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ঠিক আছে"))])); return; }
    if (soldItems.isEmpty) return;
    String invNum = await _generateInvoiceNumber(); double discount = grandTotal * (_commissionRate / 100); double cashAmount = grandTotal - discount;
    SaleRecord newSale = SaleRecord(invoiceNumber: invNum, retailerName: _nameController.text, retailerPhone: _phoneController.text, grandTotal: grandTotal, discountAmount: discount, discountRate: _commissionRate, cashAmount: cashAmount, date: DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now()), items: soldItems);
    await _finalizeSale(newSale, soldItems);
    if (mounted) { showDialog(context: context, builder: (context) => InvoiceDialog(sale: newSale)); _clearAll(); final prefs = await SharedPreferences.getInstance(); String? stockJson = prefs.getString('card_stock'); if (stockJson != null) setState(() => stock = Map<String, int>.from(jsonDecode(stockJson))); }
  }
  Future<void> _finalizeSale(SaleRecord sale, Map<String, int> soldItems) async {
    await SharedPreferences.refresh();
    final prefs = await SharedPreferences.getInstance();
    soldItems.forEach((price, qty) {
      if (stock.containsKey(price)) stock[price] = (stock[price] ?? 0) - qty;
    });
    await prefs.setString('card_stock', jsonEncode(stock));
    List<SaleRecord> history = [];
    String? existingHistory = prefs.getString('sales_history');
    if (existingHistory != null) {
      List<dynamic> decoded = jsonDecode(existingHistory);
      history = decoded.map((e) => SaleRecord.fromJson(e)).toList();
    }
    history.insert(0, sale);
    await prefs.setString('sales_history', jsonEncode(history.map((e) => e.toJson()).toList()));
  }
  void _openSettings() async { await Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(currentPrices: List.from(cardPrices)))); _loadData(); }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    double currentTotal = 0; for (var price in cardPrices) { currentTotal += price * (_quantities[price] ?? 0); } double currentCash = currentTotal - (currentTotal * (_commissionRate / 100));
    return Scaffold(
      body: Column(
        children: [
          ModernHeader(
            title: "নতুন বিক্রয়",
            subtitle: "কমিশন রেট: ${_commissionRate.toStringAsFixed(1)}%",
            onSettingsTap: _openSettings,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFCAF0F8)),
                      boxShadow: [BoxShadow(color: const Color(0xFF0047AB).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Autocomplete<String>(
                          optionsBuilder: (v) => v.text == '' ? const Iterable<String>.empty() : _retailerNames.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
                          onSelected: (s) { _nameController.text = s; if (_retailerPhoneMap.containsKey(s)) _phoneController.text = _retailerPhoneMap[s]!; },
                          fieldViewBuilder: (ctx, ctrl, node, submit) { if (ctrl.text != _nameController.text) ctrl.text = _nameController.text; ctrl.addListener(() => _nameController.text = ctrl.text); return TextField(controller: ctrl, focusNode: node, decoration: const InputDecoration(labelText: 'ডিলার নাম', prefixIcon: Icon(Icons.store))); },
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'ফোন নাম্বার', prefixIcon: Icon(Icons.phone))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cardPrices.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      int price = cardPrices[index]; int subTotal = price * (_quantities[price] ?? 0); int stockQty = stock[price.toString()] ?? 0; if (!_controllers.containsKey(price)) return const SizedBox();
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF0047AB), Color(0xFF00B4D8)]),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('$price', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(stockQty > 0 ? 'স্টকে আছে' : 'স্টক শেষ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: stockQty > 0 ? const Color(0xFF00B4D8) : Colors.red)),
                                    Text('$stockQty টি বাকি', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _controllers[price],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0047AB)),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF0F9FF),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => _updateQuantity(price, val),
                                ),
                              ),
                              const SizedBox(width: 15),
                              SizedBox(width: 60, child: Text('$subTotal', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), boxShadow: [BoxShadow(color: const Color(0xFF0047AB).withOpacity(0.1), blurRadius: 25, offset: const Offset(0, -5))]),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("মোট মূল্য", style: TextStyle(color: Colors.grey[600])), Text("${currentTotal.toStringAsFixed(0)} Tk", style: const TextStyle(fontWeight: FontWeight.bold))]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("কমিশন", style: TextStyle(color: Colors.grey[600])), Text("- ${(currentTotal * (_commissionRate/100)).toStringAsFixed(0)} Tk", style: const TextStyle(color: Color(0xFF00B4D8), fontWeight: FontWeight.bold))]),
                const Divider(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("নেট প্রদেয়", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text("${currentCash.toStringAsFixed(0)} Tk", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0047AB)))]),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submitSale, child: const Text("বিক্রয় নিশ্চিত করুন"))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// --- History Screen ---
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  List<SaleRecord> allHistory = []; List<SaleRecord> filteredHistory = []; TextEditingController searchController = TextEditingController();
  @override void initState() { super.initState(); _loadHistory(); }
  Future<void> _loadHistory() async { final prefs = await SharedPreferences.getInstance(); String? historyJson = prefs.getString('sales_history'); if (historyJson != null) { List<dynamic> decoded = jsonDecode(historyJson); setState(() { allHistory = decoded.map((e) => SaleRecord.fromJson(e)).toList(); filteredHistory = allHistory; }); } }
  void _filterHistory(String query) { setState(() { if (query.isEmpty) {
    filteredHistory = allHistory;
  } else {
    filteredHistory = allHistory.where((s) => s.invoiceNumber.toLowerCase().contains(query.toLowerCase()) || s.retailerName.toLowerCase().contains(query.toLowerCase())).toList();
  } }); }
  void _clearHistory() async { final prefs = await SharedPreferences.getInstance(); await prefs.remove('sales_history'); await prefs.remove(AppConfig.invoiceCounter); setState(() { allHistory = []; filteredHistory = []; }); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ModernHeader(title: "বিক্রয়ের ইতিহাস", subtitle: "সমস্ত রেকর্ড"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              controller: searchController,
              onChanged: _filterHistory,
              decoration: InputDecoration(hintText: "ইনভয়েস বা নাম দিয়ে খুঁজুন...", prefixIcon: const Icon(Icons.search), contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none), filled: true, fillColor: Colors.white),
            ),
          ),
          Expanded(
            child: filteredHistory.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_edu, size: 60, color: Colors.grey.shade300), const SizedBox(height: 16), Text("এখনও কোনো বিক্রয় রেকর্ড নেই", style: TextStyle(color: Colors.grey.shade500))]))
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: filteredHistory.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final sale = filteredHistory[index];
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF0F9FF))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0047AB))),
                          title: Text(sale.retailerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("#${sale.invoiceNumber} • ${sale.date}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("${sale.cashAmount.toStringAsFixed(0)} Tk", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0047AB)))]),
                          onTap: () => showDialog(context: context, builder: (c) => InvoiceDialog(sale: sale)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
// --- Invoice Dialog & Settings (Visuals Updated) ---
class InvoiceDialog extends StatefulWidget {
  final SaleRecord sale;
  const InvoiceDialog({super.key, required this.sale});
  @override
  State<InvoiceDialog> createState() => _InvoiceDialogState();
}
class _InvoiceDialogState extends State<InvoiceDialog> {
  String companyName = ""; String companyPhone = ""; String? logoPath;
  @override void initState() { super.initState(); _loadCompanyInfo(); }
  void _loadCompanyInfo() async { final prefs = await SharedPreferences.getInstance(); setState(() { companyName = prefs.getString(AppConfig.companyName) ?? "WiFi Zone Manager"; companyPhone = prefs.getString(AppConfig.companyPhone) ?? ""; logoPath = prefs.getString(AppConfig.companyLogo); }); }
  void _shareInvoice() { Share.share("🧾 *ইনভয়েস: ${widget.sale.invoiceNumber}*\n$companyName\n$companyPhone\n------------------------\nতারিখ: ${widget.sale.date}\nডিলার: ${widget.sale.retailerName}\n------------------------\nমোট মূল্য: ${widget.sale.grandTotal.toStringAsFixed(0)} Tk\nকমিশন: -${widget.sale.discountAmount.toStringAsFixed(0)}\n*প্রদেয়: ${widget.sale.cashAmount.toStringAsFixed(0)} Tk*"); }
 
  @override
  Widget build(BuildContext context) {
    final logoImage = _logoImage(logoPath);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(children: [
        if(logoImage != null) CircleAvatar(backgroundImage: logoImage, radius: 25, backgroundColor: Colors.transparent),
        Text(companyName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0047AB))), Text("ইনভয়েস #${widget.sale.invoiceNumber}", style: const TextStyle(fontSize: 12, color: Colors.grey))
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            _row("ডিলার", widget.sale.retailerName, true),
            if(widget.sale.retailerPhone.isNotEmpty) _row("ফোন", widget.sale.retailerPhone, false),
            const Divider(),
            ...widget.sale.items.entries.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${e.key} Tk x ${e.value}"), Text("${int.parse(e.key) * e.value}")]))),
            const Divider(),
            _row("মোট মূল্য", widget.sale.grandTotal.toStringAsFixed(0), false),
            _row("কমিশন", "-${widget.sale.discountAmount.toStringAsFixed(0)}", false, color: const Color(0xFF00B4D8)),
            const Divider(),
            _row("প্রদেয়", "${widget.sale.cashAmount.toStringAsFixed(0)} Tk", true, size: 18, color: const Color(0xFF0047AB)),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("বন্ধ করুন")), ElevatedButton.icon(onPressed: _shareInvoice, icon: const Icon(Icons.share, size: 16), label: const Text("শেয়ার করুন"))],
    );
  }
  Widget _row(String k, String v, bool bold, {double size=14, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(k, style: TextStyle(fontSize: size, fontWeight: bold?FontWeight.bold:FontWeight.normal)), Text(v, style: TextStyle(fontSize: size, fontWeight: bold?FontWeight.bold:FontWeight.normal, color: color))]));
}
// Settings Screen (With Logo Upload)
class SettingsScreen extends StatefulWidget {
  final List<int> currentPrices;
  const SettingsScreen({super.key, required this.currentPrices});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  late List<int> _prices;
  Uint8List? _logoBytes;
  final _addController = TextEditingController(), _companyNameCtrl = TextEditingController(), _companyPhoneCtrl = TextEditingController(), _commissionCtrl = TextEditingController();
 
  @override void initState() { super.initState(); _prices = List.from(widget.currentPrices); _loadSettings(); }
 
  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyNameCtrl.text = prefs.getString(AppConfig.companyName) ?? "";
      _companyPhoneCtrl.text = prefs.getString(AppConfig.companyPhone) ?? "";
      _commissionCtrl.text = (prefs.getDouble(AppConfig.commissionRate) ?? 10.0).toString();
      final encodedLogo = prefs.getString(AppConfig.companyLogo);
      if (encodedLogo != null && encodedLogo.isNotEmpty) {
        _logoBytes = Uint8List.fromList(base64Decode(encodedLogo));
      }
    });
  }
 
  void _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _logoBytes = Uint8List.fromList(bytes);
      });
    }
  }
  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.companyName, _companyNameCtrl.text);
    await prefs.setString(AppConfig.companyPhone, _companyPhoneCtrl.text);
    double? c = double.tryParse(_commissionCtrl.text);
    if(c!=null) await prefs.setDouble(AppConfig.commissionRate, c);
    await prefs.setStringList('saved_card_prices', _prices.map((e) => e.toString()).toList());
   
    if (_logoBytes != null) {
      await prefs.setString(AppConfig.companyLogo, base64Encode(_logoBytes!));
    }
    if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("সফলভাবে সংরক্ষণ করা হয়েছে!")));
      Navigator.pop(context);
    }
  }
 
  void _addPrice() { if(_addController.text.isNotEmpty){ int? p = int.tryParse(_addController.text); if(p!=null && !_prices.contains(p)) { setState(() { _prices.add(p); _prices.sort(); }); Navigator.pop(context); _addController.clear(); } } }
 
  Future<void> _backupData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> data = {
        'backupMarker': 'WifiZoneManagerBackup',
        'backupVersion': 1,
      };
      data['companyName'] = prefs.getString(AppConfig.companyName);
      data['companyPhone'] = prefs.getString(AppConfig.companyPhone);
      data['commissionRate'] = prefs.getDouble(AppConfig.commissionRate);
      data['invoiceCounter'] = prefs.getInt(AppConfig.invoiceCounter);
      data['savedCardPrices'] = prefs.getStringList('saved_card_prices');
      data['cardStock'] = prefs.getString('card_stock');
      data['salesHistory'] = prefs.getString('sales_history');
      data['wifiZones'] = prefs.getString(AppConfig.wifiZones);
      data['companyLogoBase64'] = prefs.getString(AppConfig.companyLogo);
      String jsonData = jsonEncode(data);
      String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFile = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonData)),
        name: 'wifi_zone_backup_$timestamp.json',
        mimeType: 'application/json',
      );
      await Share.shareXFiles([backupFile], text: 'WiFi Zone Manager Backup - $timestamp');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ব্যাকআপ সফলভাবে নেওয়া হয়েছে এবং শেয়ার করা হয়েছে।")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("ব্যাকআপ নিতে সমস্যা: $e")));
      }
    }
  }
 
  Future<void> _restoreData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null) return;
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("রিস্টোর নিশ্চিতকরণ"),
          content: const Text("এটি বর্তমান সকল ডেটা ওভাররাইট করবে। চালিয়ে যাবেন?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("না")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("হ্যাঁ")),
          ],
        ),
      );
      if (confirm != true) return;
      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) throw 'ব্যাকআপ ফাইল পড়া যাচ্ছে না।';
      String jsonData = utf8.decode(fileBytes);
      Map<String, dynamic> data = jsonDecode(jsonData);
      if (data['backupMarker'] != 'WifiZoneManagerBackup') {
        throw 'অবৈধ ব্যাকআপ ফাইল: মার্কার মিলছে না।';
      }
      num? ver = data['backupVersion'] as num?;
      if (ver == null || ver.toInt() != 1) {
        throw 'ব্যাকআপ সংস্করণ অসামঞ্জস্যপূর্ণ।';
      }
      final prefs = await SharedPreferences.getInstance();
      // Helper to set/remove string prefs
      void handleString(String prefKey, String mapKey) {
        if (data.containsKey(mapKey)) {
          String? val = data[mapKey] as String?;
          if (val != null) {
            prefs.setString(prefKey, val);
          } else {
            prefs.remove(prefKey);
          }
        }
      }
      // Helper for double
      void handleDouble(String prefKey, String mapKey) {
        if (data.containsKey(mapKey)) {
          num? val = data[mapKey] as num?;
          if (val != null) {
            prefs.setDouble(prefKey, val.toDouble());
          } else {
            prefs.remove(prefKey);
          }
        }
      }
      // Helper for int
      void handleInt(String prefKey, String mapKey) {
        if (data.containsKey(mapKey)) {
          num? val = data[mapKey] as num?;
          if (val != null) {
            prefs.setInt(prefKey, val.toInt());
          } else {
            prefs.remove(prefKey);
          }
        }
      }
      // Helper for string list
      void handleStringList(String prefKey, String mapKey) {
        if (data.containsKey(mapKey)) {
          List<dynamic>? val = data[mapKey] as List<dynamic>?;
          if (val != null) {
            prefs.setStringList(prefKey, val.cast<String>());
          } else {
            prefs.remove(prefKey);
          }
        }
      }
      handleString(AppConfig.companyName, 'companyName');
      handleString(AppConfig.companyPhone, 'companyPhone');
      handleDouble(AppConfig.commissionRate, 'commissionRate');
      handleInt(AppConfig.invoiceCounter, 'invoiceCounter');
      handleStringList('saved_card_prices', 'savedCardPrices');
      handleString('card_stock', 'cardStock');
      handleString('sales_history', 'salesHistory');
      handleString(AppConfig.wifiZones, 'wifiZones');
      // Logo handling
      if (data.containsKey('companyLogoBase64')) {
        String? b64 = data['companyLogoBase64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          List<int> bytes = base64Decode(b64);
          await prefs.setString(AppConfig.companyLogo, base64Encode(bytes));
        } else {
          prefs.remove(AppConfig.companyLogo);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ডেটা সফলভাবে রিস্টোর হয়েছে। অ্যাপ রিস্টার্ট করুন।")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("রিস্টোরে সমস্যা: $e")));
      }
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("সেটিংস"), backgroundColor: Colors.white, foregroundColor: const Color(0xFF0047AB), elevation: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo Upload Section
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: _logoBytes != null ? MemoryImage(_logoBytes!) : null,
                  child: _logoBytes == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(child: Text("লোগো পরিবর্তন করতে ট্যাপ করুন", style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 30),
            const Text("কোম্পানির তথ্য", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
            const SizedBox(height: 10),
            TextField(controller: _companyNameCtrl, decoration: const InputDecoration(labelText: "কোম্পানির নাম ", prefixIcon: Icon(Icons.store))),
            const SizedBox(height: 10),
            TextField(controller: _companyPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "ফোন", prefixIcon: Icon(Icons.phone))),
            const SizedBox(height: 30),
            const Text("কনফিগারেশন", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
            const SizedBox(height: 10),
            TextField(controller: _commissionCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "কমিশন %", prefixIcon: Icon(Icons.percent))),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("কার্ডের দাম", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFF0047AB), size: 28),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text("কার্ডের দাম যোগ করুন", style: TextStyle(color: Color(0xFF0047AB))),
                      content: TextField(
                        controller: _addController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "দাম লিখুন (Tk)",
                          prefixIcon: const Icon(Icons.attach_money),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text("বাতিল", style: TextStyle(color: Colors.grey))),
                        ElevatedButton(
                          onPressed: _addPrice,
                          child: const Text("যোগ করুন"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Beautiful Card Prices List
            if (_prices.isEmpty)
              const Center(
                child: Text("কোনো কার্ডের দাম যোগ করা হয়নি", style: TextStyle(color: Colors.grey)),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _prices.length,
                itemBuilder: (context, index) {
                  int p = _prices[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.credit_card, color: Color(0xFF0047AB), size: 24),
                              const SizedBox(height: 8),
                              Text("$p Tk", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => setState(() => _prices.remove(p)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveSettings, child: const Text("সংরক্ষণ করুন"))),
            const SizedBox(height: 30),
            const Text("ব্যাকআপ এবং রিস্টোর", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(onPressed: _backupData, icon: const Icon(Icons.backup), label: const Text("ব্যাকআপ নিন"))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(onPressed: _restoreData, icon: const Icon(Icons.restore), label: const Text("রিস্টোর করুন"))),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.logout),
                label: const Text("Admin logout"),
              ),
            ),
            // --- NEW DEVELOPER INFO SECTION (Modern Look) ---
            const SizedBox(height: 30),
            const Text("Developer Info", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0047AB))),
            const SizedBox(height: 10),
            Center(
              child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                colors: [Color(0xFF0047AB), Color(0xFF00B4D8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                BoxShadow(
                  color: Color(0x400047AB),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                    ],
                  ),
                  child: const CircleAvatar(
                    radius: 32,
                    backgroundColor: Color(0xFF0047AB),
                    child: Icon(Icons.code_rounded, color: Colors.white, size: 32),
                  ),
                  ),
                  const SizedBox(height: 14),
                  const Text("Developed by", style: TextStyle(fontSize: 13, color: Color(0xFFCAF0F8))),
                  const Text(
                  "Md. Asaduzzaman",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.phone, size: 16, color: Color(0xFFCAF0F8)),
                    SizedBox(width: 6),
                    Text("+8801770033448", style: TextStyle(fontSize: 14, color: Color(0xFFCAF0F8))),
                  ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.email_outlined, size: 16, color: Color(0xFFCAF0F8)),
                    SizedBox(width: 6),
                    Text("asadacn@gmail.com", style: TextStyle(fontSize: 14, color: Color(0xFFCAF0F8))),
                  ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Version 1.0.0",
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                  ),
                  ),
                 
                ],
                ),
              ),
              ),
            ),
            // --- END DEVELOPER INFO SECTION ---
          ],
        ),
      ),
    );
  }
}
// --- NEW SCREEN: WiFi Zone Management ---
class WifiZoneScreen extends StatefulWidget {
  const WifiZoneScreen({super.key});
  @override
  State<WifiZoneScreen> createState() => _WifiZoneScreenState();
}
class _WifiZoneScreenState extends State<WifiZoneScreen> {
  List<WifiZone> allZones = [];
  List<WifiZone> filteredZones = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  Position? _currentPosition;
  Map<String, double> _distances = {};
  StreamSubscription<Position>? _positionSubscription;
  @override
  void initState() {
    super.initState();
    _initLocationStream();
    _loadZones();
    _searchController.addListener(_filterZones);
  }
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _searchController.removeListener(_filterZones);
    _searchController.dispose();
    super.dispose();
  }
  Future<void> _initLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Optionally show dialog to enable location services
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Show message to user
        return;
      }
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      _currentPosition = position;
      _calculateDistances();
    });
  }
  void _calculateDistances() {
    if (_currentPosition == null) return;

    Map<String, double> newDistances = {};
    for (var zone in allZones) {
      if (zone.gps.isNotEmpty) {
        final parts = zone.gps.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) {
            final distance = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              lat,
              lng,
            );
            newDistances[zone.id] = distance;
          }
        }
      }
    }

    setState(() {
      _distances = newDistances;
    });
  }
  String _getDistanceText(WifiZone zone) {
    if (zone.gps.isEmpty || _currentPosition == null) return '';

    double? d = _distances[zone.id];
    if (d == null) return ' | Calculating...';

    String distStr;
    if (d < 1000) {
      distStr = '${d.toStringAsFixed(0)} m';
    } else {
      distStr = '${(d / 1000).toStringAsFixed(1)} km';
    }
    return ' | $distStr';
  }
  Future<void> _loadZones() async {
    final prefs = await SharedPreferences.getInstance();
    String? zonesJson = prefs.getString(AppConfig.wifiZones);
    if (zonesJson != null) {
      List<dynamic> decoded = jsonDecode(zonesJson);
      allZones = decoded.map((e) => WifiZone.fromJson(e)).toList();
    }
    _filterZones(); // Initial filtering to show all zones
    setState(() => _isLoading = false);
    _calculateDistances(); // Initial calculation if position available
  }
  void _filterZones() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredZones = allZones;
      } else {
        filteredZones = allZones.where((zone) {
          return zone.zoneId.toLowerCase().contains(query) ||
                 zone.title.toLowerCase().contains(query) ||
                 zone.address.toLowerCase().contains(query);
        }).toList();
      }
    });
  }
  Future<void> _saveZones() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.wifiZones, jsonEncode(allZones.map((e) => e.toJson()).toList()));
  }
  void _addEditZone({WifiZone? zone}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ZoneEntryScreen(zone: zone)),
    );
    // Reload data after returning from entry screen
    await _loadZones();
    _saveZones();
  }
  void _deleteZone(WifiZone zone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("মুছে ফেলার নিশ্চিতকরণ"),
        content: const Text("আপনি কি সত্যিই এই জোনটি মুছে ফেলতে চান?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("না"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("হ্যাঁ"),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          allZones.removeWhere((z) => z.id == zone.id);
          _filterZones();
        });
        _saveZones();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("জোনটি মুছে ফেলা হয়েছে।")));
      }
    });
  }
  void _shareZone(WifiZone zone) {
    final shareText = """
🚀 WiFi Zone Details 🚀
------------------------------------
Title: ${zone.title}
Zone ID: ${zone.zoneId}
ONU MAC: ${zone.onuMac}
Device Type: ${zone.deviceType}
Status: ${zone.status}
Address: ${zone.address}
GPS: ${zone.gps}
Map Link: ${zone.gps.isNotEmpty ? 'https://maps.google.com/?q=${zone.gps}' : 'N/A'}
""";
    Share.share(shareText, subject: 'WiFi Zone: ${zone.title}');
  }
  void _openMap(String gpsCoordinates) async {
    if (gpsCoordinates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("GPS কো-অর্ডিনেট সেট করা হয়নি।")));
      return;
    }
   
    // GPS format is typically "Latitude, Longitude" (e.g., "23.8103, 90.4125")
    final uri = Uri.parse('https://maps.google.com/?q=$gpsCoordinates');
    if (!await launchUrl(uri)) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ম্যাপ খোলা যাচ্ছে না। লোকেশন: $gpsCoordinates')));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ModernHeader(title: "ওয়াইফাই জোন", subtitle: "জোন এন্ট্রি, সার্চ ও ম্যাপ ভিউ"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "জোন ID, নাম বা ঠিকানা দিয়ে খুঁজুন...",
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredZones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.router_rounded, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(_searchController.text.isEmpty ? "কোনো জোন যোগ করা হয়নি" : "কোনো জোন খুঁজে পাওয়া যায়নি", style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filteredZones.length,
                        itemBuilder: (context, index) {
                          final zone = filteredZones[index];
                          final bool hasGps = zone.gps.isNotEmpty;
                          return Card(
                            elevation: 2,
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: zone.status == 'Active' ? const Color(0xFFCAF0F8) : Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.wifi_rounded, color: zone.status == 'Active' ? const Color(0xFF0047AB) : Colors.red.shade600),
                              ),
                              title: Text(zone.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("ID: ${zone.zoneId} | ${zone.address}", overflow: TextOverflow.ellipsis),
                                  if (_getDistanceText(zone).isNotEmpty)
                                    Text(
                                      _getDistanceText(zone).replaceFirst(' |', ''),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Map Button
                                  IconButton(
                                    icon: Icon(Icons.map_outlined, color: hasGps ? const Color(0xFF00B4D8) : Colors.grey.shade400),
                                    onPressed: hasGps ? () => _openMap(zone.gps) : null,
                                    tooltip: hasGps ? 'ম্যাপে দেখুন' : 'GPS নেই',
                                  ),
                                  // Share Button
                                  IconButton(
                                    icon: const Icon(Icons.share_outlined, color: Color(0xFF0047AB)),
                                    onPressed: () => _shareZone(zone),
                                    tooltip: 'জোন শেয়ার করুন',
                                  ),
                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _deleteZone(zone),
                                    tooltip: 'মুছে ফেলুন',
                                  ),
                                ],
                              ),
                              onTap: () => _addEditZone(zone: zone),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEditZone(),
        icon: const Icon(Icons.add),
        label: const Text("নতুন জোন যোগ করুন"),
        backgroundColor: const Color(0xFF00B4D8),
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
// --- NEW SCREEN: Zone Entry/Edit Form ---
class ZoneEntryScreen extends StatefulWidget {
  final WifiZone? zone;
  const ZoneEntryScreen({super.key, this.zone});
  @override
  State<ZoneEntryScreen> createState() => _ZoneEntryScreenState();
}
class _ZoneEntryScreenState extends State<ZoneEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _zoneIdController;
  late TextEditingController _titleController;
  late TextEditingController _addressController;
  late TextEditingController _onuMacController;
  late TextEditingController _deviceTypeController;
  late TextEditingController _gpsController;
  late String _status;
  bool _isFetchingLocation = false; // GPS ফেচিং স্ট্যাটাস
  @override
  void initState() {
    super.initState();
    final isEditing = widget.zone != null;
    _zoneIdController = TextEditingController(text: isEditing ? widget.zone!.zoneId : '');
    _titleController = TextEditingController(text: isEditing ? widget.zone!.title : '');
    _addressController = TextEditingController(text: isEditing ? widget.zone!.address : '');
    _onuMacController = TextEditingController(text: isEditing ? widget.zone!.onuMac : '');
    _deviceTypeController = TextEditingController(text: isEditing ? widget.zone!.deviceType : '');
    _gpsController = TextEditingController(text: isEditing ? widget.zone!.gps : '');
    _status = isEditing ? widget.zone!.status : 'Active';
  }
  // --- আপডেট করা ফাংশন: GPS লোকেশন ফেচ করা (Real-time logic) ---
  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _isFetchingLocation = true;
      _gpsController.text = 'Fetching...'; // Show immediate feedback
    });
    try {
      // ** Start of REAL GEOLOCATOR LOGIC **
      // 1. Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('লোকেশন সার্ভিস বন্ধ আছে। এটি চালু করুন।')));
        return;
      }
     
      // 2. Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('লোকেশন পারমিশন দেওয়া হয়নি।')));
          return;
        }
      }
     
      // 3. Get the current position
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String coordinates = "${position.latitude}, ${position.longitude}";
      // ** End of REAL GEOLOCATOR LOGIC **
      _gpsController.text = coordinates;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('লোকেশন সফলভাবে যুক্ত হয়েছে।')));
    } catch (e) {
      _gpsController.text = ''; // Clear on error
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('লোকেশন ফেচ করতে সমস্যা হয়েছে। Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }
  // --- GPS ফাংশন শেষ ---
  Future<void> _saveZone() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      List<WifiZone> zones = [];
      String? zonesJson = prefs.getString(AppConfig.wifiZones);
      if (zonesJson != null) {
        List<dynamic> decoded = jsonDecode(zonesJson);
        zones = decoded.map((e) => WifiZone.fromJson(e)).toList();
      }
      if (widget.zone != null) {
        // Edit existing zone
        final index = zones.indexWhere((z) => z.id == widget.zone!.id);
        if (index != -1) {
          zones[index].zoneId = _zoneIdController.text;
          zones[index].title = _titleController.text;
          zones[index].address = _addressController.text;
          zones[index].onuMac = _onuMacController.text;
          zones[index].deviceType = _deviceTypeController.text;
          zones[index].gps = _gpsController.text;
          zones[index].status = _status;
        }
      } else {
        // Add new zone
        final newZone = WifiZone(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          zoneId: _zoneIdController.text,
          title: _titleController.text,
          address: _addressController.text,
          onuMac: _onuMacController.text,
          deviceType: _deviceTypeController.text,
          gps: _gpsController.text,
          status: _status,
        );
        zones.add(newZone);
      }
      await prefs.setString(AppConfig.wifiZones, jsonEncode(zones.map((e) => e.toJson()).toList()));
     
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.zone != null ? "জোন আপডেট হয়েছে।" : "নতুন জোন যুক্ত হয়েছে।")));
        Navigator.pop(context);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zone != null ? "জোন এডিট করুন" : "নতুন জোন যোগ করুন"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _zoneIdController,
                decoration: const InputDecoration(labelText: "জোন আইডি", prefixIcon: Icon(Icons.vpn_key)),
                keyboardType: TextInputType.text,
                validator: (v) => v!.isEmpty ? 'জোন আইডি আবশ্যক' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "টাইটেল/নাম", prefixIcon: Icon(Icons.tag)),
                keyboardType: TextInputType.text,
                validator: (v) => v!.isEmpty ? 'নাম আবশ্যক' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: "ঠিকানা", prefixIcon: Icon(Icons.location_on)),
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _onuMacController,
                decoration: const InputDecoration(labelText: "ONU MAC", prefixIcon: Icon(Icons.dvr)),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _deviceTypeController,
                decoration: const InputDecoration(labelText: "ডিভাইস টাইপ (যেমন: Router, Switch)", prefixIcon: Icon(Icons.devices)),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 15),
             
              // GPS Field with Location Fetch Button
              TextField(
                controller: _gpsController,
                readOnly: _isFetchingLocation, // ফেচ করার সময় এডিট বন্ধ থাকবে
                decoration: InputDecoration(
                  labelText: "GPS কো-অর্ডিনেট",
                  prefixIcon: const Icon(Icons.gps_fixed),
                  // Location Fetch Button
                  suffixIcon: _isFetchingLocation
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.my_location, color: Color(0xFF00B4D8)),
                          onPressed: _getCurrentLocation,
                          tooltip: 'বর্তমান লোকেশন ফেচ করুন',
                        ),
                ),
                keyboardType: TextInputType.text,
              ),
             
              const SizedBox(height: 20),
             
              // Status Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00B4D8).withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _status,
                    icon: const Icon(Icons.arrow_drop_down),
                    hint: const Text("স্ট্যাটাস নির্বাচন করুন"),
                    items: ['Active', 'Pending', 'Inactive'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: TextStyle(color: value == 'Active' ? Colors.green.shade700 : value == 'Pending' ? Colors.orange.shade700 : Colors.red.shade700)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _status = newValue!;
                      });
                    },
                  ),
                ),
              ),
             
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveZone,
                  child: Text(widget.zone != null ? "আপডেট করুন" : "সংরক্ষণ করুন"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}