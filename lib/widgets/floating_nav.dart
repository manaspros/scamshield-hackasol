import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'island.dart';

class FloatingNavItem {
  const FloatingNavItem({required this.icon, required this.selectedIcon, required this.label, required this.key});
  final IconData icon, selectedIcon;
  final String label;
  final Key key;
}

/// Minimal floating bottom bar: a pill island with an icon and its word for every tab; the selected tab is accent + bold.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap});
  final List<FloatingNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Sp.l, top: Sp.s),
        child: Center(
          heightFactor: 1,
          child: IslandSurface(
            radius: Rad.pill,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < items.length; i++)
                Semantics(
                  selected: i == index,
                  button: true,
                  label: items[i].label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: items[i].key,
                    borderRadius: BorderRadius.circular(Rad.pill),
                    onTap: () => onTap(i),
                    child: SizedBox(
                      width: 84,
                      height: 58,
                      child: _item(items[i], i == index, p, th),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _item(FloatingNavItem it, bool sel, Pal p, ThemeData th) {
    final c = sel ? p.accent : p.muted;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: sel ? 56 : 44,
        height: 32,
        decoration: BoxDecoration(
          color: sel ? p.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.pill),
        ),
        child: Icon(sel ? it.selectedIcon : it.icon, size: sel ? 24 : 26, color: c),
      ),
      // Every tab shows its word (icons alone were hard to read); the selected one is accent + bold.
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(it.label,
              maxLines: 1,
              style: th.textTheme.labelSmall?.copyWith(
                  fontSize: 13, height: 1.1, color: c, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    ]);
  }
}
