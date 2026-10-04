import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences kept between launches. Nothing secret goes in here: no password, no recovery phrase, no keys.
class AppSettings {
  AppSettings._(this._prefs);

  /// In-memory settings: used when storage is unavailable (private browsing, blocked storage) and in tests.
  AppSettings.memory() : _prefs = null;

  final SharedPreferences? _prefs;

  static const _kNode = 'node_url';
  static const _kWallet = 'last_wallet_name';
  static const _kTheme = 'theme_mode';

  String? nodeUrl;
  String? lastWalletName;
  ThemeMode themeMode = ThemeMode.system;

  /// Never throws: a browser that blocks storage must not stop the wallet from starting.
  static Future<AppSettings> load() async {
    try {
      final s = AppSettings._(await SharedPreferences.getInstance());
      s.nodeUrl = s._prefs!.getString(_kNode);
      s.lastWalletName = s._prefs.getString(_kWallet);
      final t = s._prefs.getString(_kTheme);
      s.themeMode = ThemeMode.values.firstWhere((m) => m.name == t, orElse: () => ThemeMode.system);
      return s;
    } on Object {
      return AppSettings.memory();
    }
  }

  Future<void> save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      Future<void> put(String key, String? value) async {
        if (value == null || value.isEmpty) {
          await p.remove(key);
        } else {
          await p.setString(key, value);
        }
      }

      await put(_kNode, nodeUrl);
      await put(_kWallet, lastWalletName);
      await put(_kTheme, themeMode.name);
    } on Object {
      // Losing a preference is better than failing the action that triggered the save.
    }
  }
}
