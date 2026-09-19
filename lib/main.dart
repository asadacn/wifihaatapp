// ============================================================================
// WiFi Zone Manager  —  main.dart
//
// pubspec.yaml -> dependencies (এগুলো থাকতে হবে):
//   firebase_core, firebase_auth, cloud_firestore
//   shared_preferences, intl, fl_chart
//   share_plus: ^8.0.0
//   url_launcher: ^6.2.2
//   image_picker: ^1.1.2
//   file_picker: ^6.1.1
//   geolocator: ^11.0.0
// (image_cropper ও path_provider আর লাগছে না — বাদ দিতে পারেন)
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart' as prefs;
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// ---------------------------------------------------------------------------
// Colors / config
// ---------------------------------------------------------------------------
class AppColors {
  static const cobalt = Color(0xFF0047AB);
  static const navy = Color(0xFF00296B);
  static const deep = Color(0xFF001A4D);
  static const sky = Color(0xFF00B4D8);
  static const paleSky = Color(0xFFCAF0F8);
  static const bg = Color(0xFFF0F9FF);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const success = Color(0xFF16A34A);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
}

extension ColorOpacityX on Color {
  /// Version-independent replacement for withOpacity()
  Color o(double opacity) =>
      withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

class AppConfig {
  static const String companyName = 'company_name';
  static const String companyPhone = 'company_phone';
  static const String commissionRate = 'commission_rate';
  static const String invoiceCounter = 'invoice_counter';
  static const String companyLogo = 'company_logo';
  static const String wifiZones = 'wifi_zones';
  static const String savedCardPrices = 'saved_card_prices';
  static const String cardStock = 'card_stock';
  static const String salesHistory = 'sales_history';

  static const int lowStockLimit = 10;
  static const List<int> defaultPrices = [9, 15, 25, 50, 89, 249];

  static const List<String> allKeys = [
    companyName,
    companyPhone,
    commissionRate,
    invoiceCounter,
    companyLogo,
    wifiZones,
    savedCardPrices,
    cardStock,
    salesHistory,
  ];
}

String? _firebaseInitializationError;

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------
final DateFormat _saleDateFormat = DateFormat('yyyy-MM-dd hh:mm a', 'en_US');
final NumberFormat _moneyFormat = NumberFormat.decimalPattern('en_IN');

DateTime? parseSaleDate(String s) {
  try {
    return _saleDateFormat.parse(s);
  } catch (_) {
    return null;
  }
}

String taka(num v) => '${_moneyFormat.format(v.round())} Tk';

const List<String> _bnWeekdays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'];
const List<String> _bnMonths = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
];

/// "23.81, 90.41" -> [23.81, 90.41]  (invalid হলে null)
List<double>? parseGps(String s) {
  final parts = s.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return [lat, lng];
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.toStringAsFixed(0)} মি.'
    : '${(meters / 1000).toStringAsFixed(1)} কি.মি.';

ImageProvider? _logoImage(String? encodedLogo) {
  if (encodedLogo == null || encodedLogo.isEmpty) return null;
  try {
    return MemoryImage(Uint8List.fromList(base64Decode(encodedLogo)));
  } catch (_) {
    return null;
  }
}

void showMsg(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    behavior: SnackBarBehavior.floating,
    backgroundColor: error ? AppColors.danger : AppColors.navy,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'হ্যাঁ',
  String no = 'না',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger
              ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
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

  int get totalPieces => items.values.fold(0, (a, b) => a + b);

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
        invoiceNumber: (json['invoiceNumber'] ?? 'OLD').toString(),
        retailerName: (json['retailerName'] ?? '').toString(),
        retailerPhone: (json['retailerPhone'] ?? '').toString(),
        grandTotal: (json['grandTotal'] as num?)?.toDouble() ?? 0.0,
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
        discountRate: (json['discountRate'] as num?)?.toDouble() ?? 10.0,
        cashAmount: (json['cashAmount'] as num?)?.toDouble() ?? 0.0,
        date: (json['date'] ?? '').toString(),
        items: (json['items'] as Map?)?.map<String, int>(
                (k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            <String, int>{},
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
        id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
        zoneId: (json['zoneId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        onuMac: (json['onuMac'] ?? '').toString(),
        deviceType: (json['deviceType'] ?? '').toString(),
        gps: (json['gps'] ?? '').toString(),
        status: (json['status'] ?? 'Active').toString(),
      );
}

// ---------------------------------------------------------------------------
// AppPrefs : local storage (shared_preferences) + Firestore mirror
//
// * সব read/write আগে লোকালে হয় -> অফলাইনেও অ্যাপ চলে
// * Firestore-এ লেখা await করা হয় না (অফলাইনে await করলে UI আটকে যেত)
// * Firestore লিসেনার শুধু লগইনের পরে চলে; নতুন ডেটা এলে dataVersion বাড়ে,
//   আর স্ক্রিনগুলো নিজে থেকে রিলোড হয়
// ---------------------------------------------------------------------------
class AppPrefs {
  AppPrefs._(this._local);
  final prefs.SharedPreferences _local;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
  static final ValueNotifier<String?> syncError = ValueNotifier<String?>(null);
  static final ValueNotifier<bool> syncPending = ValueNotifier<bool>(false);

  static const Set<String> _doubleKeys = {AppConfig.commissionRate};
  static const Set<String> _intKeys = {AppConfig.invoiceCounter};

  static bool get cloudReady => Firebase.apps.isNotEmpty;
  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('wifihaat').doc('app_data');

  static Future<AppPrefs> getInstance() async =>
      AppPrefs._(await prefs.SharedPreferences.getInstance());

  // ---- cloud listener ------------------------------------------------------
  static void startListener() {
    if (_sub != null || !cloudReady) return;
    _sub = _doc.snapshots(includeMetadataChanges: true).listen(
      (snap) async {
        syncPending.value = snap.metadata.hasPendingWrites;
        if (snap.metadata.hasPendingWrites) return;
        final changed = await _apply(snap.data());
        syncError.value = null;
        if (changed) dataVersion.value++;
      },
      onError: (Object error) {
        syncError.value = error.toString();
        debugPrint('Firestore listener error: $error');
      },
    );
  }

  static Future<void> stopListener() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }

  /// Firestore থেকে এখনই নতুন ডেটা টেনে আনে
  static Future<bool> pullNow() async {
    if (!cloudReady) return false;
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 10));
      final changed = await _apply(snap.data());
      syncError.value = null;
      if (changed) dataVersion.value++;
      return true;
    } catch (e) {
      syncError.value = e.toString();
      return false;
    }
  }

  static Future<bool> _apply(Map<String, dynamic>? data) async {
    if (data == null || data.isEmpty) return false;
    final local = await prefs.SharedPreferences.getInstance();
    var changed = false;
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      final current = local.get(key);
      if (value is String) {
        if (current != value) {
          await local.setString(key, value);
          changed = true;
        }
      } else if (value is bool) {
        if (current != value) {
          await local.setBool(key, value);
          changed = true;
        }
      } else if (value is num) {
        // Web-এ 10.0 Firestore-এ int হয়ে যেতে পারে, তাই টাইপ ঠিক করে নিই
        final wantDouble = _doubleKeys.contains(key) ||
            (value is double && !_intKeys.contains(key));
        final same = current is num &&
            current.toDouble() == value.toDouble() &&
            ((current is double) == wantDouble);
        if (!same) {
          if (wantDouble) {
            await local.setDouble(key, value.toDouble());
          } else {
            await local.setInt(key, value.toInt());
          }
          changed = true;
        }
      } else if (value is List) {
        final list = value.map((e) => e.toString()).toList();
        final same = current is List &&
            listEquals(current.map((e) => e.toString()).toList(), list);
        if (!same) {
          await local.setStringList(key, list);
          changed = true;
        }
      }
    }
    return changed;
  }

  static Future<void> _pushAsync(Map<String, Object?> data) async {
    try {
      await _doc.set(data, SetOptions(merge: true));
      syncError.value = null;
    } catch (e) {
      syncError.value = e.toString();
      debugPrint('Firebase write failed: $e');
    }
  }

  void _push(String key, Object? value) {
    if (!cloudReady) return;
    unawaited(_pushAsync({key: value}));
  }

  /// লোকাল সব ডেটা ক্লাউডে পাঠায় (ব্যবহারকারী চাইলে)
  Future<bool> pushAll() async {
    if (!cloudReady) return false;
    final data = <String, Object?>{};
    for (final k in AppConfig.allKeys) {
      final v = _local.get(k);
      if (v != null) data[k] = v;
    }
    try {
      await _doc
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
      syncError.value = null;
      return true;
    } catch (e) {
      syncError.value = e.toString();
      return false;
    }
  }

  /// Firestore ডকুমেন্টের (1 MiB লিমিট) আনুমানিক সাইজ
  int estimatedCloudBytes() {
    var n = 0;
    for (final k in AppConfig.allKeys) {
      final v = _local.get(k);
      if (v is String) {
        n += utf8.encode(v).length;
      } else if (v is List) {
        for (final e in v) {
          n += e.toString().length;
        }
      }
    }
    return n;
  }

  // ---- raw access ----------------------------------------------------------
  String? getString(String key) {
    final v = _local.get(key);
    return v is String ? v : null;
  }

  int? getInt(String key) {
    final v = _local.get(key);
    return v is num ? v.toInt() : null;
  }

  double? getDouble(String key) {
    final v = _local.get(key);
    return v is num ? v.toDouble() : null;
  }

  List<String>? getStringList(String key) {
    final v = _local.get(key);
    return v is List ? v.map((e) => e.toString()).toList() : null;
  }

  Future<void> setString(String key, String value) async {
    await _local.setString(key, value);
    _push(key, value);
  }

  Future<void> setInt(String key, int value) async {
    await _local.setInt(key, value);
    _push(key, value);
  }

  Future<void> setDouble(String key, double value) async {
    await _local.setDouble(key, value);
    _push(key, value);
  }

  Future<void> setStringList(String key, List<String> value) async {
    await _local.setStringList(key, value);
    _push(key, value);
  }

  Future<void> remove(String key) async {
    await _local.remove(key);
    _push(key, FieldValue.delete());
  }

  // ---- typed helpers -------------------------------------------------------
  List<int> cardPrices() {
    final saved = getStringList(AppConfig.savedCardPrices);
    if (saved == null) return List<int>.from(AppConfig.defaultPrices);
    return saved.map(int.tryParse).whereType<int>().toList()..sort();
  }

  Future<void> saveCardPrices(List<int> prices) => setStringList(
      AppConfig.savedCardPrices, prices.map((e) => e.toString()).toList());

  Map<String, int> stock() {
    final s = getString(AppConfig.cardStock);
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map;
      return m.map<String, int>(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveStock(Map<String, int> stock) =>
      setString(AppConfig.cardStock, jsonEncode(stock));

  List<SaleRecord> history() {
    final s = getString(AppConfig.salesHistory);
    if (s == null) return [];
    try {
      final l = jsonDecode(s) as List;
      return l
          .map((e) => SaleRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<SaleRecord> h) => setString(
      AppConfig.salesHistory, jsonEncode(h.map((e) => e.toJson()).toList()));

  List<WifiZone> zones() {
    final s = getString(AppConfig.wifiZones);
    if (s == null) return [];
    try {
      final l = jsonDecode(s) as List;
      return l
          .map((e) => WifiZone.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveZones(List<WifiZone> zones) => setString(
      AppConfig.wifiZones, jsonEncode(zones.map((e) => e.toJson()).toList()));
}

Future<bool> _initializeFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) return true;
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      await Firebase.initializeApp();
    }
    return true;
  } catch (error) {
    _firebaseInitializationError = error.toString();
    debugPrint('Firebase is not configured: $error');
    return false;
  }
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WifiCardApp());
}

class WifiCardApp extends StatelessWidget {
  const WifiCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.sky.o(0.3)),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi Zone Manager',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.cobalt,
          primary: AppColors.cobalt,
          secondary: AppColors.sky,
          tertiary: AppColors.paleSky,
          surface: AppColors.bg,
          onSurface: AppColors.ink,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppColors.sky.o(0.2)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.cobalt,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.cobalt),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cobalt,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            elevation: 2,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.cobalt,
            side: BorderSide(color: AppColors.cobalt.o(0.4)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.cobalt, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          prefixIconColor: AppColors.cobalt,
          labelStyle: TextStyle(color: AppColors.cobalt.o(0.75)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.paleSky,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? AppColors.cobalt : AppColors.muted,
            );
          }),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Auth gate
// ---------------------------------------------------------------------------
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

class InitErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const InitErrorScreen(
      {super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 72, color: AppColors.danger.o(0.8)),
                const SizedBox(height: 16),
                const Text('সার্ভারে সংযোগ করা যায়নি',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('আবার চেষ্টা করুন'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _initializeFirebase().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _firebaseInitializationError =
            'Firebase সার্ভারে সংযোগ করতে সময় শেষ হয়েছে।';
        return false;
      },
    );
    if (!mounted) return;
    setState(() {
      _ready = ok;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const FirebaseLoadingScreen();
    if (!_ready) {
      return InitErrorScreen(
        message: _firebaseInitializationError ??
            'ইন্টারনেট সংযোগ ও Firebase কনফিগারেশন যাচাই করুন।',
        onRetry: () {
          setState(() => _loading = true);
          _init();
        },
      );
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FirebaseLoadingScreen();
        }
        return snapshot.data == null ? const LoginScreen() : const HomeScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------
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
  String? _message;
  bool _isError = true;
  late final AnimationController _logoAnimCtrl;
  late final Animation<double> _logoPulse;

  @override
  void initState() {
    super.initState();
    _logoAnimCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _logoPulse = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(parent: _logoAnimCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _logoAnimCtrl.dispose();
    super.dispose();
  }

  void _setMessage(String text, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _isError = error;
    });
  }

  String _errorText(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'ইমেইল বা পাসওয়ার্ড সঠিক নয়।';
      case 'operation-not-allowed':
        return 'Firebase Console-এ Email/Password sign-in চালু করুন।';
      case 'invalid-email':
        return 'সঠিক email address লিখুন।';
      case 'user-disabled':
        return 'এই admin account বন্ধ করা আছে।';
      case 'too-many-requests':
        return 'অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।';
      case 'network-request-failed':
        return 'ইন্টারনেট সংযোগ নেই। সংযোগ দেখে আবার চেষ্টা করুন।';
      default:
        return 'লগইন করা যায়নি (${error.code})। আবার চেষ্টা করুন।';
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _setMessage('ইমেইল এবং পাসওয়ার্ড দিন।');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (error) {
      _setMessage(_errorText(error));
    } catch (_) {
      _setMessage('লগইন সেবায় সংযোগ করা যাচ্ছে না। আবার চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _setMessage('পাসওয়ার্ড রিসেটের জন্য আগে ইমেইল লিখুন।');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _setMessage('$email -এ পাসওয়ার্ড রিসেট লিংক পাঠানো হয়েছে।',
          error: false);
    } on FirebaseAuthException catch (error) {
      _setMessage(_errorText(error));
    } catch (_) {
      _setMessage('রিসেট লিংক পাঠানো যায়নি। আবার চেষ্টা করুন।');
    }
  }

  InputDecoration _glass(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.o(0.8)),
      prefixIcon: Icon(icon, color: Colors.white.o(0.8)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.o(0.1),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.o(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.cobalt, AppColors.navy],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ScaleTransition(
                        scale: _logoPulse,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white.o(0.2),
                          child: const Icon(Icons.wifi,
                              size: 48, color: Colors.white),
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
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 6),
                    Text('Admin login',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.white.o(0.7), fontSize: 16)),
                    const SizedBox(height: 32),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.o(0.15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.o(0.2)),
                          ),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _glass(
                                      'Admin email', Icons.email_outlined),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _login(),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _glass(
                                    'Password',
                                    Icons.lock_outline,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: Colors.white.o(0.8),
                                      ),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                ),
                                if (_message != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: (_isError
                                              ? Colors.red
                                              : Colors.green)
                                          .o(0.18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _isError
                                              ? Icons.error_outline
                                              : Icons.check_circle_outline,
                                          color: _isError
                                              ? Colors.red.shade100
                                              : Colors.green.shade100,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _message!,
                                            style: TextStyle(
                                              color: _isError
                                                  ? Colors.red.shade100
                                                  : Colors.green.shade100,
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
                                                color: AppColors.cobalt))
                                        : const Icon(Icons.login,
                                            color: AppColors.cobalt),
                                    label: Text(
                                      _loading ? 'লগইন হচ্ছে...' : 'লগইন করুন',
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.cobalt),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppColors.cobalt,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _loading ? null : _resetPassword,
                                  child: Text(
                                    'পাসওয়ার্ড ভুলে গেছেন?',
                                    style: TextStyle(
                                        color: Colors.white.o(0.85),
                                        decoration: TextDecoration.underline,
                                        decorationColor: Colors.white.o(0.85)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('WiFi Zone Manager',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.white.o(0.5), fontSize: 12)),
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

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppPrefs.syncError, AppPrefs.syncPending]),
      builder: (context, _) {
        IconData icon = Icons.cloud_done_outlined;
        Color color = const Color(0xFF86EFAC);
        String tip = 'ক্লাউডে সিঙ্ক আছে';
        if (!AppPrefs.cloudReady) {
          icon = Icons.cloud_off_outlined;
          color = const Color(0xFFFCA5A5);
          tip = 'ক্লাউড সংযোগ নেই';
        } else if (AppPrefs.syncError.value != null) {
          icon = Icons.sync_problem_outlined;
          color = const Color(0xFFFCA5A5);
          tip = 'সিঙ্কে সমস্যা: ${AppPrefs.syncError.value}';
        } else if (AppPrefs.syncPending.value) {
          icon = Icons.cloud_upload_outlined;
          color = const Color(0xFFFCD34D);
          tip = 'সিঙ্ক হচ্ছে (অফলাইনে থাকলে ইন্টারনেট এলে হবে)';
        }
        return Tooltip(
          message: tip,
          triggerMode: TooltipTriggerMode.tap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 22),
          ),
        );
      },
    );
  }
}

class ModernHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? logoBase64;
  final VoidCallback? onSettingsTap;

  const ModernHeader({
    super.key,
    required this.title,
    this.subtitle = '',
    this.logoBase64,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final logo = _logoImage(logoBase64);
    final email = AppPrefs.cloudReady
        ? (FirebaseAuth.instance.currentUser?.email ?? '')
        : '';
    final now = DateTime.now();
    final dateText = '${now.day} ${_bnMonths[now.month - 1]} ${now.year}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 10, 8, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cobalt, AppColors.navy, AppColors.deep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: AppColors.cobalt.o(0.25),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.o(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.o(0.35), width: 2),
                ),
                child: logo != null
                    ? ClipOval(
                        child: Image(
                            image: logo,
                            fit: BoxFit.cover,
                            width: 46,
                            height: 46))
                    : const Icon(Icons.wifi, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.o(0.75),
                            fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              const SyncBadge(),
              if (onSettingsTap != null)
                IconButton(
                  tooltip: 'সেটিংস',
                  icon: Icon(Icons.settings_outlined,
                      color: Colors.white.o(0.9)),
                  onPressed: onSettingsTap,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: Colors.white.o(0.6)),
                const SizedBox(width: 6),
                Text(dateText,
                    style: TextStyle(fontSize: 12, color: Colors.white.o(0.7))),
                const Spacer(),
                if (email.isNotEmpty)
                  Flexible(
                    child: Text(email,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.white.o(0.55))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.sky.o(0.15)),
        boxShadow: [
          BoxShadow(
              color: AppColors.cobalt.o(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.cobalt)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  const EmptyState({super.key, required this.icon, required this.text, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home (bottom navigation)
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    AppPrefs.startListener(); // লগইনের পরেই ক্লাউড লিসেনার চালু
  }

  @override
  void dispose() {
    unawaited(AppPrefs.stopListener());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack: ট্যাব বদলালে ফর্মের ডেটা হারাবে না (যেমন অর্ধেক লেখা বিক্রয়)
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(active: _index == 0),
          SalesEntryScreen(active: _index == 1),
          HistoryScreen(active: _index == 2),
          WifiZoneScreen(active: _index == 3),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        elevation: 10,
        shadowColor: AppColors.cobalt.o(0.15),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon:
                Icon(Icons.grid_view_rounded, color: AppColors.cobalt),
            label: 'ড্যাশবোর্ড',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon:
                Icon(Icons.add_circle_rounded, color: AppColors.cobalt),
            label: 'নতুন বিক্রয়',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon:
                Icon(Icons.receipt_long_rounded, color: AppColors.cobalt),
            label: 'ইতিহাস',
          ),
          NavigationDestination(
            icon: Icon(Icons.router_outlined),
            selectedIcon: Icon(Icons.router_rounded, color: AppColors.cobalt),
            label: 'ওয়াইফাই জোন',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  final bool active;
  const DashboardScreen({super.key, this.active = true});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String _companyName = 'WiFi Zone Manager';
  String? _logo;
  List<int> _prices = [];
  Map<String, int> _stock = {};
  double _today = 0, _week = 0, _month = 0, _stockValue = 0;
  List<double> _weekData = List<double>.filled(7, 0.0);
  List<String> _weekLabels = [];
  Map<String, int> _monthCardSales = {};
  int _cloudBytes = 0;

  @override
  void initState() {
    super.initState();
    AppPrefs.dataVersion.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    AppPrefs.dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final history = p.history();
    if (!mounted) return;
    setState(() {
      final name = p.getString(AppConfig.companyName);
      _companyName =
          (name == null || name.trim().isEmpty) ? 'WiFi Zone Manager' : name;
      _logo = p.getString(AppConfig.companyLogo);
      _prices = p.cardPrices();
      _stock = p.stock();
      _cloudBytes = p.estimatedCloudBytes();
      _compute(history);
      _stockValue = 0;
      for (final price in _prices) {
        _stockValue += price * (_stock['$price'] ?? 0);
      }
      _loading = false;
    });
  }

  void _compute(List<SaleRecord> history) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    double t = 0, w = 0, m = 0;
    final chart = List<double>.filled(7, 0.0);
    final cards = <String, int>{};
    final labels = <String>[];
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      labels.add(_bnWeekdays[d.weekday - 1]);
    }
    for (final sale in history) {
      final dt = parseSaleDate(sale.date);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(day).inDays;
      if (diff == 0) t += sale.cashAmount;
      if (diff >= 0 && diff < 7) {
        w += sale.cashAmount;
        chart[6 - diff] += sale.cashAmount;
      }
      if (dt.year == now.year && dt.month == now.month) {
        m += sale.cashAmount;
        sale.items.forEach((price, qty) {
          cards[price] = (cards[price] ?? 0) + qty;
        });
      }
    }
    _today = t;
    _week = w;
    _month = m;
    _weekData = chart;
    _weekLabels = labels;
    _monthCardSales = cards;
  }

  Future<void> _refresh() async {
    await AppPrefs.pullNow();
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _load();
  }

  Future<void> _applyStock(String price, int qty,
      {required bool overwrite}) async {
    final p = await AppPrefs.getInstance();
    final latest = p.stock(); // সবসময় সর্বশেষ স্টক থেকে হিসাব
    latest[price] = overwrite ? qty : (latest[price] ?? 0) + qty;
    await p.saveStock(latest);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    showMsg(context, overwrite ? 'স্টক সংশোধন হয়েছে' : 'স্টক যোগ হয়েছে');
  }

  void _manageStock(String price) {
    final ctrl = TextEditingController();
    final current = _stock[price] ?? 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('স্টক ম্যানেজ ($price Tk)',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.cobalt)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('বর্তমান স্টক: $current টি',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'সংখ্যা (pcs)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          OutlinedButton(
            onPressed: () {
              final q = int.tryParse(ctrl.text);
              if (q == null) return;
              Navigator.pop(ctx);
              _applyStock(price, q, overwrite: true);
            },
            child: const Text('সেট করুন'),
          ),
          ElevatedButton(
            onPressed: () {
              final q = int.tryParse(ctrl.text);
              if (q == null) return;
              Navigator.pop(ctx);
              _applyStock(price, q, overwrite: false);
            },
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, double value, IconData icon, List<Color> colors) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: colors.first.o(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.white.o(0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(taka(value),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(IconData icon, Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.o(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.o(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink))),
        ],
      ),
    );
  }

  Widget _weekChart() {
    final maxV = _weekData.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV == 0 ? 10 : maxV * 1.25,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.navy,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                taka(rod.toY),
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    v.toInt() >= 0 && v.toInt() < _weekLabels.length
                        ? _weekLabels[v.toInt()]
                        : '',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.muted),
                  ),
                ),
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _weekData[i],
                color: i == 6
                    ? AppColors.cobalt
                    : (_weekData[i] > 0 ? AppColors.sky : AppColors.paleSky),
                width: 16,
                borderRadius: BorderRadius.circular(5),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _cardChart() {
    double maxQty = 0;
    for (final p in _prices) {
      final q = (_monthCardSales['$p'] ?? 0).toDouble();
      if (q > maxQty) maxQty = q;
    }
    final maxY = maxQty == 0 ? 10.0 : maxQty * 1.25;
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.sky,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${rod.toY.toStringAsFixed(0)} pcs',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    v.toInt() >= 0 && v.toInt() < _prices.length
                        ? '${_prices[v.toInt()]}'
                        : '',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.muted),
                  ),
                ),
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(_prices.length, (i) {
            final q = (_monthCardSales['${_prices[i]}'] ?? 0).toDouble();
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: q,
                gradient: const LinearGradient(
                  colors: [AppColors.cobalt, AppColors.sky],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 16,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(5)),
                backDrawRodData: BackgroundBarChartRodData(
                    show: true, toY: maxY, color: AppColors.bg),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final low = _prices
        .where((p) => (_stock['$p'] ?? 0) < AppConfig.lowStockLimit)
        .toList();
    final weekHasData = _weekData.any((v) => v > 0);
    final monthHasData = _monthCardSales.isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          ModernHeader(
            title: 'ড্যাশবোর্ড',
            subtitle: _companyName,
            logoBase64: _logo,
            onSettingsTap: _openSettings,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(children: [
                    _stat('আজকের নেট বিক্রয়', _today, Icons.today_rounded,
                        const [AppColors.cobalt, Color(0xFF1D6FD8)]),
                    const SizedBox(width: 12),
                    _stat('এই সপ্তাহ (৭ দিন)', _week, Icons.date_range_rounded,
                        const [Color(0xFF0077B6), AppColors.sky]),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _stat('এই মাস', _month, Icons.calendar_month_rounded,
                        const [AppColors.navy, AppColors.cobalt]),
                    const SizedBox(width: 12),
                    _stat('মোট স্টক মূল্য', _stockValue,
                        Icons.inventory_2_rounded,
                        const [Color(0xFF0F766E), Color(0xFF14B8A6)]),
                  ]),
                  const SizedBox(height: 16),
                  if (low.isNotEmpty)
                    _banner(
                      Icons.warning_amber_rounded,
                      AppColors.warn,
                      'কম স্টক: ${low.map((p) => '$p Tk (${_stock['$p'] ?? 0})').join(', ')}',
                    ),
                  if (_cloudBytes > 700 * 1024)
                    _banner(
                      Icons.storage_rounded,
                      AppColors.danger,
                      'ক্লাউড ডেটা সীমার কাছাকাছি (${(_cloudBytes / 1024).toStringAsFixed(0)} KB / 1024 KB)। '
                      'সেটিংস থেকে ব্যাকআপ নিন এবং পুরনো ইতিহাস আলাদা করার ব্যবস্থা করুন।',
                    ),
                  const SectionTitle('সাপ্তাহিক রেভিনিউ'),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    child: weekHasData
                        ? _weekChart()
                        : const SizedBox(
                            height: 120,
                            child: EmptyState(
                                icon: Icons.bar_chart_rounded,
                                text: 'এই সপ্তাহে কোনো বিক্রয় নেই')),
                  ),
                  const SectionTitle('এই মাসে কার্ড অনুযায়ী বিক্রয়'),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    child: monthHasData
                        ? _cardChart()
                        : const SizedBox(
                            height: 120,
                            child: EmptyState(
                                icon: Icons.credit_card_rounded,
                                text: 'এই মাসে কোনো কার্ড বিক্রি হয়নি')),
                  ),
                  SectionTitle(
                    'স্টক আপডেট',
                    trailing: const Text('ট্যাপ করে পরিবর্তন করুন',
                        style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ),
                  if (_prices.isEmpty)
                    const AppCard(
                        child: Text(
                            'কোনো কার্ডের দাম নেই। সেটিংস থেকে দাম যোগ করুন।'))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.9,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _prices.length,
                      itemBuilder: (context, index) {
                        final price = _prices[index].toString();
                        final qty = _stock[price] ?? 0;
                        final out = qty == 0;
                        final isLow = qty < AppConfig.lowStockLimit;
                        final Color tone = out
                            ? AppColors.danger
                            : (isLow ? AppColors.warn : AppColors.cobalt);
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _manageStock(price),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: tone.o(0.35)),
                                gradient: LinearGradient(
                                  colors: [tone.o(0.12), Colors.white],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 19,
                                    backgroundColor: tone.o(0.15),
                                    child: Icon(Icons.credit_card,
                                        color: tone, size: 22),
                                  ),
                                  const SizedBox(height: 10),
                                  Text('$price Tk',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: tone)),
                                  const SizedBox(height: 2),
                                  Text(out ? 'স্টক শেষ' : '$qty pcs',
                                      style: TextStyle(
                                          color: out ? tone : AppColors.ink,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
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
}

// ---------------------------------------------------------------------------
// Sales entry
// ---------------------------------------------------------------------------
class SalesEntryScreen extends StatefulWidget {
  final bool active;
  const SalesEntryScreen({super.key, this.active = true});
  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  List<int> _prices = [];
  Map<String, int> _stock = {};
  final Map<int, int> _qty = {};
  final Map<int, TextEditingController> _ctrls = {};
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  List<String> _dealers = [];
  final Map<String, String> _dealerPhone = {};
  double _rate = 10.0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (mounted) setState(() {});
    });
    AppPrefs.dataVersion.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(SalesEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    AppPrefs.dataVersion.removeListener(_load);
    _name.dispose();
    _phone.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final history = p.history();
    if (!mounted) return;
    setState(() {
      _rate = p.getDouble(AppConfig.commissionRate) ?? 10.0;
      _prices = p.cardPrices();
      _stock = p.stock();
      final seen = <String>{};
      _dealers = [];
      _dealerPhone.clear();
      for (final s in history) {
        final n = s.retailerName.trim();
        if (n.isEmpty) continue;
        if (seen.add(n)) {
          _dealers.add(n);
          _dealerPhone[n] = s.retailerPhone;
        }
      }
      // নতুন দামের জন্য কন্ট্রোলার, মুছে ফেলা দামের কন্ট্রোলার dispose
      for (final price in _prices) {
        _qty.putIfAbsent(price, () => 0);
        _ctrls.putIfAbsent(price, () => TextEditingController());
      }
      final removed =
          _ctrls.keys.where((k) => !_prices.contains(k)).toList();
      final toDispose = <TextEditingController>[];
      for (final k in removed) {
        final c = _ctrls.remove(k);
        if (c != null) toDispose.add(c);
        _qty.remove(k);
      }
      if (toDispose.isNotEmpty) {
        // ফ্রেম শেষ হলে dispose, যাতে পুরনো TextField আগে unmount হয়
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final c in toDispose) {
            c.dispose();
          }
        });
      }
      _loading = false;
    });
  }

  void _setQty(int price, int q) {
    if (q < 0) q = 0;
    if (q > 99999) q = 99999;
    final ctrl = _ctrls[price];
    final text = q == 0 ? '' : '$q';
    if (ctrl != null && ctrl.text != text) {
      ctrl.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() => _qty[price] = q);
  }

  void _clearAll() {
    setState(() {
      for (final price in _prices) {
        _qty[price] = 0;
        _ctrls[price]?.clear();
      }
      _name.clear();
      _phone.clear();
    });
    FocusScope.of(context).unfocus();
  }

  double get _total {
    double t = 0;
    for (final price in _prices) {
      t += price * (_qty[price] ?? 0);
    }
    return t;
  }

  int get _pieces => _prices.fold(0, (a, p) => a + (_qty[p] ?? 0));

  List<String> get _suggestions {
    final q = _name.text.trim().toLowerCase();
    if (q.isEmpty) return _dealers.take(6).toList();
    return _dealers
        .where((d) => d.toLowerCase().contains(q) && d.toLowerCase() != q)
        .take(6)
        .toList();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMsg(context, 'ডিলারের নাম লিখুন', error: true);
      return;
    }
    final sold = <String, int>{};
    final problems = <String>[];
    double total = 0;
    for (final price in _prices) {
      final q = _qty[price] ?? 0;
      if (q <= 0) continue;
      final avail = _stock['$price'] ?? 0;
      if (avail < q) {
        problems.add('$price Tk — চাই $q, আছে $avail');
      } else {
        sold['$price'] = q;
        total += price * q;
      }
    }
    if (problems.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('স্টক পর্যাপ্ত নয়'),
          content: Text(problems.join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ঠিক আছে'))
          ],
        ),
      );
      return;
    }
    if (sold.isEmpty) {
      showMsg(context, 'অন্তত একটি কার্ডের পরিমাণ দিন', error: true);
      return;
    }
    final net = total - total * (_rate / 100);
    final ok = await confirmDialog(
      context,
      title: 'বিক্রয় নিশ্চিত করবেন?',
      message:
          '$name\n$_pieces পিস • মোট ${taka(total)}\nনেট প্রদেয়: ${taka(net)}',
      yes: 'নিশ্চিত করুন',
      no: 'বাতিল',
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      final p = await AppPrefs.getInstance();
      // সর্বশেষ স্টক আবার পড়ে যাচাই (অন্য ডিভাইসে বদলে থাকতে পারে)
      final latestStock = p.stock();
      for (final e in sold.entries) {
        if ((latestStock[e.key] ?? 0) < e.value) {
          if (mounted) {
            showMsg(context,
                '${e.key} Tk কার্ডের স্টক এইমাত্র বদলেছে। আবার চেষ্টা করুন।',
                error: true);
          }
          await _load();
          return;
        }
      }
      final rate = p.getDouble(AppConfig.commissionRate) ?? _rate;
      final discount = total * (rate / 100);
      final counter = (p.getInt(AppConfig.invoiceCounter) ?? 1000) + 1;
      final sale = SaleRecord(
        invoiceNumber: 'INV-$counter',
        retailerName: name,
        retailerPhone: _phone.text.trim(),
        grandTotal: total,
        discountAmount: discount,
        discountRate: rate,
        cashAmount: total - discount,
        date: _saleDateFormat.format(DateTime.now()),
        items: sold,
      );
      sold.forEach((k, q) => latestStock[k] = (latestStock[k] ?? 0) - q);
      final history = p.history()..insert(0, sale);
      await p.saveStock(latestStock);
      await p.saveHistory(history);
      await p.setInt(AppConfig.invoiceCounter, counter);
      if (!mounted) return;
      _clearAll();
      await _load();
      if (!mounted) return;
      await showDialog<void>(
          context: context, builder: (_) => InvoiceDialog(sale: sale));
    } catch (e) {
      if (mounted) showMsg(context, 'বিক্রয় সংরক্ষণ করা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _load();
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }

  Widget _priceRow(int price) {
    final qty = _qty[price] ?? 0;
    final stockQty = _stock['$price'] ?? 0;
    final over = qty > stockQty;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.cobalt, AppColors.sky]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$price',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stockQty > 0 ? 'স্টক: $stockQty টি' : 'স্টক শেষ',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: stockQty > 0
                            ? AppColors.sky
                            : AppColors.danger)),
                const SizedBox(height: 2),
                Text(
                  over
                      ? 'স্টকের বেশি!'
                      : (qty > 0 ? '= ${taka(price * qty)}' : ''),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: over ? AppColors.danger : AppColors.ink),
                ),
              ],
            ),
          ),
          _stepButton(Icons.remove, qty > 0 ? () => _setQty(price, qty - 1) : null),
          SizedBox(
            width: 54,
            child: TextField(
              controller: _ctrls[price],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: over ? AppColors.danger : AppColors.cobalt),
              decoration: InputDecoration(
                hintText: '0',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: over ? AppColors.danger : Colors.transparent)),
              ),
              onChanged: (v) => setState(() => _qty[price] = int.tryParse(v) ?? 0),
            ),
          ),
          _stepButton(Icons.add, () => _setQty(price, qty + 1)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final total = _total;
    final discount = total * (_rate / 100);
    final net = total - discount;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final suggestions = _suggestions;

    return Scaffold(
      body: Column(
        children: [
          ModernHeader(
            title: 'নতুন বিক্রয়',
            subtitle: 'কমিশন রেট: ${_rate.toStringAsFixed(1)}%',
            onSettingsTap: _openSettings,
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            labelText: 'ডিলার নাম',
                            prefixIcon: Icon(Icons.store)),
                      ),
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: suggestions
                              .map((d) => ActionChip(
                                    avatar: const Icon(Icons.history, size: 16),
                                    label: Text(d),
                                    onPressed: () {
                                      _name.text = d;
                                      _name.selection = TextSelection.collapsed(
                                          offset: d.length);
                                      final ph = _dealerPhone[d];
                                      if (ph != null && ph.isNotEmpty) {
                                        _phone.text = ph;
                                      }
                                    },
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: 'ফোন নাম্বার',
                            prefixIcon: Icon(Icons.phone)),
                      ),
                    ],
                  ),
                ),
                SectionTitle(
                  'কার্ড নির্বাচন',
                  trailing: TextButton.icon(
                    onPressed: (_pieces > 0 || _name.text.isNotEmpty)
                        ? _clearAll
                        : null,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('সব মুছুন'),
                  ),
                ),
                if (_prices.isEmpty)
                  const AppCard(
                      child: Text(
                          'কোনো কার্ডের দাম নেই। সেটিংস থেকে দাম যোগ করুন।'))
                else
                  ..._prices.map(_priceRow),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, keyboardOpen ? 10 : 18, 20, keyboardOpen ? 10 : 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                    color: AppColors.cobalt.o(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -6)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: keyboardOpen
                  ? Row(
                      children: [
                        Expanded(
                          child: Text('নেট: ${taka(net)}',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.cobalt)),
                        ),
                        ElevatedButton(
                            onPressed: _saving ? null : _submit,
                            child: const Text('নিশ্চিত করুন')),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sumRow('মোট মূল্য ($_pieces পিস)', taka(total)),
                        const SizedBox(height: 6),
                        _sumRow('কমিশন (${_rate.toStringAsFixed(1)}%)',
                            '- ${taka(discount)}',
                            valueColor: AppColors.sky),
                        const Divider(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('নেট প্রদেয়',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.bold)),
                            Text(taka(net),
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.cobalt)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _submit,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                                _saving ? 'সংরক্ষণ হচ্ছে...' : 'বিক্রয় নিশ্চিত করুন'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String k, String v, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: AppColors.muted)),
        Text(v,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------
enum HistoryRange { all, today, week, month }

class HistoryScreen extends StatefulWidget {
  final bool active;
  const HistoryScreen({super.key, this.active = true});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SaleRecord> _all = [];
  final TextEditingController _search = TextEditingController();
  HistoryRange _range = HistoryRange.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    AppPrefs.dataVersion.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    AppPrefs.dataVersion.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final h = p.history();
    if (!mounted) return;
    setState(() {
      _all = h;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await AppPrefs.pullNow();
    await _load();
  }

  List<SaleRecord> get _filtered {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final q = _search.text.trim().toLowerCase();
    return _all.where((s) {
      if (q.isNotEmpty &&
          !s.invoiceNumber.toLowerCase().contains(q) &&
          !s.retailerName.toLowerCase().contains(q)) {
        return false;
      }
      if (_range == HistoryRange.all) return true;
      final dt = parseSaleDate(s.date);
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(day).inDays;
      switch (_range) {
        case HistoryRange.today:
          return diff == 0;
        case HistoryRange.week:
          return diff >= 0 && diff < 7;
        case HistoryRange.month:
          return dt.year == now.year && dt.month == now.month;
        case HistoryRange.all:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final total = list.fold<double>(0, (a, s) => a + s.cashAmount);
    const labels = {
      HistoryRange.all: 'সব',
      HistoryRange.today: 'আজ',
      HistoryRange.week: '৭ দিন',
      HistoryRange.month: 'এই মাস',
    };

    return Scaffold(
      body: Column(
        children: [
          const ModernHeader(title: 'বিক্রয়ের ইতিহাস', subtitle: 'সমস্ত রেকর্ড'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'ইনভয়েস বা ডিলারের নাম দিয়ে খুঁজুন...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _search.clear),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: HistoryRange.values
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(labels[r]!),
                          selected: _range == r,
                          onSelected: (_) => setState(() => _range = r),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Row(
              children: [
                Text('${list.length} টি ইনভয়েস',
                    style: const TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('মোট নেট: ${taka(total)}',
                    style: const TextStyle(
                        color: AppColors.cobalt, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 300,
                                child: EmptyState(
                                  icon: Icons.history_edu,
                                  text: _all.isEmpty
                                      ? 'এখনও কোনো বিক্রয় রেকর্ড নেই'
                                      : 'কোনো ইনভয়েস পাওয়া যায়নি',
                                  hint: _all.isEmpty
                                      ? '"নতুন বিক্রয়" ট্যাব থেকে প্রথম বিক্রয় যোগ করুন'
                                      : 'ফিল্টার বা সার্চ বদলে দেখুন',
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final sale = list[index];
                              return AppCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => InvoiceDialog(sale: sale)),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                          color: AppColors.bg,
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: const Icon(
                                          Icons.receipt_long_rounded,
                                          color: AppColors.cobalt),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(sale.retailerName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text('#${sale.invoiceNumber} • ${sale.date}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(taka(sale.cashAmount),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                                color: AppColors.cobalt)),
                                        Text('${sale.totalPieces} পিস',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.muted)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoice dialog
// ---------------------------------------------------------------------------
class InvoiceDialog extends StatefulWidget {
  final SaleRecord sale;
  const InvoiceDialog({super.key, required this.sale});
  @override
  State<InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<InvoiceDialog> {
  String _companyName = '';
  String _companyPhone = '';
  String? _logo;

  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
  }

  Future<void> _loadCompanyInfo() async {
    final p = await AppPrefs.getInstance();
    if (!mounted) return;
    setState(() {
      final n = p.getString(AppConfig.companyName);
      _companyName = (n == null || n.trim().isEmpty) ? 'WiFi Zone Manager' : n;
      _companyPhone = p.getString(AppConfig.companyPhone) ?? '';
      _logo = p.getString(AppConfig.companyLogo);
    });
  }

  String get _shareText {
    final s = widget.sale;
    final lines = s.items.entries
        .map((e) => '${e.key} Tk x ${e.value} = ${(int.tryParse(e.key) ?? 0) * e.value}')
        .join('\n');
    return '🧾 *ইনভয়েস: ${s.invoiceNumber}*\n'
        '$_companyName\n$_companyPhone\n'
        '------------------------\n'
        'তারিখ: ${s.date}\nডিলার: ${s.retailerName}\n'
        '------------------------\n'
        '$lines\n'
        '------------------------\n'
        'মোট মূল্য: ${s.grandTotal.toStringAsFixed(0)} Tk\n'
        'কমিশন: -${s.discountAmount.toStringAsFixed(0)} Tk\n'
        '*প্রদেয়: ${s.cashAmount.toStringAsFixed(0)} Tk*';
  }

  Widget _row(String k, String v,
      {bool bold = false, double size = 14, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(v,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final logo = _logoImage(_logo);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          if (logo != null)
            CircleAvatar(
                backgroundImage: logo,
                radius: 26,
                backgroundColor: Colors.transparent),
          const SizedBox(height: 6),
          Text(_companyName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppColors.cobalt)),
          if (_companyPhone.isNotEmpty)
            Text(_companyPhone,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text('ইনভয়েস #${s.invoiceNumber}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(s.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            _row('ডিলার', s.retailerName, bold: true),
            if (s.retailerPhone.isNotEmpty) _row('ফোন', s.retailerPhone),
            const Divider(),
            ...s.items.entries.map((e) => _row(
                '${e.key} Tk × ${e.value}', '${(int.tryParse(e.key) ?? 0) * e.value}')),
            const Divider(),
            _row('মোট মূল্য', s.grandTotal.toStringAsFixed(0)),
            _row('কমিশন (${s.discountRate.toStringAsFixed(1)}%)',
                '-${s.discountAmount.toStringAsFixed(0)}',
                color: AppColors.sky),
            const Divider(),
            _row('প্রদেয়', '${s.cashAmount.toStringAsFixed(0)} Tk',
                bold: true, size: 18, color: AppColors.cobalt),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বন্ধ করুন')),
        ElevatedButton.icon(
          onPressed: () => Share.share(_shareText),
          icon: const Icon(Icons.share, size: 16),
          label: const Text('শেয়ার'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<int> _prices = [];
  Uint8List? _logoBytes;
  bool _logoRemoved = false;
  bool _dirty = false;
  bool _busy = false;
  int _cloudBytes = 0;
  final _companyNameCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _companyPhoneCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final p = await AppPrefs.getInstance();
    if (!mounted) return;
    setState(() {
      _companyNameCtrl.text = p.getString(AppConfig.companyName) ?? '';
      _companyPhoneCtrl.text = p.getString(AppConfig.companyPhone) ?? '';
      final rate = p.getDouble(AppConfig.commissionRate) ?? 10.0;
      _commissionCtrl.text =
          rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';
      _prices = p.cardPrices();
      _cloudBytes = p.estimatedCloudBytes();
      final encoded = p.getString(AppConfig.companyLogo);
      if (encoded != null && encoded.isNotEmpty) {
        try {
          _logoBytes = base64Decode(encoded);
        } catch (_) {}
      }
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      // ছোট করে নিই, নাহলে base64 লোগো ক্লাউড ডকুমেন্ট ভারী করে দেয়
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 80,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _logoBytes = bytes;
        _logoRemoved = false;
        _dirty = true;
      });
    } catch (e) {
      if (mounted) showMsg(context, 'ছবি নেওয়া যায়নি: $e', error: true);
    }
  }

  Future<void> _save() async {
    final rate = double.tryParse(_commissionCtrl.text.trim());
    if (rate == null || rate < 0 || rate > 100) {
      showMsg(context, 'কমিশন ০ থেকে ১০০ এর মধ্যে হতে হবে', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await AppPrefs.getInstance();
      await p.setString(AppConfig.companyName, _companyNameCtrl.text.trim());
      await p.setString(AppConfig.companyPhone, _companyPhoneCtrl.text.trim());
      await p.setDouble(AppConfig.commissionRate, rate);
      await p.saveCardPrices(_prices);
      if (_logoRemoved) {
        await p.remove(AppConfig.companyLogo);
      } else if (_logoBytes != null) {
        await p.setString(AppConfig.companyLogo, base64Encode(_logoBytes!));
      }
      if (!mounted) return;
      _dirty = false;
      showMsg(context, 'সফলভাবে সংরক্ষণ করা হয়েছে');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, 'সংরক্ষণ করা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPriceDialog() async {
    final ctrl = TextEditingController();
    String? err;
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('কার্ডের দাম যোগ করুন',
              style: TextStyle(color: AppColors.cobalt)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'দাম লিখুন (Tk)',
              prefixIcon: const Icon(Icons.attach_money),
              errorText: err,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim());
                if (v == null || v <= 0) {
                  setSt(() => err = 'সঠিক দাম লিখুন');
                  return;
                }
                if (_prices.contains(v)) {
                  setSt(() => err = 'এই দাম আগেই আছে');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('যোগ করুন'),
            ),
          ],
        ),
      ),
    );
    if (value != null) {
      setState(() {
        _prices
          ..add(value)
          ..sort();
        _dirty = true;
      });
    }
  }

  Future<void> _removePrice(int price) async {
    final ok = await confirmDialog(
      context,
      title: '$price Tk মুছবেন?',
      message: 'এই কার্ডটি বিক্রয় তালিকা ও ড্যাশবোর্ড থেকে সরে যাবে। '
          'পুরনো ইনভয়েস অক্ষত থাকবে। ("সংরক্ষণ করুন" চাপলে কার্যকর হবে)',
      yes: 'মুছুন',
      danger: true,
    );
    if (!ok) return;
    setState(() {
      _prices.remove(price);
      _dirty = true;
    });
  }

  Future<void> _backupData() async {
    try {
      final p = await AppPrefs.getInstance();
      final data = <String, dynamic>{
        'backupMarker': 'WifiZoneManagerBackup',
        'backupVersion': 1,
        'companyName': p.getString(AppConfig.companyName),
        'companyPhone': p.getString(AppConfig.companyPhone),
        'commissionRate': p.getDouble(AppConfig.commissionRate),
        'invoiceCounter': p.getInt(AppConfig.invoiceCounter),
        'savedCardPrices': p.getStringList(AppConfig.savedCardPrices),
        'cardStock': p.getString(AppConfig.cardStock),
        'salesHistory': p.getString(AppConfig.salesHistory),
        'wifiZones': p.getString(AppConfig.wifiZones),
        'companyLogoBase64': p.getString(AppConfig.companyLogo),
      };
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
        name: 'wifi_zone_backup_$timestamp.json',
        mimeType: 'application/json',
      );
      await Share.shareXFiles([file],
          text: 'WiFi Zone Manager Backup - $timestamp');
      if (mounted) showMsg(context, 'ব্যাকআপ ফাইল তৈরি হয়েছে');
    } catch (e) {
      if (mounted) showMsg(context, 'ব্যাকআপ নিতে সমস্যা: $e', error: true);
    }
  }

  Future<void> _restoreData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) throw 'ব্যাকআপ ফাইল পড়া যাচ্ছে না।';
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['backupMarker'] != 'WifiZoneManagerBackup') {
        throw 'অবৈধ ব্যাকআপ ফাইল।';
      }
      final Map data = decoded;
      if ((data['backupVersion'] as num?)?.toInt() != 1) {
        throw 'ব্যাকআপ সংস্করণ অসামঞ্জস্যপূর্ণ।';
      }
      // কিছু লেখার আগেই JSON ফিল্ডগুলো যাচাই
      for (final f in ['cardStock', 'salesHistory', 'wifiZones']) {
        final v = data[f];
        if (v is String) jsonDecode(v);
      }
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'রিস্টোর নিশ্চিতকরণ',
        message: 'এটি বর্তমান সকল ডেটা (সব ডিভাইসের) ওভাররাইট করবে। চালিয়ে যাবেন?',
        danger: true,
      );
      if (!ok) return;
      setState(() => _busy = true);
      final p = await AppPrefs.getInstance();

      Future<void> str(String key, String field) async {
        if (!data.containsKey(field)) return;
        final v = data[field];
        if (v is String && v.isNotEmpty) {
          await p.setString(key, v);
        } else {
          await p.remove(key);
        }
      }

      await str(AppConfig.companyName, 'companyName');
      await str(AppConfig.companyPhone, 'companyPhone');
      await str(AppConfig.cardStock, 'cardStock');
      await str(AppConfig.salesHistory, 'salesHistory');
      await str(AppConfig.wifiZones, 'wifiZones');
      await str(AppConfig.companyLogo, 'companyLogoBase64');
      if (data['commissionRate'] is num) {
        await p.setDouble(
            AppConfig.commissionRate, (data['commissionRate'] as num).toDouble());
      }
      if (data['invoiceCounter'] is num) {
        await p.setInt(
            AppConfig.invoiceCounter, (data['invoiceCounter'] as num).toInt());
      }
      if (data['savedCardPrices'] is List) {
        await p.setStringList(AppConfig.savedCardPrices,
            (data['savedCardPrices'] as List).map((e) => e.toString()).toList());
      }
      AppPrefs.dataVersion.value++;
      if (!mounted) return;
      _dirty = false;
      showMsg(context, 'ডেটা সফলভাবে রিস্টোর হয়েছে');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, 'রিস্টোরে সমস্যা: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final ok = await AppPrefs.pullNow();
    final p = await AppPrefs.getInstance();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cloudBytes = p.estimatedCloudBytes();
    });
    showMsg(context, ok ? 'ক্লাউড থেকে সিঙ্ক সম্পন্ন' : 'সিঙ্ক করা যায়নি — ইন্টারনেট দেখুন',
        error: !ok);
  }

  Future<void> _pushAll() async {
    final ok = await confirmDialog(
      context,
      title: 'লোকাল ডেটা ক্লাউডে পাঠাবেন?',
      message: 'এই ফোনের ডেটা ক্লাউডে গিয়ে অন্য ডিভাইসের একই ডেটা ওভাররাইট করবে।',
      yes: 'পাঠান',
    );
    if (!ok) return;
    setState(() => _busy = true);
    final p = await AppPrefs.getInstance();
    final done = await p.pushAll();
    if (!mounted) return;
    setState(() => _busy = false);
    showMsg(context, done ? 'ক্লাউডে পাঠানো হয়েছে' : 'পাঠানো যায়নি — ইন্টারনেট দেখুন',
        error: !done);
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context,
        title: 'লগআউট করবেন?', message: 'আপনাকে আবার লগইন করতে হবে।', yes: 'লগআউট');
    if (!ok) return;
    await AppPrefs.stopListener();
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pop(context);
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.cobalt, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.cobalt)),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kb = _cloudBytes / 1024;
    final ratio = (_cloudBytes / (1024 * 1024)).clamp(0.0, 1.0);
    final hasLogo = _logoBytes != null && !_logoRemoved;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmDialog(
          context,
          title: 'সংরক্ষণ না করেই বের হবেন?',
          message: 'আপনার পরিবর্তনগুলো সংরক্ষিত হয়নি।',
          yes: 'বের হন',
          no: 'থাকুন',
          danger: true,
        );
        if (leave && mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('সেটিংস')),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard('কোম্পানির তথ্য', Icons.business_rounded, [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: AppColors.paleSky,
                            backgroundImage: hasLogo ? MemoryImage(_logoBytes!) : null,
                            child: hasLogo
                                ? null
                                : const Icon(Icons.add_a_photo,
                                    size: 34, color: AppColors.cobalt),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 15,
                              backgroundColor: AppColors.cobalt,
                              child: const Icon(Icons.edit,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: hasLogo
                        ? TextButton(
                            onPressed: () => setState(() {
                              _logoRemoved = true;
                              _dirty = true;
                            }),
                            child: const Text('লোগো সরান'),
                          )
                        : const Text('লোগো যোগ করতে ট্যাপ করুন',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _companyNameCtrl,
                    onChanged: (_) => _markDirty(),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'কোম্পানির নাম', prefixIcon: Icon(Icons.store)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _companyPhoneCtrl,
                    onChanged: (_) => _markDirty(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'ফোন', prefixIcon: Icon(Icons.phone)),
                  ),
                ]),
                _sectionCard('কনফিগারেশন', Icons.tune_rounded, [
                  TextField(
                    controller: _commissionCtrl,
                    onChanged: (_) => _markDirty(),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'কমিশন %', prefixIcon: Icon(Icons.percent)),
                  ),
                  const SizedBox(height: 18),
                  const Text('কার্ডের দাম',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ..._prices.map((p) => InputChip(
                            label: Text('$p Tk',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.cobalt)),
                            avatar: const Icon(Icons.credit_card,
                                size: 16, color: AppColors.cobalt),
                            backgroundColor: AppColors.paleSky.o(0.5),
                            onDeleted: () => _removePrice(p),
                          )),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('দাম যোগ'),
                        onPressed: _addPriceDialog,
                      ),
                    ],
                  ),
                  if (_prices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('কোনো কার্ডের দাম যোগ করা হয়নি',
                          style: TextStyle(color: Colors.grey)),
                    ),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('সংরক্ষণ করুন'),
                  ),
                ),
                const SizedBox(height: 16),
                _sectionCard('ক্লাউড সিঙ্ক', Icons.cloud_sync_outlined, [
                  Row(children: [
                    const SyncBadgeDark(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ক্লাউড ডেটা: ${kb.toStringAsFixed(0)} KB / 1024 KB',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio.toDouble(),
                      minHeight: 8,
                      backgroundColor: AppColors.paleSky,
                      color: ratio > 0.7 ? AppColors.danger : AppColors.cobalt,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _syncNow,
                        icon: const Icon(Icons.cloud_download_outlined, size: 18),
                        label: const Text('এখনই সিঙ্ক'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pushAll,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('ক্লাউডে পাঠান'),
                      ),
                    ),
                  ]),
                ]),
                _sectionCard('ব্যাকআপ ও রিস্টোর', Icons.backup_outlined, [
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _backupData,
                        icon: const Icon(Icons.backup, size: 18),
                        label: const Text('ব্যাকআপ'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _restoreData,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('রিস্টোর'),
                      ),
                    ),
                  ]),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _logout,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(color: AppColors.danger.o(0.5))),
                    icon: const Icon(Icons.logout),
                    label: const Text('Admin logout'),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.cobalt, AppColors.sky],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.cobalt.o(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.navy,
                        child: Icon(Icons.code_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 10),
                      const Text('Developed by',
                          style: TextStyle(fontSize: 12, color: AppColors.paleSky)),
                      const Text('Md. Asaduzzaman',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone, size: 15, color: AppColors.paleSky),
                          SizedBox(width: 6),
                          Text('+8801770033448',
                              style: TextStyle(fontSize: 13, color: AppColors.paleSky)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.email_outlined, size: 15, color: AppColors.paleSky),
                          SizedBox(width: 6),
                          Text('asadacn@gmail.com',
                              style: TextStyle(fontSize: 13, color: AppColors.paleSky)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.white.o(0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('Version 1.1.0',
                            style: TextStyle(
                                fontSize: 12, color: Colors.white.o(0.85))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.o(0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// হালকা ব্যাকগ্রাউন্ডের জন্য SyncBadge (সেটিংস স্ক্রিনে)
class SyncBadgeDark extends StatelessWidget {
  const SyncBadgeDark({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppPrefs.syncError, AppPrefs.syncPending]),
      builder: (context, _) {
        IconData icon = Icons.cloud_done_outlined;
        Color color = AppColors.success;
        if (!AppPrefs.cloudReady || AppPrefs.syncError.value != null) {
          icon = Icons.sync_problem_outlined;
          color = AppColors.danger;
        } else if (AppPrefs.syncPending.value) {
          icon = Icons.cloud_upload_outlined;
          color = AppColors.warn;
        }
        return Icon(icon, color: color, size: 22);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// WiFi zones
// ---------------------------------------------------------------------------
class WifiZoneScreen extends StatefulWidget {
  final bool active;
  const WifiZoneScreen({super.key, this.active = true});
  @override
  State<WifiZoneScreen> createState() => _WifiZoneScreenState();
}

class _WifiZoneScreenState extends State<WifiZoneScreen> {
  List<WifiZone> _all = [];
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  String _statusFilter = 'All';
  bool _sortNearest = false;
  Position? _position;
  StreamSubscription<Position>? _positionSub;
  bool _locationStarted = false;
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    AppPrefs.dataVersion.addListener(_load);
    _load();
    if (widget.active) _initLocationStream();
  }

  @override
  void didUpdateWidget(WifiZoneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _load();
      _initLocationStream();
    }
  }

  @override
  void dispose() {
    AppPrefs.dataVersion.removeListener(_load);
    _positionSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _initLocationStream() async {
    if (_locationStarted) return;
    _locationStarted = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationNote = 'লোকেশন সার্ভিস বন্ধ — দূরত্ব দেখানো যাচ্ছে না');
        _locationStarted = false;
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationNote = 'লোকেশন পারমিশন নেই — দূরত্ব দেখানো যাচ্ছে না');
        return;
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 25),
      ).listen(
        (pos) {
          if (mounted) setState(() {
            _position = pos;
            _locationNote = null;
          });
        },
        onError: (Object e) {
          debugPrint('Location stream error: $e');
        },
      );
    } catch (e) {
      _locationStarted = false;
      debugPrint('Location init failed: $e');
    }
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final z = p.zones();
    if (!mounted) return;
    setState(() {
      _all = z;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await AppPrefs.pullNow();
    await _load();
  }

  double? _distanceOf(WifiZone zone) {
    final pos = _position;
    if (pos == null) return null;
    final pts = parseGps(zone.gps);
    if (pts == null) return null;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, pts[0], pts[1]);
  }

  List<WifiZone> get _filtered {
    final q = _search.text.trim().toLowerCase();
    var list = _all.where((z) {
      if (_statusFilter != 'All' && z.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return z.zoneId.toLowerCase().contains(q) ||
          z.title.toLowerCase().contains(q) ||
          z.address.toLowerCase().contains(q) ||
          z.onuMac.toLowerCase().contains(q);
    }).toList();
    if (_sortNearest && _position != null) {
      list.sort((a, b) {
        final da = _distanceOf(a);
        final db = _distanceOf(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }
    return list;
  }

  Future<void> _addEditZone({WifiZone? zone}) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ZoneEntryScreen(zone: zone)));
    if (mounted) _load(); // সেভ ZoneEntryScreen নিজেই করে
  }

  Future<void> _deleteZone(WifiZone zone) async {
    final ok = await confirmDialog(
      context,
      title: 'জোন মুছবেন?',
      message: '"${zone.title}" স্থায়ীভাবে মুছে যাবে।',
      yes: 'মুছুন',
      danger: true,
    );
    if (!ok) return;
    final p = await AppPrefs.getInstance();
    final latest = p.zones()..removeWhere((z) => z.id == zone.id);
    await p.saveZones(latest);
    if (!mounted) return;
    await _load();
    if (mounted) showMsg(context, 'জোনটি মুছে ফেলা হয়েছে');
  }

  void _shareZone(WifiZone zone) {
    final pts = parseGps(zone.gps);
    final link = pts == null
        ? 'N/A'
        : 'https://www.google.com/maps/search/?api=1&query=${pts[0]},${pts[1]}';
    Share.share(
      '🚀 WiFi Zone Details 🚀\n'
      '------------------------------------\n'
      'Title: ${zone.title}\n'
      'Zone ID: ${zone.zoneId}\n'
      'ONU MAC: ${zone.onuMac}\n'
      'Device Type: ${zone.deviceType}\n'
      'Status: ${zone.status}\n'
      'Address: ${zone.address}\n'
      'GPS: ${zone.gps}\n'
      'Map Link: $link\n',
      subject: 'WiFi Zone: ${zone.title}',
    );
  }

  Future<void> _openMap(WifiZone zone) async {
    final pts = parseGps(zone.gps);
    if (pts == null) {
      showMsg(context, 'GPS কো-অর্ডিনেট সেট করা নেই', error: true);
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pts[0]},${pts[1]}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showMsg(context, 'ম্যাপ খোলা যাচ্ছে না। লোকেশন: ${zone.gps}', error: true);
      }
    } catch (_) {
      if (mounted) {
        showMsg(context, 'ম্যাপ খোলা যাচ্ছে না। লোকেশন: ${zone.gps}', error: true);
      }
    }
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMsg(context, '$label কপি হয়েছে');
  }

  Color _statusColor(String s) => s == 'Active'
      ? AppColors.success
      : (s == 'Pending' ? AppColors.warn : AppColors.danger);

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    int count(String s) => s == 'All' ? _all.length : _all.where((z) => z.status == s).length;

    return Scaffold(
      body: Column(
        children: [
          const ModernHeader(
              title: 'ওয়াইফাই জোন', subtitle: 'জোন এন্ট্রি, সার্চ ও ম্যাপ ভিউ'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'জোন ID, নাম, ঠিকানা বা MAC দিয়ে খুঁজুন...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close), onPressed: _search.clear),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final s in const ['All', 'Active', 'Pending', 'Inactive'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${s == 'All' ? 'সব' : s} (${count(s)})'),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() => _statusFilter = s),
                    ),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.near_me, size: 16),
                  label: const Text('কাছের আগে'),
                  selected: _sortNearest,
                  onSelected: (v) {
                    if (_position == null) {
                      showMsg(context,
                          _locationNote ?? 'লোকেশন পাওয়া যাচ্ছে না, একটু অপেক্ষা করুন',
                          error: true);
                      _initLocationStream();
                      return;
                    }
                    setState(() => _sortNearest = v);
                  },
                ),
              ],
            ),
          ),
          if (_locationNote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
              child: Row(children: [
                const Icon(Icons.location_off_outlined,
                    size: 14, color: AppColors.warn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_locationNote!,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              ]),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 300,
                                child: EmptyState(
                                  icon: Icons.router_rounded,
                                  text: _all.isEmpty
                                      ? 'কোনো জোন যোগ করা হয়নি'
                                      : 'কোনো জোন খুঁজে পাওয়া যায়নি',
                                  hint: _all.isEmpty
                                      ? 'নিচের বাটন থেকে প্রথম জোন যোগ করুন'
                                      : 'সার্চ বা ফিল্টার বদলে দেখুন',
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final zone = list[index];
                              final color = _statusColor(zone.status);
                              final dist = _distanceOf(zone);
                              return AppCard(
                                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                                onTap: () => _addEditZone(zone: zone),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                          color: color.o(0.12),
                                          borderRadius: BorderRadius.circular(12)),
                                      child: Icon(Icons.wifi_rounded, color: color),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(zone.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text('ID: ${zone.zoneId}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted)),
                                          if (zone.address.isNotEmpty)
                                            Text(zone.address,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.muted)),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              _tag(zone.status, color),
                                              if (zone.deviceType.isNotEmpty)
                                                _tag(zone.deviceType, AppColors.cobalt),
                                              if (dist != null)
                                                _tag(formatDistance(dist), AppColors.sky,
                                                    icon: Icons.near_me),
                                              if (zone.gps.isEmpty)
                                                _tag('GPS নেই', Colors.grey,
                                                    icon: Icons.location_off),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      onSelected: (v) {
                                        switch (v) {
                                          case 'map':
                                            _openMap(zone);
                                            break;
                                          case 'share':
                                            _shareZone(zone);
                                            break;
                                          case 'mac':
                                            _copy('ONU MAC', zone.onuMac);
                                            break;
                                          case 'edit':
                                            _addEditZone(zone: zone);
                                            break;
                                          case 'delete':
                                            _deleteZone(zone);
                                            break;
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'map',
                                          enabled: zone.gps.isNotEmpty,
                                          child: const ListTile(
                                              dense: true,
                                              leading: Icon(Icons.map_outlined),
                                              title: Text('ম্যাপে দেখুন')),
                                        ),
                                        const PopupMenuItem(
                                          value: 'share',
                                          child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.share_outlined),
                                              title: Text('শেয়ার করুন')),
                                        ),
                                        PopupMenuItem(
                                          value: 'mac',
                                          enabled: zone.onuMac.isNotEmpty,
                                          child: const ListTile(
                                              dense: true,
                                              leading: Icon(Icons.copy_rounded),
                                              title: Text('ONU MAC কপি')),
                                        ),
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.edit_outlined),
                                              title: Text('এডিট করুন')),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.delete_outline,
                                                  color: AppColors.danger),
                                              title: Text('মুছে ফেলুন',
                                                  style: TextStyle(
                                                      color: AppColors.danger))),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEditZone(),
        icon: const Icon(Icons.add),
        label: const Text('নতুন জোন'),
        backgroundColor: AppColors.cobalt,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _tag(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.o(0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zone entry / edit
// ---------------------------------------------------------------------------
class ZoneEntryScreen extends StatefulWidget {
  final WifiZone? zone;
  const ZoneEntryScreen({super.key, this.zone});
  @override
  State<ZoneEntryScreen> createState() => _ZoneEntryScreenState();
}

class _ZoneEntryScreenState extends State<ZoneEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _zoneIdController;
  late final TextEditingController _titleController;
  late final TextEditingController _addressController;
  late final TextEditingController _onuMacController;
  late final TextEditingController _deviceTypeController;
  late final TextEditingController _gpsController;
  late String _status;
  bool _fetchingLocation = false;
  bool _saving = false;
  List<WifiZone> _existing = [];

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    _zoneIdController = TextEditingController(text: z?.zoneId ?? '');
    _titleController = TextEditingController(text: z?.title ?? '');
    _addressController = TextEditingController(text: z?.address ?? '');
    _onuMacController = TextEditingController(text: z?.onuMac ?? '');
    _deviceTypeController = TextEditingController(text: z?.deviceType ?? '');
    _gpsController = TextEditingController(text: z?.gps ?? '');
    _status = z?.status ?? 'Active';
    if (!['Active', 'Pending', 'Inactive'].contains(_status)) _status = 'Active';
    AppPrefs.getInstance().then((p) => _existing = p.zones());
  }

  @override
  void dispose() {
    _zoneIdController.dispose();
    _titleController.dispose();
    _addressController.dispose();
    _onuMacController.dispose();
    _deviceTypeController.dispose();
    _gpsController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) showMsg(context, 'লোকেশন সার্ভিস বন্ধ আছে। এটি চালু করুন।', error: true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) showMsg(context, 'লোকেশন পারমিশন দেওয়া হয়নি।', error: true);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      _gpsController.text =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      if (mounted) showMsg(context, 'লোকেশন সফলভাবে যুক্ত হয়েছে');
    } catch (e) {
      if (mounted) {
        showMsg(context, 'লোকেশন পাওয়া যায়নি। খোলা জায়গায় গিয়ে আবার চেষ্টা করুন।',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _saveZone() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final p = await AppPrefs.getInstance();
      final zones = p.zones(); // সর্বশেষ ডেটা
      final gps = _gpsController.text.trim();
      if (widget.zone != null) {
        final i = zones.indexWhere((z) => z.id == widget.zone!.id);
        if (i != -1) {
          zones[i]
            ..zoneId = _zoneIdController.text.trim()
            ..title = _titleController.text.trim()
            ..address = _addressController.text.trim()
            ..onuMac = _onuMacController.text.trim()
            ..deviceType = _deviceTypeController.text.trim()
            ..gps = gps
            ..status = _status;
        } else {
          zones.add(WifiZone(
            id: widget.zone!.id,
            zoneId: _zoneIdController.text.trim(),
            title: _titleController.text.trim(),
            address: _addressController.text.trim(),
            onuMac: _onuMacController.text.trim(),
            deviceType: _deviceTypeController.text.trim(),
            gps: gps,
            status: _status,
          ));
        }
      } else {
        zones.add(WifiZone(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          zoneId: _zoneIdController.text.trim(),
          title: _titleController.text.trim(),
          address: _addressController.text.trim(),
          onuMac: _onuMacController.text.trim(),
          deviceType: _deviceTypeController.text.trim(),
          gps: gps,
          status: _status,
        ));
      }
      await p.saveZones(zones);
      if (!mounted) return;
      showMsg(context, widget.zone != null ? 'জোন আপডেট হয়েছে' : 'নতুন জোন যুক্ত হয়েছে');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMsg(context, 'সংরক্ষণ করা যায়নি: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.zone != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'জোন এডিট করুন' : 'নতুন জোন যোগ করুন')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _zoneIdController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'জোন আইডি *', prefixIcon: Icon(Icons.vpn_key)),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'জোন আইডি আবশ্যক';
                  final dup = _existing.any((z) =>
                      z.zoneId.toLowerCase() == t.toLowerCase() &&
                      z.id != widget.zone?.id);
                  return dup ? 'এই জোন আইডি আগেই আছে' : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'টাইটেল/নাম *', prefixIcon: Icon(Icons.tag)),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'নাম আবশ্যক' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _addressController,
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'ঠিকানা', prefixIcon: Icon(Icons.location_on)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _onuMacController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'ONU MAC / Serial', prefixIcon: Icon(Icons.dvr)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _deviceTypeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'ডিভাইস টাইপ', prefixIcon: Icon(Icons.devices)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Router', 'ONU', 'Switch', 'OLT', 'AP']
                    .map((t) => ActionChip(
                          label: Text(t),
                          onPressed: () => setState(() => _deviceTypeController.text = t),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _gpsController,
                readOnly: _fetchingLocation,
                decoration: InputDecoration(
                  labelText: 'GPS কো-অর্ডিনেট (lat, lng)',
                  prefixIcon: const Icon(Icons.gps_fixed),
                  suffixIcon: _fetchingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.my_location, color: AppColors.sky),
                          onPressed: _getCurrentLocation,
                          tooltip: 'বর্তমান লোকেশন নিন',
                        ),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return parseGps(t) == null
                      ? 'সঠিক ফরম্যাট: 23.8103, 90.4125'
                      : null;
                },
              ),
              const SizedBox(height: 20),
              const Text('স্ট্যাটাস',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'Active', label: Text('Active')),
                    ButtonSegment(value: 'Pending', label: Text('Pending')),
                    ButtonSegment(value: 'Inactive', label: Text('Inactive')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveZone,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: Text(editing ? 'আপডেট করুন' : 'সংরক্ষণ করুন'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}