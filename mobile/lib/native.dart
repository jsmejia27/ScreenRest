import 'package:flutter/services.dart';

/// Calls into the Kotlin side (MainActivity / BreakService) over the "screenrest/native" channel.
/// Every call is safe to make when the native side is missing (tests, other platforms): it just returns defaults.
class Native {
  static const _ch = MethodChannel('screenrest/native');

  /// Called when a break notification is tapped while the app is already open.
  static void onOpenBreak(void Function(String type, String kind) handler) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openBreak') {
        final a = Map<String, dynamic>.from(call.arguments as Map);
        handler(a['type'] as String? ?? 'eye', a['kind'] as String? ?? 'other');
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _map(String method, [Object? args]) async {
    final m = await _call<Map>(method, args);
    return m == null ? {} : Map<String, dynamic>.from(m);
  }

  static Future<Map<String, dynamic>?> launchBreak() async {
    final m = await _call<Map>('launchBreak');
    return m == null ? null : Map<String, dynamic>.from(m);
  }

  static Future<Map<String, dynamic>> settings() => _map('getSettings');
  static Future<void> saveSettings(Map<String, Object?> s) => _call('saveSettings', s);
  static Future<void> setEnabled(bool on) => _call('setEnabled', on);
  static Future<Map<String, dynamic>> status() => _map('status');
  static Future<Map<String, dynamic>> permissions() => _map('permissions');

  static Future<List<Map<String, dynamic>>> stats(int days) async {
    final l = await _call<List>('stats', days);
    return (l ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> recentApps() async {
    final l = await _call<List>('recentApps');
    return (l ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Screen time per app over the last [days] days: [{pkg, label, kind, seconds, late}], most used first.
  static Future<List<Map<String, dynamic>>> appStats(int days) async {
    final l = await _call<List>('appStats', days);
    return (l ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// The launcher icon of [pkg] as PNG bytes, or null if it can't be read.
  static Future<Uint8List?> appIcon(String pkg) => _call<Uint8List>('appIcon', pkg);

  /// Lays out [report] as a PDF and opens the share sheet. False if that failed.
  static Future<bool> exportPdf(Map<String, Object?> report) async => await _call<bool>('exportPdf', report) ?? false;

  static Future<void> setAppKind(String pkg, String? kind) => _call('setAppKind', {'pkg': pkg, 'kind': kind});
  static Future<void> breakDone(String type, {required bool taken}) => _call('breakDone', {'type': type, 'taken': taken});
  static Future<void> pause(int minutes) => _call('pause', minutes);
  static Future<void> resume() => _call('resume');
  static Future<void> testReminder(String type) => _call('testReminder', type);
  static Future<void> requestNotifications() => _call('requestNotifications');
  static Future<void> openUsageAccess() => _call('openUsageAccess');
  static Future<void> openOverlay() => _call('openOverlay');
  static Future<void> openBattery() => _call('openBattery');
  static Future<void> openDisplay() => _call('openDisplay');
  static Future<bool> playVoice(String slug) async => await _call<bool>('playVoice', slug) ?? false;
  static Future<void> stopVoice() => _call('stopVoice');
}
