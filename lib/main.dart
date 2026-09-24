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

  // dark mode chrome (কার্ডগুলো ইচ্ছাকৃতভাবে সাদাই রাখা হয়েছে, পড়তে সুবিধার জন্য)
  static const darkBg = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF111A2E);
  static const darkAppBarFg = Color(0xFFE2ECFF);
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
  static const String dealers = 'dealers';
  static const String adminEmails = 'admin_emails';
  static const String stockLog = 'stock_log';
  static const String companyCommission = 'company_commission';
  static const String dealerCommission = 'dealer_commission';
  static const String officePartnerCommission = 'office_partner_commission';
  static const String cardCost = 'card_cost';
  static const String themeMode = 'theme_mode';
  static const String settingsPin = 'settings_pin';

  static const int lowStockLimit = 10;
  static const List<int> defaultPrices = [9, 15, 25, 50, 89, 249];
  static const int maxStockLogEntries = 300;

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
    dealers,
    stockLog,
    adminEmails,
    companyCommission,
    dealerCommission,
    officePartnerCommission,
    cardCost,
    settingsPin,
    // themeMode জেনেবুঝে বাদ: এটা এই ডিভাইসের পছন্দ, ক্লাউডে পাঠানোর দরকার নেই
  ];
}

/// অ্যাপের থিম (লোকাল, ডিভাইস-ভিত্তিক — ক্লাউডে সিঙ্ক হয় না)
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

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

  static const Set<String> _doubleKeys = {
    AppConfig.commissionRate,
    AppConfig.companyCommission,
    AppConfig.dealerCommission,
    AppConfig.officePartnerCommission,
  };
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

  Map<String, double> costPrices() {
    final s = getString(AppConfig.cardCost);
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map;
      return m.map<String, double>(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCostPrices(Map<String, double> costs) =>
      setString(AppConfig.cardCost, jsonEncode(costs));

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

  // ---- dealers -------------------------------------------------------------
  List<Dealer> dealers() {
    final s = getString(AppConfig.dealers);
    if (s == null) return [];
    try {
      final l = jsonDecode(s) as List;
      return l
          .map((e) => Dealer.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDealers(List<Dealer> dealers) => setString(
      AppConfig.dealers, jsonEncode(dealers.map((e) => e.toJson()).toList()));

  /// ডিলার লিস্ট। ফিচার প্রথমবার চালু হলে পুরনো বিক্রয় ইতিহাস থেকে বানিয়ে নেয়।
  /// (নতুন বিক্রয় সেভ করার আগে কল করতে হবে, নাহলে ভিজিট দুইবার গোনা হবে)
  Future<List<Dealer>> ensureDealers() async {
    if (getString(AppConfig.dealers) != null) return dealers();
    final built = buildDealersFromHistory(history());
    if (built.isNotEmpty) await saveDealers(built);
    return built;
  }

  // ---- কমিশন শতাংশ (প্রতি কার্ড সেলে ফ্ল্যাট ভাগ: ডিলার + কোম্পানি + অফিস পার্টনার = ১০০%) -----------
  double companyCommissionPercent() {
    return getDouble(AppConfig.companyCommission) ?? 50.0;
  }

  double dealerCommissionPercent() {
    return getDouble(AppConfig.dealerCommission) ?? 10.0;
  }

  double officePartnerPercent() {
    return getDouble(AppConfig.officePartnerCommission) ?? 40.0;
  }

  Future<void> saveCommissionPercents(
      double company, double dealer, double officePartner) async {
    await setDouble(AppConfig.companyCommission, company);
    await setDouble(AppConfig.dealerCommission, dealer);
    await setDouble(AppConfig.officePartnerCommission, officePartner);
    // বিক্রয় স্ক্রিনের ডিলার ডিসকাউন্ট = ডিলার %
    await setDouble(AppConfig.commissionRate, dealer);
  }

  // ---- সেটিংস পিন (স্টাফদের সেটিংস থেকে দূরে রাখতে) --------------------------
  List<Map<String, dynamic>> stockLog() {
    final s = getString(AppConfig.stockLog);
    if (s == null) return [];
    try {
      final l = jsonDecode(s) as List;
      return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> appendStockLog(
      String price, int delta, String type, int resultingQty) async {
    final log = stockLog();
    log.insert(0, {
      'price': price,
      'delta': delta,
      'type': type, // add | set | sale
      'qty': resultingQty,
      'at': DateTime.now().toIso8601String(),
    });
    if (log.length > AppConfig.maxStockLogEntries) {
      log.removeRange(AppConfig.maxStockLogEntries, log.length);
    }
    await setString(AppConfig.stockLog, jsonEncode(log));
  }

  // ---- নিরাপত্তা (সেটিংস পিন) --------------------------
  String? settingsPin() {
    final p = getString(AppConfig.settingsPin);
    return (p == null || p.isEmpty) ? null : p;
  }

  Future<void> saveSettingsPin(String? pin) async {
    if (pin == null || pin.isEmpty) {
      await remove(AppConfig.settingsPin);
    } else {
      await setString(AppConfig.settingsPin, pin);
    }
  }

  // ---- Admin emails (dashboard এ দেখার জন্য) -----------
  List<String> adminEmails() {
    final s = getString(AppConfig.adminEmails);
    if (s == null || s.isEmpty) return [];
    try {
      final l = jsonDecode(s) as List;
      return l.map((e) => e.toString().trim().toLowerCase()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAdminEmails(List<String> emails) async {
    final normalized = emails.map((e) => e.trim().toLowerCase()).toList();
    await setString(AppConfig.adminEmails, jsonEncode(normalized));
  }

  bool isAdmin(String? email) {
    if (email == null || email.isEmpty) return false;
    return adminEmails().contains(email.trim().toLowerCase());
  }

  // ---- থিম (লোকাল, ক্লাউডে যায় না) ------------------------------------------
  Future<void> saveThemeModeLocal(ThemeMode mode) async {
    await _local.setString(
        AppConfig.themeMode, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  ThemeMode loadThemeModeLocal() {
    final v = _local.getString(AppConfig.themeMode);
    return v == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }
}

/// এই সেলে বিক্রি হওয়া কার্ডের মোট খরচ (cost) বের করে
/// CSV-এর একটা সেল নিরাপদ করে (কমা/উদ্ধৃতি/নতুন লাইন থাকলে quote করে)
String csvCell(Object? v) {
  final s = (v ?? '').toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String buildSalesCsv(List<SaleRecord> history) {
  final rows = <String>[];
  rows.add([
    'Invoice',
    'Date',
    'Dealer',
    'Phone',
    'Items',
    'Pieces',
    'GrandTotal',
    'Commission',
    'NetCash',
  ].map(csvCell).join(','));
  for (final s in history) {
    final itemsText =
        s.items.entries.map((e) => '${e.key}x${e.value}').join(' | ');
    rows.add([
      s.invoiceNumber,
      s.date,
      s.retailerName,
      s.retailerPhone,
      itemsText,
      s.totalPieces,
      s.grandTotal.toStringAsFixed(0),
      s.discountAmount.toStringAsFixed(0),
      s.cashAmount.toStringAsFixed(0),
    ].map(csvCell).join(','));
  }
  return rows.join('\r\n');
}

String buildDealersCsv(List<Dealer> dealers) {
  final rows = <String>[];
  rows.add([
    'Name',
    'Phone',
    'VisitCount',
    'LastVisit',
    'TotalPurchase',
    'AvgPerVisit',
    'GPS',
    'VIP',
  ].map(csvCell).join(','));
  for (final d in dealers) {
    rows.add([
      d.name,
      d.phone,
      d.visitCount,
      d.lastVisitDate == null ? '' : formatVisit(d.lastVisitDate!),
      d.totalPurchase.toStringAsFixed(0),
      d.average.toStringAsFixed(0),
      d.bestGps,
      d.vip ? 'Yes' : 'No',
    ].map(csvCell).join(','));
  }
  return rows.join('\r\n');
}

Future<void> shareCsv(String filename, String csv, String subject) async {
  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode('\uFEFF$csv')), // BOM যোগ, Excel বাংলা ঠিক দেখায়
    name: filename,
    mimeType: 'text/csv',
  );
  await SharePlus.instance.share(ShareParams(files: [file], text: subject));
}

/// পিন যাচাই করে তারপরই সেটিংস স্ক্রিন খোলে (পিন সেট না থাকলে সরাসরি খোলে)
Future<void> openSettingsGated(BuildContext context) async {
  final p = await AppPrefs.getInstance();
  if (!context.mounted) return;
  final allowed = await verifySettingsPin(context, p);
  if (!allowed || !context.mounted) return;
  await Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
}

/// সেটিংসে ঢোকার আগে পিন যাচাই (পিন সেট না থাকলে সরাসরি ঢুকতে দেয়)
Future<bool> verifySettingsPin(BuildContext context, AppPrefs p) async {
  final pin = p.settingsPin();
  if (pin == null) return true;
  final ctrl = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('সেটিংস পিন দিন',
            style: TextStyle(color: AppColors.cobalt)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: 'পিন',
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: err),
          onSubmitted: (_) {
            if (ctrl.text == pin) {
              Navigator.pop(ctx, true);
            } else {
              setSt(() => err = 'ভুল পিন');
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text == pin) {
                Navigator.pop(ctx, true);
              } else {
                setSt(() => err = 'ভুল পিন');
              }
            },
            child: const Text('ঢুকুন'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
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
  // থিম প্রেফারেন্স আগেভাগে লোড করি, যাতে প্রথম ফ্রেমেই সঠিক থিম দেখা যায়
  try {
    final p = await AppPrefs.getInstance();
    appThemeMode.value = p.loadThemeModeLocal();
  } catch (_) {}
  runApp(const WifiCardApp());
}

ThemeData _buildTheme({required bool dark}) {
  final scaffoldBg = dark ? AppColors.darkBg : AppColors.bg;
  final surface = dark ? AppColors.darkSurface : Colors.white;
  final fg = dark ? AppColors.darkAppBarFg : AppColors.cobalt;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: AppColors.sky.o(dark ? 0.25 : 0.3)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cobalt,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.cobalt,
      secondary: AppColors.sky,
      tertiary: AppColors.paleSky,
      surface: dark ? AppColors.darkSurface : AppColors.bg,
      onSurface: dark ? AppColors.darkAppBarFg : AppColors.ink,
    ),
    scaffoldBackgroundColor: scaffoldBg,
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.sky.o(0.2)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: true,
      titleTextStyle:
          TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.cobalt,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        elevation: 2,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.cobalt,
        side: BorderSide(color: AppColors.cobalt.o(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIconColor: AppColors.cobalt,
      labelStyle: TextStyle(color: AppColors.cobalt.o(0.75)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
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
  );
}

class WifiCardApp extends StatelessWidget {
  const WifiCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'WiFi Zone Manager',
          themeMode: mode,
          theme: _buildTheme(dark: false),
          darkTheme: _buildTheme(dark: true),
          home: const AuthGate(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Auth gate
// ---------------------------------------------------------------------------
const double _kPi = 3.141592653589793;

/// WiFi সিগন্যালের মতো একটা একটা করে জ্বলে ওঠা অ্যানিমেশন
class WifiLoader extends StatefulWidget {
  final double size;
  final Color color;
  const WifiLoader({super.key, this.size = 140, this.color = Colors.white});
  @override
  State<WifiLoader> createState() => _WifiLoaderState();
}

class _WifiLoaderState extends State<WifiLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size(widget.size, widget.size * 0.75),
        painter: _WifiPainter(_c.value, widget.color),
      ),
    );
  }
}

class _WifiPainter extends CustomPainter {
  final double progress;
  final Color color;
  _WifiPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.88;
    final maxR = size.height * 0.82;
    final stroke = size.width * 0.055;
    final t = progress * 4.0; // 0..4 : ডট, আর্ক১, আর্ক২, আর্ক৩
    final double fade = progress > 0.85
        ? ((1 - progress) / 0.15).clamp(0.0, 1.0).toDouble()
        : 1.0;

    for (int i = 0; i < 3; i++) {
      final double lit = (t - i).clamp(0.0, 1.0).toDouble() * fade;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.o(0.18 + 0.82 * lit);
      final r = maxR * (0.36 + 0.32 * i);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -3 * _kPi / 4,
        _kPi / 2,
        false,
        paint,
      );
    }
    canvas.drawCircle(Offset(cx, cy), stroke * 0.95, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WifiPainter old) =>
      old.progress != progress || old.color != color;
}

class FirebaseLoadingScreen extends StatefulWidget {
  const FirebaseLoadingScreen({super.key});
  @override
  State<FirebaseLoadingScreen> createState() => _FirebaseLoadingScreenState();
}

class _FirebaseLoadingScreenState extends State<FirebaseLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WifiLoader(size: 150),
                const SizedBox(height: 28),
                const Text(
                  'WiFi Zone Manager',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _dots,
                  builder: (_, _) {
                    final n = (_dots.value * 3).floor() + 1;
                    return Text.rich(
                      TextSpan(
                        text: 'সংযোগ হচ্ছে',
                        children: [
                          for (int i = 0; i < 3; i++)
                            TextSpan(
                              text: '.',
                              style: TextStyle(
                                  color: i < n
                                      ? Colors.white.o(0.8)
                                      : Colors.transparent),
                            ),
                        ],
                      ),
                      style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.o(0.8),
                          fontWeight: FontWeight.w500),
                    );
                  },
                ),
              ],
            ),
          ),
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
    saleDealerRequest.addListener(_onSaleRequest);
  }

  @override
  void dispose() {
    saleDealerRequest.removeListener(_onSaleRequest);
    unawaited(AppPrefs.stopListener());
    super.dispose();
  }

  /// ডিলার স্ক্রিন থেকে "বিক্রয়" চাপলে নতুন বিক্রয় ট্যাবে চলে যায়
  void _onSaleRequest() {
    if (saleDealerRequest.value != null && mounted) {
      setState(() => _index = 2); // নতুন বিক্রয় ট্যাব (মাঝখানে)
    }
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack: ট্যাব বদলালে ফর্মের ডেটা হারাবে না (যেমন অর্ধেক লেখা বিক্রয়)
    // ক্রম: 0 ড্যাশবোর্ড, 1 ডিলার, 2 নতুন বিক্রয় (মাঝখানে), 3 ইতিহাস, 4 জোন
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(active: _index == 0),
          DealerScreen(active: _index == 1),
          SalesEntryScreen(active: _index == 2),
          HistoryScreen(active: _index == 3),
          WifiZoneScreen(active: _index == 4),
        ],
      ),
      bottomNavigationBar: AppBottomBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
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
  double _monthProfit = 0; // অফিস পার্টনারের অংশ (ড্যাশবোর্ড লাভ)
  double _monthGrand = 0;
  double _monthDealerShare = 0;
  double _monthCompanyShare = 0;
  double _monthOfficeShare = 0;
  double _dealerPct = 10.0;
  double _companyPct = 50.0;
  double _officePct = 40.0;
  List<MapEntry<String, double>> _topDealers = [];

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
      _dealerPct = p.dealerCommissionPercent();
      _companyPct = p.companyCommissionPercent();
      _officePct = p.officePartnerPercent();
      _compute(history);
      _stockValue = 0;
      for (final price in _prices) {
        _stockValue += price * (_stock['$price'] ?? 0);
      }
      _loading = false;
    });
  }

  bool _isUserAdmin(String? email) {
    // লগইন করা যেকোনো ব্যবহারকারী ড্যাশবোর্ড দেখতে পারবে।
    // (Firebase Auth-ই অ্যাক্সেস গেট; adminEmails ভবিষ্যতের জন্য সংরক্ষিত)
    return email != null && email.isNotEmpty;
  }

  void _compute(List<SaleRecord> history) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    double t = 0, w = 0, m = 0, mGrand = 0;
    final chart = List<double>.filled(7, 0.0);
    final cards = <String, int>{};
    final dealerTotals = <String, double>{};
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
        mGrand += sale.grandTotal;
        sale.items.forEach((price, qty) {
          cards[price] = (cards[price] ?? 0) + qty;
        });
        final dealer = sale.retailerName.trim();
        if (dealer.isNotEmpty) {
          dealerTotals[dealer] = (dealerTotals[dealer] ?? 0) + sale.cashAmount;
        }
      }
    }
    final ranked = dealerTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _today = t;
    _week = w;
    _month = m;
    _monthGrand = mGrand;
    // প্রতি কার্ড সেলে ফ্ল্যাট ভাগ — সেটিংসের % × এই মাসের মোট বিক্রয়
    _monthDealerShare = mGrand * (_dealerPct / 100);
    _monthCompanyShare = mGrand * (_companyPct / 100);
    _monthOfficeShare = mGrand * (_officePct / 100);
    _monthProfit = _monthOfficeShare;
    _weekData = chart;
    _weekLabels = labels;
    _monthCardSales = cards;
    _topDealers = ranked.take(5).toList();
  }

  Future<void> _refresh() async {
    await AppPrefs.pullNow();
    await _load();
  }

  Future<void> _openSettings() async {
    await openSettingsGated(context);
    if (mounted) _load();
  }

  Future<void> _applyStock(String price, int qty,
      {required bool overwrite}) async {
    final p = await AppPrefs.getInstance();
    final before = p.stock(); // সবসময় সর্বশেষ স্টক থেকে হিসাব
    final prevQty = before[price] ?? 0;
    final newQty = overwrite ? qty : prevQty + qty;
    before[price] = newQty;
    await p.saveStock(before);
    await p.appendStockLog(
        price, overwrite ? (newQty - prevQty) : qty, overwrite ? 'set' : 'add', newQty);
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

  Widget _profitSplitRow(String name, double pct, double amount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$name ${pct.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.o(0.9),
                fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          taka(amount),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white),
        ),
      ],
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
      return const Scaffold(body: Center(child: WifiLoader(size: 96, color: AppColors.cobalt)));
    }
    
    // Admin access check
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !_isUserAdmin(currentUser.email)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: AppColors.cobalt.o(0.5)),
              const SizedBox(height: 16),
              const Text('শুধু অ্যাডমিনরা ড্যাশবোর্ড দেখতে পারেন',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.cobalt)),
              const SizedBox(height: 8),
              Text('আপনার অ্যাকাউন্ট: ${currentUser?.email ?? "unknown"}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      );
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF15803D), AppColors.success],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.success.o(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.trending_up_rounded,
                            color: Colors.white.o(0.85), size: 24),
                        const SizedBox(height: 8),
                        Text(taka(_monthProfit),
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(
                            'অফিস পার্টনার লাভ (${_officePct.toStringAsFixed(0)}%) • এই মাস',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.o(0.85),
                                fontWeight: FontWeight.w600)),
                        if (_monthGrand > 0) ...[
                          const SizedBox(height: 4),
                          Text('মোট বিক্রয় ${taka(_monthGrand)}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.o(0.75))),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.o(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              _profitSplitRow(
                                  'ডিলার',
                                  _dealerPct,
                                  _monthDealerShare),
                              const SizedBox(height: 4),
                              _profitSplitRow(
                                  'কোম্পানি',
                                  _companyPct,
                                  _monthCompanyShare),
                              const SizedBox(height: 4),
                              _profitSplitRow(
                                  'অফিস পার্টনার',
                                  _officePct,
                                  _monthProfit),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  if (_topDealers.isNotEmpty) ...[
                    const SectionTitle('এই মাসের সেরা ৫ ডিলার'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: Column(
                        children: [
                          for (int i = 0; i < _topDealers.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i == 0
                                          ? AppColors.warn.o(0.18)
                                          : AppColors.bg,
                                    ),
                                    child: Text('${i + 1}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                            color: i == 0
                                                ? AppColors.warn
                                                : AppColors.muted)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(_topDealers[i].key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  Text(taka(_topDealers[i].value),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.cobalt)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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
    saleDealerRequest.addListener(_onDealerRequest);
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
    saleDealerRequest.removeListener(_onDealerRequest);
    _name.dispose();
    _phone.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// ডিলার স্ক্রিন থেকে আসা অনুরোধ: নাম/ফোন আগে থেকে বসিয়ে দেয়
  void _onDealerRequest() {
    final d = saleDealerRequest.value;
    if (d == null) return;
    _name.text = d.name;
    _phone.text = d.phone;
    saleDealerRequest.value = null;
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final dealers = await p.ensureDealers();
    dealers.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    if (!mounted) return;
    setState(() {
      _rate = p.dealerCommissionPercent();
      _prices = p.cardPrices();
      _stock = p.stock();
      final seen = <String>{};
      _dealers = [];
      _dealerPhone.clear();
      for (final d in dealers) {
        final n = d.name.trim();
        if (n.isEmpty) continue;
        if (seen.add(n)) {
          _dealers.add(n);
          _dealerPhone[n] = d.phone;
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
      // ডিলারের লোকেশন (না পেলে বিক্রয় আটকায় না)
      final pos = await tryGetPosition();
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
      final rate = p.dealerCommissionPercent();
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
      // নতুন বিক্রয় সেভ করার আগে ডিলার লিস্ট নিতে হবে (ব্যাকফিলে দুইবার গোনা এড়াতে)
      final dealers = await p.ensureDealers();
      upsertDealerVisit(dealers, sale, pos);
      await p.saveStock(latestStock);
      await p.saveHistory(history);
      await p.saveDealers(dealers);
      await p.setInt(AppConfig.invoiceCounter, counter);
      for (final e in sold.entries) {
        await p.appendStockLog(
            e.key, -e.value, 'sale', latestStock[e.key] ?? 0);
      }
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
    await openSettingsGated(context);
    if (mounted) _load();
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
      return const Scaffold(body: Center(child: WifiLoader(size: 96, color: AppColors.cobalt)));
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
            subtitle: 'ডিলার কমিশন: ${_rate.toStringAsFixed(0)}%',
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
                        _sumRow('ডিলার কমিশন (${_rate.toStringAsFixed(0)}%)',
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
                ? const Center(child: WifiLoader(size: 96, color: AppColors.cobalt))
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
          onPressed: () =>
              SharePlus.instance.share(ShareParams(text: _shareText)),
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
  final _companyCommCtrl = TextEditingController();
  final _dealerCommCtrl = TextEditingController();
  final _officeCommCtrl = TextEditingController();
  final Map<int, TextEditingController> _costCtrls = {};
  final _pinCtrl = TextEditingController();
  String? _savedPin;

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
    _companyCommCtrl.dispose();
    _dealerCommCtrl.dispose();
    _officeCommCtrl.dispose();
    _pinCtrl.dispose();
    for (final c in _costCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncCostControllers(Map<String, double> costs) {
    for (final price in _prices) {
      final ctrl = _costCtrls.putIfAbsent(price, () => TextEditingController());
      final c = costs[price.toString()];
      ctrl.text = (c == null || c == 0) ? '' : c.toStringAsFixed(0);
    }
    final stale = _costCtrls.keys.where((k) => !_prices.contains(k)).toList();
    for (final k in stale) {
      _costCtrls.remove(k)?.dispose();
    }
  }

  Future<void> _loadSettings() async {
    final p = await AppPrefs.getInstance();
    final costs = p.costPrices();
    if (!mounted) return;
    setState(() {
      _companyNameCtrl.text = p.getString(AppConfig.companyName) ?? '';
      _companyPhoneCtrl.text = p.getString(AppConfig.companyPhone) ?? '';
      final rate = p.getDouble(AppConfig.commissionRate) ?? 10.0;
      _commissionCtrl.text =
          rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';
      final companyPct = p.companyCommissionPercent();
      final dealerPct = p.dealerCommissionPercent();
      final officePct = p.officePartnerPercent();
      _companyCommCtrl.text = companyPct == companyPct.roundToDouble()
          ? companyPct.toStringAsFixed(0)
          : '$companyPct';
      _dealerCommCtrl.text = dealerPct == dealerPct.roundToDouble()
          ? dealerPct.toStringAsFixed(0)
          : '$dealerPct';
      _officeCommCtrl.text = officePct == officePct.roundToDouble()
          ? officePct.toStringAsFixed(0)
          : '$officePct';
      _commissionCtrl.text = _dealerCommCtrl.text;
      _prices = p.cardPrices();
      _cloudBytes = p.estimatedCloudBytes();
      _savedPin = p.settingsPin();
      _syncCostControllers(costs);
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
    final companyPct = double.tryParse(_companyCommCtrl.text.trim());
    final dealerPct = double.tryParse(_dealerCommCtrl.text.trim());
    final officePct = double.tryParse(_officeCommCtrl.text.trim());
    if (dealerPct == null || dealerPct < 0 || dealerPct > 100) {
      setState(() => _busy = false);
      if (!mounted) return;
      showMsg(context, 'ডিলার % ০–১০০ এর মধ্যে দিন', error: true);
      return;
    }
    if (companyPct == null || companyPct < 0 || companyPct > 100) {
      setState(() => _busy = false);
      if (!mounted) return;
      showMsg(context, 'কোম্পানি % ০–১০০ এর মধ্যে দিন', error: true);
      return;
    }
    if (officePct == null || officePct < 0 || officePct > 100) {
      setState(() => _busy = false);
      if (!mounted) return;
      showMsg(context, 'অফিস পার্টনার % ০–১০০ এর মধ্যে দিন', error: true);
      return;
    }
    final sum = dealerPct + companyPct + officePct;
    if ((sum - 100).abs() > 0.05) {
      setState(() => _busy = false);
      if (!mounted) return;
      showMsg(context,
          'তিনটি % মিলিয়ে ঠিক ১০০ হতে হবে (এখন ${sum.toStringAsFixed(1)})',
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await AppPrefs.getInstance();
      await p.setString(AppConfig.companyName, _companyNameCtrl.text.trim());
      await p.setString(AppConfig.companyPhone, _companyPhoneCtrl.text.trim());
      await p.saveCommissionPercents(companyPct, dealerPct, officePct);
      await p.saveCardPrices(_prices);
      final costs = <String, double>{};
      for (final price in _prices) {
        final v = double.tryParse(_costCtrls[price]?.text.trim() ?? '');
        if (v != null && v > 0) costs[price.toString()] = v;
      }
      await p.saveCostPrices(costs);
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
        _costCtrls[value] = TextEditingController();
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
      _costCtrls.remove(price)?.dispose();
      _dirty = true;
    });
  }

  Future<void> _toggleDarkMode(bool dark) async {
    appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    final p = await AppPrefs.getInstance();
    await p.saveThemeModeLocal(appThemeMode.value);
    if (mounted) setState(() {});
  }

  Future<void> _exportSalesCsv() async {
    final p = await AppPrefs.getInstance();
    if (!mounted) return;
    final h = p.history();
    if (h.isEmpty) {
      showMsg(context, 'এক্সপোর্ট করার মতো কোনো বিক্রয় নেই', error: true);
      return;
    }
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await shareCsv('sales_$ts.csv', buildSalesCsv(h), 'বিক্রয়ের রিপোর্ট - $ts');
  }

  Future<void> _exportDealersCsv() async {
    final p = await AppPrefs.getInstance();
    if (!mounted) return;
    final d = await p.ensureDealers();
    if (!mounted) return;
    if (d.isEmpty) {
      showMsg(context, 'এক্সপোর্ট করার মতো কোনো ডিলার নেই', error: true);
      return;
    }
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await shareCsv('dealers_$ts.csv', buildDealersCsv(d), 'ডিলার রিপোর্ট - $ts');
  }

  Future<void> _openStockLog() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const StockLogScreen()));
  }

  Future<void> _savePin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty && pin.length < 4) {
      showMsg(context, 'পিন অন্তত ৪ ডিজিট হতে হবে', error: true);
      return;
    }
    final p = await AppPrefs.getInstance();
    await p.saveSettingsPin(pin.isEmpty ? null : pin);
    if (!mounted) return;
    setState(() {
      _savedPin = pin.isEmpty ? null : pin;
      _pinCtrl.clear();
    });
    showMsg(context, pin.isEmpty ? 'পিন সরানো হয়েছে' : 'পিন সেট করা হয়েছে');
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
        'companyCommission': p.companyCommissionPercent(),
        'dealerCommission': p.dealerCommissionPercent(),
        'officePartnerCommission': p.officePartnerPercent(),
        'invoiceCounter': p.getInt(AppConfig.invoiceCounter),
        'savedCardPrices': p.getStringList(AppConfig.savedCardPrices),
        'cardStock': p.getString(AppConfig.cardStock),
        'salesHistory': p.getString(AppConfig.salesHistory),
        'wifiZones': p.getString(AppConfig.wifiZones),
        'dealers': p.getString(AppConfig.dealers),
        'cardCost': p.getString(AppConfig.cardCost),
        'stockLog': p.getString(AppConfig.stockLog),
        'adminEmails': p.getString(AppConfig.adminEmails),
        'companyLogoBase64': p.getString(AppConfig.companyLogo),
      };
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
        name: 'wifi_zone_backup_$timestamp.json',
        mimeType: 'application/json',
      );
      await SharePlus.instance.share(ShareParams(
        files: [file],
        text: 'WiFi Zone Manager Backup - $timestamp',
      ));
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
      for (final f in ['cardStock', 'salesHistory', 'wifiZones', 'dealers', 'cardCost', 'stockLog', 'adminEmails']) {
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
      if (data.containsKey('dealers')) {
        await str(AppConfig.dealers, 'dealers');
      } else {
        // পুরনো ব্যাকআপ: রিস্টোর করা ইতিহাস থেকে ডিলার নতুন করে তৈরি হবে
        await p.remove(AppConfig.dealers);
      }
      await str(AppConfig.cardCost, 'cardCost');
      await str(AppConfig.stockLog, 'stockLog');
      await str(AppConfig.companyLogo, 'companyLogoBase64');
      if (data['commissionRate'] is num) {
        await p.setDouble(
            AppConfig.commissionRate, (data['commissionRate'] as num).toDouble());
      }
      final companyPct = (data['companyCommission'] as num?)?.toDouble();
      final dealerPct = (data['dealerCommission'] as num?)?.toDouble();
      final officePct = (data['officePartnerCommission'] as num?)?.toDouble();
      if (companyPct != null || dealerPct != null || officePct != null) {
        await p.saveCommissionPercents(
          companyPct ?? 50.0,
          dealerPct ?? 10.0,
          officePct ?? 40.0,
        );
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
        if (leave && context.mounted) {
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
                _sectionCard('পার্টনার ভাগ (প্রতি কার্ড সেল)', Icons.percent_rounded, [
                  const Text(
                    'প্রতি কার্ড বিক্রয়ে মোট মূল্য এই তিন ভাগে ভাগ হবে। তিনটি মিলিয়ে ১০০% হতে হবে।',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dealerCommCtrl,
                    onChanged: (_) => _markDirty(),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'ডিলার %',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        helperText: 'ডিফল্ট ১০ — বিক্রয়ে ডিলারের কমিশন'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _companyCommCtrl,
                    onChanged: (_) => _markDirty(),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'কোম্পানি %',
                        prefixIcon: Icon(Icons.business_outlined),
                        helperText: 'ডিফল্ট ৫০'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _officeCommCtrl,
                    onChanged: (_) => _markDirty(),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'অফিস পার্টনার % (ড্যাশবোর্ড লাভ)',
                        prefixIcon: Icon(Icons.groups_outlined),
                        helperText: 'ডিফল্ট ৪০ — ড্যাশবোর্ডে লাভ হিসেবে দেখাবে'),
                  ),
                ]),
                _sectionCard('কনফিগারেশন', Icons.tune_rounded, [
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
                  if (_prices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('কার্ডের ক্রয়মূল্য (কস্ট) — লাভ হিসাবের জন্য',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text(
                        'খালি রাখলে সেই কার্ডে লাভ ০ ধরা হবে',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 8),
                    ..._prices.map((price) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: _costCtrls[price],
                            onChanged: (_) => _markDirty(),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: '$price Tk কার্ডের ক্রয়মূল্য',
                              prefixIcon: const Icon(Icons.shopping_bag_outlined),
                              suffixText: 'Tk',
                            ),
                          ),
                        )),
                  ],

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
                _sectionCard('অ্যাপের ধরন', Icons.dark_mode_outlined, [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: appThemeMode,
                    builder: (context, mode, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('ডার্ক মোড'),
                      subtitle: const Text('চোখের আরাম, বিশেষত রাতে',
                          style: TextStyle(fontSize: 12)),
                      value: mode == ThemeMode.dark,
                      onChanged: _toggleDarkMode,
                    ),
                  ),
                ]),
                _sectionCard('রিপোর্ট এক্সপোর্ট (CSV)', Icons.table_chart_outlined, [
                  const Text(
                      'Excel/Google Sheets-এ খোলার মতো CSV ফাইল হিসেবে শেয়ার হবে',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportSalesCsv,
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('বিক্রয়'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exportDealersCsv,
                        icon: const Icon(Icons.storefront_outlined, size: 18),
                        label: const Text('ডিলার'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openStockLog,
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('স্টক পরিবর্তনের লগ দেখুন'),
                    ),
                  ),
                ]),
                _sectionCard('নিরাপত্তা (সেটিংস পিন)', Icons.lock_outline, [
                  Text(
                    _savedPin == null
                        ? 'এখন পিন সেট নেই — যে কেউ সেটিংসে ঢুকতে পারবে'
                        : 'পিন চালু আছে — সেটিংসে ঢুকতে পিন লাগবে',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: _savedPin == null
                            ? AppColors.muted
                            : AppColors.success,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: _savedPin == null
                          ? 'নতুন পিন (৪+ ডিজিট)'
                          : 'নতুন পিন — খালি রেখে সংরক্ষণ করলে পিন বন্ধ হবে',
                      prefixIcon: const Icon(Icons.password_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _savePin,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(_savedPin == null ? 'পিন চালু করুন' : 'পিন আপডেট/বন্ধ করুন'),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
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
                  child: const Center(child: WifiLoader(size: 96, color: AppColors.cobalt)),
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
// স্টক পরিবর্তনের লগ (audit trail)
// ---------------------------------------------------------------------------
class StockLogScreen extends StatefulWidget {
  const StockLogScreen({super.key});
  @override
  State<StockLogScreen> createState() => _StockLogScreenState();
}

class _StockLogScreenState extends State<StockLogScreen> {
  List<Map<String, dynamic>> _log = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final l = p.stockLog();
    if (!mounted) return;
    setState(() {
      _log = l;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('স্টক পরিবর্তনের লগ')),
      body: _loading
          ? const Center(child: WifiLoader(size: 96, color: AppColors.cobalt))
          : _log.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  text: 'এখনও কোনো স্টক পরিবর্তন লগ হয়নি',
                  hint: 'ড্যাশবোর্ড থেকে স্টক আপডেট করলে এখানে দেখাবে')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _log.length,
                  itemBuilder: (context, index) {
                    final e = _log[index];
                    final type = (e['type'] ?? '').toString();
                    final price = (e['price'] ?? '').toString();
                    final delta = (e['delta'] as num?)?.toInt() ?? 0;
                    final qty = (e['qty'] as num?)?.toInt() ?? 0;
                    final at = DateTime.tryParse((e['at'] ?? '').toString());
                    IconData icon;
                    Color color;
                    String label;
                    switch (type) {
                      case 'sale':
                        icon = Icons.point_of_sale_rounded;
                        color = AppColors.cobalt;
                        label = 'বিক্রয়';
                        break;
                      case 'set':
                        icon = Icons.edit_rounded;
                        color = AppColors.warn;
                        label = 'সংশোধন';
                        break;
                      default:
                        icon = Icons.add_box_rounded;
                        color = AppColors.success;
                        label = 'যোগ';
                    }
                    return AppCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: color.o(0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(icon, color: color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$price Tk — $label',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    at == null
                                        ? ''
                                        : '${formatVisit(at)} • নতুন স্টক: $qty',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          Text(
                            delta >= 0 ? '+$delta' : '$delta',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: delta >= 0
                                    ? AppColors.success
                                    : AppColors.danger),
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
          if (mounted) {
            setState(() {
              _position = pos;
              _locationNote = null;
            });
          }
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
    SharePlus.instance.share(ShareParams(
      text: '🚀 WiFi Zone Details 🚀\n'
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
    ));
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
                ? const Center(child: WifiLoader(size: 96, color: AppColors.cobalt))
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
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

// ---------------------------------------------------------------------------
// Dealers  (নতুন বিক্রয় থেকে অটো তৈরি হয়)
// ---------------------------------------------------------------------------
class Dealer {
  final String id;
  String name;
  String phone;
  int visitCount;
  String lastVisit; // ISO-8601
  String gps; // ডিলারের লোকেশন (প্রথম ভিজিটে অটো সেট, পরে হাতে বদলানো যায়)
  String lastVisitGps; // সর্বশেষ বিক্রয়ের সময়ের লোকেশন
  double totalPurchase; // মোট নেট ক্রয়
  String lastInvoice;
  bool vip; // গুরুত্বপূর্ণ ডিলার হিসেবে মার্ক করা
  String reminder; // ভিজিট রিমাইন্ডারের তারিখ (YYYY-MM-DD), খালি = নেই

  Dealer({
    required this.id,
    required this.name,
    required this.phone,
    required this.visitCount,
    required this.lastVisit,
    required this.gps,
    required this.lastVisitGps,
    required this.totalPurchase,
    required this.lastInvoice,
    this.vip = false,
    this.reminder = '',
  });

  DateTime? get lastVisitDate =>
      lastVisit.isEmpty ? null : DateTime.tryParse(lastVisit);
  double get average => visitCount == 0 ? 0 : totalPurchase / visitCount;
  String get bestGps => parseGps(gps) != null
      ? gps
      : (parseGps(lastVisitGps) != null ? lastVisitGps : '');
  DateTime? get reminderDate =>
      reminder.isEmpty ? null : DateTime.tryParse(reminder);
  bool get reminderDue {
    final r = reminderDate;
    if (r == null) return false;
    final today = DateTime.now();
    return !DateTime(r.year, r.month, r.day)
        .isAfter(DateTime(today.year, today.month, today.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'visitCount': visitCount,
        'lastVisit': lastVisit,
        'gps': gps,
        'lastVisitGps': lastVisitGps,
        'totalPurchase': totalPurchase,
        'lastInvoice': lastInvoice,
        'vip': vip,
        'reminder': reminder,
      };

  factory Dealer.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '').toString();
    return Dealer(
      id: (j['id'] ?? dealerKey(name)).toString(),
      name: name,
      phone: (j['phone'] ?? '').toString(),
      visitCount: (j['visitCount'] as num?)?.toInt() ?? 0,
      lastVisit: (j['lastVisit'] ?? '').toString(),
      gps: (j['gps'] ?? '').toString(),
      lastVisitGps: (j['lastVisitGps'] ?? '').toString(),
      totalPurchase: (j['totalPurchase'] as num?)?.toDouble() ?? 0.0,
      lastInvoice: (j['lastInvoice'] ?? '').toString(),
      vip: j['vip'] == true,
      reminder: (j['reminder'] ?? '').toString(),
    );
  }
}

/// একই ডিলারকে চেনার key (বড়/ছোট হাতের ও বাড়তি স্পেস উপেক্ষা করে)
String dealerKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// এই ফোন থেকে অন্য ট্যাব (নতুন বিক্রয়) খুলতে ডিলার পাঠানোর চ্যানেল
final ValueNotifier<Dealer?> saleDealerRequest = ValueNotifier<Dealer?>(null);

/// আগের ইতিহাস থেকে ডিলার লিস্ট বানায় (প্রথমবার ফিচার চালুর সময়)
List<Dealer> buildDealersFromHistory(List<SaleRecord> history) {
  final map = <String, Dealer>{};
  final latest = <String, DateTime>{};
  for (final s in history) {
    final name = s.retailerName.trim();
    if (name.isEmpty) continue;
    final key = dealerKey(name);
    final dt = parseSaleDate(s.date);
    var d = map[key];
    if (d == null) {
      d = Dealer(
        id: key,
        name: name,
        phone: s.retailerPhone,
        visitCount: 0,
        lastVisit: dt?.toIso8601String() ?? '',
        gps: '',
        lastVisitGps: '',
        totalPurchase: 0,
        lastInvoice: s.invoiceNumber,
      );
      map[key] = d;
      if (dt != null) latest[key] = dt;
    }
    d.visitCount++;
    d.totalPurchase += s.cashAmount;
    if (d.phone.isEmpty && s.retailerPhone.isNotEmpty) d.phone = s.retailerPhone;
    final prev = latest[key];
    if (dt != null && (prev == null || dt.isAfter(prev))) {
      latest[key] = dt;
      d.lastVisit = dt.toIso8601String();
      d.lastInvoice = s.invoiceNumber;
    }
  }
  return map.values.toList();
}

/// নতুন বিক্রয়ের পর ডিলার তৈরি/আপডেট
void upsertDealerVisit(List<Dealer> dealers, SaleRecord sale, Position? pos) {
  final key = dealerKey(sale.retailerName);
  final gps = pos == null
      ? ''
      : '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
  final nowIso = DateTime.now().toIso8601String();
  final idx = dealers.indexWhere((d) => dealerKey(d.name) == key);
  if (idx == -1) {
    dealers.add(Dealer(
      id: key,
      name: sale.retailerName.trim(),
      phone: sale.retailerPhone,
      visitCount: 1,
      lastVisit: nowIso,
      gps: gps,
      lastVisitGps: gps,
      totalPurchase: sale.cashAmount,
      lastInvoice: sale.invoiceNumber,
    ));
    return;
  }
  final d = dealers[idx];
  d.name = sale.retailerName.trim();
  if (sale.retailerPhone.isNotEmpty) d.phone = sale.retailerPhone;
  d.visitCount++;
  d.lastVisit = nowIso;
  d.totalPurchase += sale.cashAmount;
  d.lastInvoice = sale.invoiceNumber;
  if (gps.isNotEmpty) {
    d.lastVisitGps = gps;
    if (parseGps(d.gps) == null) d.gps = gps; // ডিলারের লোকেশন একবারই অটো সেট হয়
  }
}

/// দ্রুত লোকেশন নেয়; পারমিশন/সিগন্যাল না পেলে null (বিক্রয় আটকায় না)
Future<Position?> tryGetPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 6),
      ),
    );
  } catch (_) {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int? _daysSince(DateTime? dt) {
  if (dt == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .difference(DateTime(dt.year, dt.month, dt.day))
      .inDays;
}

String relativeDays(DateTime? dt) {
  final d = _daysSince(dt);
  if (d == null) return 'তথ্য নেই';
  if (d <= 0) return 'আজ';
  if (d == 1) return 'গতকাল';
  if (d < 30) return '$d দিন আগে';
  if (d < 365) return '${d ~/ 30} মাস আগে';
  return '${d ~/ 365} বছর আগে';
}

String formatVisit(DateTime dt) =>
    '${dt.day} ${_bnMonths[dt.month - 1]} ${dt.year}, ${DateFormat('hh:mm a', 'en_US').format(dt)}';

const List<List<Color>> _avatarPalettes = [
  [AppColors.cobalt, AppColors.sky],
  [Color(0xFF7C3AED), Color(0xFFA78BFA)],
  [Color(0xFF0F766E), Color(0xFF14B8A6)],
  [Color(0xFFEA580C), Color(0xFFFB923C)],
  [Color(0xFFBE185D), Color(0xFFF472B6)],
];

Widget dealerAvatar(String name, double size) {
  final trimmed = name.trim();
  final initial = trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);
  final idx = trimmed.runes.fold<int>(0, (a, b) => a + b) % _avatarPalettes.length;
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: _avatarPalettes[idx],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
            color: _avatarPalettes[idx].first.o(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3)),
      ],
    ),
    child: Text(initial.toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800)),
  );
}

// ---------------------------------------------------------------------------
// Bottom bar : মাঝখানে "নতুন বিক্রয়" বাটন
// ---------------------------------------------------------------------------
class _NavSpec {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavSpec(this.icon, this.selectedIcon, this.label);
}

class AppBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const AppBottomBar({super.key, required this.index, required this.onChanged});

  static const int centerIndex = 2;
  static const List<_NavSpec> _items = [
    _NavSpec(Icons.grid_view_outlined, Icons.grid_view_rounded, 'ড্যাশবোর্ড'),
    _NavSpec(Icons.storefront_outlined, Icons.storefront_rounded, 'ডিলার'),
    _NavSpec(Icons.add_circle_outline, Icons.add_circle_rounded, 'নতুন বিক্রয়'),
    _NavSpec(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'ইতিহাস'),
    _NavSpec(Icons.router_outlined, Icons.router_rounded, 'ওয়াইফাই জোন'),
  ];

  Widget _label(String text, bool selected) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? AppColors.cobalt : AppColors.muted,
            )),
      );

  Widget _item(int i) {
    final s = _items[i];
    final sel = index == i;
    return InkWell(
      onTap: () => onChanged(i),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? AppColors.paleSky : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(sel ? s.selectedIcon : s.icon,
                size: 24, color: sel ? AppColors.cobalt : AppColors.muted),
          ),
          const SizedBox(height: 2),
          _label(s.label, sel),
        ],
      ),
    );
  }

  Widget _center() {
    final s = _items[centerIndex];
    final sel = index == centerIndex;
    return InkWell(
      onTap: () => onChanged(centerIndex),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: sel ? 56 : 52,
            height: sel ? 56 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.cobalt, AppColors.sky],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: sel ? AppColors.paleSky : Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                    color: AppColors.cobalt.o(sel ? 0.5 : 0.3),
                    blurRadius: sel ? 16 : 10,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: Icon(s.selectedIcon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 2),
          _label(s.label, sel),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 78 + bottom,
      padding: EdgeInsets.only(bottom: bottom, top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: AppColors.cobalt.o(0.14),
              blurRadius: 22,
              offset: const Offset(0, -6)),
        ],
      ),
      child: Row(
        children: List.generate(
          _items.length,
          (i) => Expanded(child: i == centerIndex ? _center() : _item(i)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dealer screen
// ---------------------------------------------------------------------------
enum DealerSort { recent, visits, purchase, name, nearest }

enum DealerFilter { all, today, stale, noGps, vip, reminder }

class DealerScreen extends StatefulWidget {
  final bool active;
  const DealerScreen({super.key, this.active = true});
  @override
  State<DealerScreen> createState() => _DealerScreenState();
}

class _DealerScreenState extends State<DealerScreen> {
  List<Dealer> _dealers = [];
  List<SaleRecord> _history = [];
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  DealerSort _sort = DealerSort.recent;
  DealerFilter _filter = DealerFilter.all;
  Position? _position;
  bool _locationTried = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    AppPrefs.dataVersion.addListener(_load);
    _load();
    if (widget.active) _fetchPosition();
  }

  @override
  void didUpdateWidget(DealerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _load();
      if (!_locationTried) _fetchPosition();
    }
  }

  @override
  void dispose() {
    AppPrefs.dataVersion.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetchPosition() async {
    _locationTried = true;
    final pos = await tryGetPosition();
    if (mounted && pos != null) setState(() => _position = pos);
  }

  Future<void> _load() async {
    final p = await AppPrefs.getInstance();
    final ds = await p.ensureDealers();
    final h = p.history();
    if (!mounted) return;
    setState(() {
      _dealers = ds;
      _history = h;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    await AppPrefs.pullNow();
    await _load();
    await _fetchPosition();
  }

  double? _distanceOf(Dealer d) {
    final pos = _position;
    if (pos == null) return null;
    final pts = parseGps(d.bestGps);
    if (pts == null) return null;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, pts[0], pts[1]);
  }

  List<Dealer> get _visible {
    final q = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final list = _dealers.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !d.phone.contains(q)) {
        return false;
      }
      switch (_filter) {
        case DealerFilter.all:
          return true;
        case DealerFilter.today:
          final dt = d.lastVisitDate;
          return dt != null && _sameDay(dt, now);
        case DealerFilter.stale:
          final days = _daysSince(d.lastVisitDate);
          return days != null && days >= 30;
        case DealerFilter.noGps:
          return d.bestGps.isEmpty;
        case DealerFilter.vip:
          return d.vip;
        case DealerFilter.reminder:
          return d.reminderDue;
      }
    }).toList();

    switch (_sort) {
      case DealerSort.recent:
        list.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
        break;
      case DealerSort.visits:
        list.sort((a, b) => b.visitCount.compareTo(a.visitCount));
        break;
      case DealerSort.purchase:
        list.sort((a, b) => b.totalPurchase.compareTo(a.totalPurchase));
        break;
      case DealerSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case DealerSort.nearest:
        list.sort((a, b) {
          final da = _distanceOf(a);
          final db = _distanceOf(b);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        break;
    }
    return list;
  }

  Color _tone(int? days) {
    if (days == null) return AppColors.muted;
    if (days <= 7) return AppColors.success;
    if (days <= 30) return AppColors.cobalt;
    return AppColors.warn;
  }

  String _sortLabel(DealerSort s) {
    switch (s) {
      case DealerSort.recent:
        return 'সর্বশেষ ভিজিট';
      case DealerSort.visits:
        return 'বেশি ভিজিট';
      case DealerSort.purchase:
        return 'বেশি ক্রয়';
      case DealerSort.name:
        return 'নাম (ক-হ)';
      case DealerSort.nearest:
        return 'কাছের আগে';
    }
  }

  // ---- actions -------------------------------------------------------------
  Future<void> _mutate(Dealer d, void Function(Dealer) fn) async {
    final p = await AppPrefs.getInstance();
    final list = await p.ensureDealers();
    final i = list.indexWhere((x) => x.id == d.id);
    if (i == -1) return;
    fn(list[i]);
    await p.saveDealers(list);
    if (mounted) await _load();
  }

  Future<void> _call(Dealer d) async {
    if (d.phone.trim().isEmpty) {
      showMsg(context, 'এই ডিলারের ফোন নাম্বার নেই', error: true);
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: d.phone.trim()));
    } catch (_) {
      if (mounted) showMsg(context, 'কল করা যাচ্ছে না', error: true);
    }
  }

  Future<void> _openMap(String gps) async {
    final pts = parseGps(gps);
    if (pts == null) {
      showMsg(context, 'এই ডিলারের GPS লোকেশন সেভ নেই', error: true);
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pts[0]},${pts[1]}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showMsg(context, 'ম্যাপ খোলা যাচ্ছে না। লোকেশন: $gps', error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'ম্যাপ খোলা যাচ্ছে না। লোকেশন: $gps', error: true);
    }
  }

  Future<void> _setGpsHere(Dealer d) async {
    showMsg(context, 'লোকেশন নেওয়া হচ্ছে...');
    final pos = await tryGetPosition();
    if (!mounted) return;
    if (pos == null) {
      showMsg(context, 'লোকেশন পাওয়া যায়নি। GPS ও পারমিশন চালু আছে কিনা দেখুন।',
          error: true);
      return;
    }
    final g =
        '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    await _mutate(d, (x) {
      x.gps = g;
      x.lastVisitGps = g;
    });
    if (mounted) showMsg(context, 'ডিলারের লোকেশন আপডেট হয়েছে');
  }

  Future<void> _edit(Dealer d) async {
    final nameCtrl = TextEditingController(text: d.name);
    final phoneCtrl = TextEditingController(text: d.phone);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('ডিলার এডিট',
              style: TextStyle(color: AppColors.cobalt)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: 'ডিলার নাম',
                    prefixIcon: const Icon(Icons.store),
                    errorText: err),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'ফোন', prefixIcon: Icon(Icons.phone)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) {
                  setSt(() => err = 'নাম আবশ্যক');
                  return;
                }
                final dup = _dealers.any(
                    (x) => x.id != d.id && dealerKey(x.name) == dealerKey(n));
                if (dup) {
                  setSt(() => err = 'এই নামে আরেকজন ডিলার আছে');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('সংরক্ষণ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _mutate(d, (x) {
      x.name = nameCtrl.text.trim();
      x.phone = phoneCtrl.text.trim();
    });
    if (mounted) showMsg(context, 'ডিলারের তথ্য আপডেট হয়েছে');
  }

  Future<void> _delete(Dealer d) async {
    final ok = await confirmDialog(
      context,
      title: 'ডিলার মুছবেন?',
      message: '"${d.name}" ডিলার তালিকা থেকে মুছে যাবে। বিক্রয়ের ইতিহাস অক্ষত থাকবে, '
          'তবে ভিজিট কাউন্ট নতুন করে শুরু হবে।',
      yes: 'মুছুন',
      danger: true,
    );
    if (!ok) return;
    final p = await AppPrefs.getInstance();
    final list = await p.ensureDealers();
    list.removeWhere((x) => x.id == d.id);
    await p.saveDealers(list);
    if (mounted) {
      await _load();
      if (mounted) showMsg(context, 'ডিলার মুছে ফেলা হয়েছে');
    }
  }

  void _newSale(Dealer d) => saleDealerRequest.value = d;

  Future<void> _toggleVip(Dealer d) async {
    await _mutate(d, (x) => x.vip = !x.vip);
    if (mounted) {
      showMsg(context, d.vip ? 'VIP তালিকা থেকে সরানো হয়েছে' : 'VIP হিসেবে মার্ক করা হয়েছে');
    }
  }

  Future<void> _setReminder(Dealer d) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: d.reminderDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'ভিজিট রিমাইন্ডারের তারিখ বাছাই করুন',
    );
    if (picked == null) return;
    final iso = DateTime(picked.year, picked.month, picked.day).toIso8601String();
    await _mutate(d, (x) => x.reminder = iso);
    if (mounted) showMsg(context, 'রিমাইন্ডার সেট হয়েছে');
  }

  Future<void> _clearReminder(Dealer d) async {
    await _mutate(d, (x) => x.reminder = '');
    if (mounted) showMsg(context, 'রিমাইন্ডার মুছে ফেলা হয়েছে');
  }

  /// GPS আছে এমন সব ডিলারকে একসাথে Google Maps-এ রুট আকারে খোলে (সর্বোচ্চ ১০টি স্টপ)
  Future<void> _openAllOnMap() async {
    final withGps = _dealers
        .map((d) => parseGps(d.bestGps))
        .whereType<List<double>>()
        .take(10)
        .toList();
    if (withGps.isEmpty) {
      showMsg(context, 'কোনো ডিলারের GPS লোকেশন সেভ করা নেই', error: true);
      return;
    }
    final dest = withGps.last;
    final waypoints = withGps
        .sublist(0, withGps.length - 1)
        .map((p) => '${p[0]},${p[1]}')
        .join('|');
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${dest[0]},${dest[1]}'
        '${waypoints.isEmpty ? '' : '&waypoints=$waypoints'}&travelmode=driving');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showMsg(context, 'ম্যাপ খোলা যাচ্ছে না', error: true);
    } catch (_) {
      if (mounted) showMsg(context, 'ম্যাপ খোলা যাচ্ছে না', error: true);
    }
  }

  Future<void> _openDetail(Dealer d) async {
    final key = dealerKey(d.name);
    final sales = _history.where((s) => dealerKey(s.retailerName) == key).toList();
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DealerSheet(
        dealer: d,
        sales: sales,
        distance: _distanceOf(d),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'call':
        await _call(d);
        break;
      case 'map':
        await _openMap(d.bestGps);
        break;
      case 'lastmap':
        await _openMap(d.lastVisitGps);
        break;
      case 'sale':
        _newSale(d);
        break;
      case 'edit':
        await _edit(d);
        break;
      case 'setgps':
        await _setGpsHere(d);
        break;
      case 'vip':
        await _toggleVip(d);
        break;
      case 'reminder':
        await _setReminder(d);
        break;
      case 'clearReminder':
        await _clearReminder(d);
        break;
      case 'delete':
        await _delete(d);
        break;
    }
  }

  // ---- UI ------------------------------------------------------------------
  Widget _summary(List<Dealer> all) {
    final now = DateTime.now();
    final visits = all.fold<int>(0, (a, d) => a + d.visitCount);
    final today = all.where((d) {
      final dt = d.lastVisitDate;
      return dt != null && _sameDay(dt, now);
    }).length;
    Widget cell(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: Colors.white.o(0.85), size: 20),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(color: Colors.white.o(0.75), fontSize: 11)),
            ],
          ),
        );
    Widget divider() =>
        Container(width: 1, height: 44, color: Colors.white.o(0.2));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cobalt, AppColors.navy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.cobalt.o(0.28),
              blurRadius: 14,
              offset: const Offset(0, 7)),
        ],
      ),
      child: Row(
        children: [
          cell(Icons.storefront_rounded, '${all.length}', 'মোট ডিলার'),
          divider(),
          cell(Icons.repeat_rounded, '$visits', 'মোট ভিজিট'),
          divider(),
          cell(Icons.today_rounded, '$today', 'আজ ভিজিট'),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.o(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _card(Dealer d) {
    final dt = d.lastVisitDate;
    final days = _daysSince(dt);
    final tone = _tone(days);
    final dist = _distanceOf(d);
    final hasGps = d.bestGps.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _openDetail(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              dealerAvatar(d.name, 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        if (d.vip) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded,
                              color: AppColors.warn, size: 17),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(d.phone.isEmpty ? 'ফোন নেই' : d.phone,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.sky.o(0.3)),
                ),
                child: Column(
                  children: [
                    Text('${d.visitCount}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.cobalt)),
                    const Text('ভিজিট',
                        style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(Icons.schedule_rounded, relativeDays(dt), tone),
              _pill(Icons.payments_outlined, taka(d.totalPurchase),
                  AppColors.cobalt),
              if (dist != null)
                _pill(Icons.near_me_rounded, formatDistance(dist), AppColors.sky),
              _pill(hasGps ? Icons.location_on_rounded : Icons.location_off_rounded,
                  hasGps ? 'লোকেশন সেভ' : 'GPS নেই',
                  hasGps ? AppColors.success : Colors.grey),
              if (d.reminderDue)
                _pill(Icons.notifications_active_rounded, 'রিমাইন্ডার', AppColors.danger),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: d.phone.isEmpty ? null : () => _call(d),
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: const Text('কল'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasGps ? () => _openMap(d.bestGps) : null,
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('ম্যাপ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _newSale(d),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12)),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: const Text('বিক্রয়'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    const filterLabels = {
      DealerFilter.all: 'সব',
      DealerFilter.today: 'আজ এসেছে',
      DealerFilter.stale: '৩০+ দিন আসেনি',
      DealerFilter.noGps: 'GPS নেই',
      DealerFilter.vip: 'VIP',
      DealerFilter.reminder: 'রিমাইন্ডার',
    };

    return Scaffold(
      body: Column(
        children: [
          ModernHeader(
            title: 'ডিলার',
            subtitle: '${_dealers.length} জন ডিলার • নতুন বিক্রয় থেকে অটো তৈরি',
          ),
          Expanded(
            child: _loading
                ? const Center(child: WifiLoader(size: 96, color: AppColors.cobalt))
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        if (_dealers.isNotEmpty) _summary(_dealers),
                        TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText: 'নাম বা ফোন দিয়ে খুঁজুন...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: _search.clear),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...DealerFilter.values.map((f) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(filterLabels[f]!),
                                      selected: _filter == f,
                                      onSelected: (_) =>
                                          setState(() => _filter = f),
                                    ),
                                  )),
                              ActionChip(
                                avatar: const Icon(Icons.map_rounded, size: 16),
                                label: const Text('সব ডিলার ম্যাপে'),
                                onPressed: _openAllOnMap,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 0, 8),
                          child: Row(
                            children: [
                              Text('${list.length} জন',
                                  style: const TextStyle(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              PopupMenuButton<DealerSort>(
                                tooltip: 'সাজান',
                                onSelected: (s) {
                                  if (s == DealerSort.nearest &&
                                      _position == null) {
                                    showMsg(context,
                                        'লোকেশন পাওয়া যাচ্ছে না — GPS/পারমিশন চালু করুন',
                                        error: true);
                                    _fetchPosition();
                                    return;
                                  }
                                  setState(() => _sort = s);
                                },
                                itemBuilder: (_) => DealerSort.values
                                    .map((s) => PopupMenuItem(
                                          value: s,
                                          child: Row(children: [
                                            Icon(
                                                _sort == s
                                                    ? Icons.check_rounded
                                                    : Icons.sort_rounded,
                                                size: 18,
                                                color: AppColors.cobalt),
                                            const SizedBox(width: 8),
                                            Text(_sortLabel(s)),
                                          ]),
                                        ))
                                    .toList(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.swap_vert_rounded,
                                        size: 18, color: AppColors.cobalt),
                                    const SizedBox(width: 4),
                                    Text(_sortLabel(_sort),
                                        style: const TextStyle(
                                            color: AppColors.cobalt,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (list.isEmpty)
                          SizedBox(
                            height: 280,
                            child: EmptyState(
                              icon: Icons.storefront_rounded,
                              text: _dealers.isEmpty
                                  ? 'এখনও কোনো ডিলার নেই'
                                  : 'কোনো ডিলার পাওয়া যায়নি',
                              hint: _dealers.isEmpty
                                  ? '"নতুন বিক্রয়" করলেই ডিলার অটো যোগ হবে'
                                  : 'সার্চ বা ফিল্টার বদলে দেখুন',
                            ),
                          )
                        else
                          ...list.map(_card),
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
// Dealer detail bottom sheet
// ---------------------------------------------------------------------------
class _DealerSheet extends StatelessWidget {
  final Dealer dealer;
  final List<SaleRecord> sales;
  final double? distance;
  const _DealerSheet(
      {required this.dealer, required this.sales, required this.distance});

  Widget _stat(String label, String value, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: c.o(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.o(0.2)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: c)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.cobalt),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 1),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, String key, IconData icon, String label,
      {bool primary = false, bool danger = false, bool enabled = true}) {
    final onTap = enabled ? () => Navigator.pop(context, key) : null;
    if (primary) {
      return ElevatedButton.icon(
          onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label));
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: danger
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.o(0.5)))
          : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = dealer;
    final last = d.lastVisitDate;
    final recent = sales.take(5).toList();
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  dealerAvatar(d.name, 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(d.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w900)),
                            ),
                            if (d.vip) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.star_rounded,
                                  color: AppColors.warn, size: 22),
                            ],
                          ],
                        ),
                        Text(d.phone.isEmpty ? 'ফোন নেই' : d.phone,
                            style: const TextStyle(color: AppColors.muted)),
                        if (distance != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('আপনার থেকে ${formatDistance(distance!)} দূরে',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.sky,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _stat('ভিজিট', '${d.visitCount}', AppColors.cobalt),
                  const SizedBox(width: 10),
                  _stat('মোট ক্রয়', taka(d.totalPurchase), AppColors.success),
                  const SizedBox(width: 10),
                  _stat('গড়/ভিজিট', taka(d.average), AppColors.sky),
                ],
              ),
              const SizedBox(height: 10),
              _info(
                Icons.schedule_rounded,
                'সর্বশেষ ভিজিট',
                last == null ? 'তথ্য নেই' : '${formatVisit(last)}  •  ${relativeDays(last)}',
              ),
              _info(Icons.receipt_long_rounded, 'সর্বশেষ ইনভয়েস',
                  d.lastInvoice.isEmpty ? '—' : '#${d.lastInvoice}'),
              _info(Icons.location_on_rounded, 'ডিলারের লোকেশন',
                  d.bestGps.isEmpty ? 'সেট করা নেই' : d.bestGps),
              _info(Icons.pin_drop_outlined, 'সর্বশেষ ভিজিটের লোকেশন',
                  d.lastVisitGps.isEmpty ? 'সেভ হয়নি' : d.lastVisitGps),
              _info(
                Icons.notifications_active_outlined,
                'ভিজিট রিমাইন্ডার',
                d.reminderDate == null
                    ? 'সেট করা নেই'
                    : '${formatVisit(d.reminderDate!).split(',').first}'
                        '${d.reminderDue ? ' — আজই ভিজিট করুন' : ''}',
              ),
              if (recent.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('সাম্প্রতিক ইনভয়েস',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.cobalt)),
                const SizedBox(height: 6),
                ...recent.map((s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('#${s.invoiceNumber} • ${s.date}',
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.muted)),
                          ),
                          Text(taka(s.cashAmount),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    )),
              ],
              const Divider(height: 26),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _action(context, 'sale', Icons.add_shopping_cart_rounded,
                      'নতুন বিক্রয়',
                      primary: true),
                  _action(context, 'call', Icons.call_rounded, 'কল',
                      enabled: d.phone.isNotEmpty),
                  _action(context, 'map', Icons.map_outlined, 'ম্যাপ',
                      enabled: d.bestGps.isNotEmpty),
                  _action(context, 'lastmap', Icons.pin_drop_outlined,
                      'সর্বশেষ ভিজিট ম্যাপে',
                      enabled: d.lastVisitGps.isNotEmpty),
                  _action(context, 'setgps', Icons.my_location_rounded,
                      'এখানকার লোকেশন সেট'),
                  _action(context, 'vip', d.vip ? Icons.star_rounded : Icons.star_border_rounded,
                      d.vip ? 'VIP বাতিল' : 'VIP করুন'),
                  _action(context, 'reminder', Icons.notifications_active_outlined,
                      d.reminderDate == null ? 'রিমাইন্ডার সেট' : 'রিমাইন্ডার বদলান'),
                  if (d.reminderDate != null)
                    _action(context, 'clearReminder', Icons.notifications_off_outlined,
                        'রিমাইন্ডার মুছুন'),
                  _action(context, 'edit', Icons.edit_outlined, 'এডিট'),
                  _action(context, 'delete', Icons.delete_outline, 'মুছুন',
                      danger: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}