import 'package:flutter/material.dart';

import '../api/model_api.dart';
import '../theme/tokens.dart';
import 'premium.dart';

/// "Your phone" card shared by the AI and speech model pickers: name, RAM, chip and free space.
/// [t] looks up the `m_*` labels in the screen's language.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.dev, required this.t});
  final DeviceInfo dev;
  final String Function(String key) t;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final p = palOf(context);
    Widget cell(String v, String k) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(Sp.m),
            decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : p.page, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text(k, style: th.textTheme.bodySmall?.copyWith(color: p.muted, fontSize: 14)),
            ]),
          ),
        );
    return PCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.smartphone_rounded, color: p.accent, size: 28),
          const SizedBox(width: Sp.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('m_phone'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(dev.phoneLabel.isEmpty ? t('m_unknown') : dev.phoneLabel, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.m),
        Row(children: [
          cell(dev.ramLabel, t('m_ram')),
          const SizedBox(width: Sp.s),
          cell(dev.soc.isEmpty ? '—' : dev.soc, t('m_chip')),
          const SizedBox(width: Sp.s),
          cell(dev.storageLabel, t('m_free')),
        ]),
      ]),
    );
  }
}
