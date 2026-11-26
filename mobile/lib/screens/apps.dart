import 'package:flutter/material.dart';

import '../lang.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// Lets the person relabel apps used in the last 7 days as reading, watching, gaming or other.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<Map<String, dynamic>> _apps = [];
  bool _loaded = false;
  bool _usage = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([Native.recentApps(), Native.permissions()]);
    if (!mounted) return;
    setState(() {
      _apps = r[0] as List<Map<String, dynamic>>;
      _usage = (r[1] as Map<String, dynamic>)['usage'] == true;
      _loaded = true;
    });
  }

  Future<void> _change(Map<String, dynamic> app) async {
    const kinds = ['reading', 'watching', 'gaming', 'other'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.panel,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(app['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final k in kinds)
            ListTile(
              leading: Icon(Icons.circle, color: C.kinds[k], size: 14),
              title: Text(L.kind(k)),
              trailing: app['kind'] == k ? const Icon(Icons.check, color: C.accent) : null,
              onTap: () => Navigator.pop(c, k),
            ),
          if (app['custom'] == true)
            ListTile(
              leading: const Icon(Icons.restart_alt, color: C.dim),
              title: Text(L.t('Let ScreenRest decide', 'Hayaang ang ScreenRest ang magpasya')),
              onTap: () => Navigator.pop(c, ''),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    await Native.setAppKind(app['pkg'] as String, picked.isEmpty ? null : picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('Your apps', 'Iyong mga app'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : !_usage
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      L.t('Allow usage access first, so ScreenRest can see which apps you use.',
                          'Payagan muna ang usage access para makita ng ScreenRest kung anong mga app ang ginagamit mo.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: Native.openUsageAccess, child: Text(L.t('Allow usage access', 'Payagan ang usage access'))),
                  ]),
                )
              : _apps.isEmpty
                  ? Center(child: Text(L.t('No apps used in the last 7 days yet.', 'Wala pang app na nagamit sa nakaraang 7 araw.'),
                      style: const TextStyle(color: C.dim)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _apps.length + 1,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: C.panel),
                      itemBuilder: (c, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Text(
                              L.t('Apps you used in the last 7 days. Tap one to change its type.',
                                  'Mga app na nagamit mo sa nakaraang 7 araw. I-tap para baguhin ang uri.'),
                              style: const TextStyle(color: C.dim),
                            ),
                          );
                        }
                        final a = _apps[i - 1];
                        final kind = a['kind'] as String? ?? 'other';
                        return ListTile(
                          leading: AppIcon(pkg: a['pkg'] as String, kind: kind, size: 36),
                          title: Text(a['label'] as String? ?? a['pkg'] as String),
                          subtitle: Text(L.t('${a['minutes']} min this week', '${a['minutes']} min ngayong linggo'),
                              style: const TextStyle(color: C.dim)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.circle, size: 10, color: C.kinds[kind]),
                            const SizedBox(width: 6),
                            Text(L.kind(kind) + (a['custom'] == true ? ' ✎' : '')),
                          ]),
                          onTap: () => _change(a),
                        );
                      },
                    ),
    );
  }
}
