import 'package:flutter/material.dart';

import 'lang.dart';
import 'theme.dart';

/// Rounded panel with an optional small heading.
class Section extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets padding;
  const Section({super.key, this.title, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(color: C.dim, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Horizontal bar split by activity, with a legend underneath.
class KindBar extends StatelessWidget {
  final Map<String, double> seconds;
  const KindBar({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final order = ['reading', 'watching', 'gaming', 'other'];
    final total = order.fold<double>(0, (s, k) => s + (seconds[k] ?? 0));
    if (total < 60) {
      return Text(L.t('No screen time yet today.', 'Wala pang screen time ngayong araw.'), style: const TextStyle(color: C.dim));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (final k in order)
                if ((seconds[k] ?? 0) > 0)
                  Expanded(flex: ((seconds[k]! / total) * 1000).round().clamp(1, 1000), child: Container(color: C.kinds[k])),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final k in order)
            if ((seconds[k] ?? 0) >= 60)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: C.kinds[k], shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${L.kind(k)} ${L.duration(seconds[k]!)}', style: const TextStyle(fontSize: 13)),
              ]),
        ]),
      ],
    );
  }
}

/// A permission row: what it is for, whether it's on, and a button to turn it on.
class PermTile extends StatelessWidget {
  final String title, why;
  final bool ok, required;
  final VoidCallback onTap;
  const PermTile({super.key, required this.title, required this.why, required this.ok, required this.onTap, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? C.accent : (required ? C.warn : C.dim)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            Text(why, style: const TextStyle(color: C.dim, fontSize: 13)),
          ]),
        ),
        if (!ok) TextButton(onPressed: onTap, child: Text(L.t('Turn on', 'I-on'))),
      ]),
    );
  }
}
