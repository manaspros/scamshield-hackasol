import 'package:flutter/material.dart';

import '../api/home_api.dart';
import '../api/llm_api.dart';
import '../api/model_api.dart';
import '../api/model_catalog.dart';
import '../demo/demo_flag.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_profile.dart';
import '../models/verdict.dart';
import '../profile/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';
import '../widgets/shell_bar.dart';
import 'demo_lab_screen.dart';
import 'family_screen.dart';
import 'model_picker_screen.dart';
import 'page_route.dart';
import 'recording_screen.dart';
import 'settings_screen.dart' show SettingsScreen, kDistricts;
import 'setup_screen.dart';

/// Profile tab: who the user is (used to tailor lessons), their family, protection checks and help.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onOpen, this.api = const HomeApi(), this.models = const ModelApi()});

  /// Opens a page titled by a shell string key (from HomeShell); falls back to [pushTitled].
  final void Function(String titleKey, Widget page)? onOpen;
  final HomeApi api;
  final ModelApi models;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  bool? _paired;
  Protection? _prot;
  ModelState? _model;
  List<ModelSpec> _catalog = kFallbackCatalog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final paired = await widget.api.familyPaired();
    final prot = await widget.api.protection();
    final m = await widget.models.state();
    final cat = ModelCatalogStore.models.value;
    if (!mounted) return;
    LlmStatus.ready.value = m.ready;
    setState(() {
      _paired = paired;
      _prot = prot;
      _model = m;
      _catalog = cat;
    });
  }

  String _t(String k, [Map<String, Object?> a = const {}]) => profileT(AppLanguage.of(context), k, a);

  Future<void> _go(String title, Widget page) async {
    await pushTitled(context, title, page);
    if (mounted) _refresh();
  }

  Future<void> _save(UserProfile p) async {
    await ProfileStore.save(p);
    if (mounted) showIsland(context, _t('saved'), tone: IslandTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguage.of(context);
    return ValueListenableBuilder<UserProfile>(
      valueListenable: ProfileStore.profile,
      builder: (context, prof, _) => ListView(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl),
        children: [
          _header(prof, lang),
          PSection(title: _t('details')),
          _details(prof, lang),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.s, Sp.xs, 0),
            child: Row(children: [
              Icon(Icons.lock_rounded, size: 16, color: palOf(context).muted),
              const SizedBox(width: Sp.xs),
              Expanded(child: Text(_t('privacy'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palOf(context).muted, fontSize: 14))),
            ]),
          ),
          PSection(title: _t('family'), action: _t('add_member'), actionKey: const Key('profile_add_member'), onAction: () => _editContact(null)),
          _family(),
          PSection(title: _t('checks')),
          _checks(),
          PSection(title: _t('help')),
          _help(lang),
        ],
      ),
    );
  }

  Widget _header(UserProfile prof, String lang) {
    final th = Theme.of(context);
    final p = palOf(context);
    final age = prof.ageOn();
    final sub = [if (age != null) _t('years', {'n': age}), if (prof.district != null) prof.district!].join(' · ');
    final pct = (prof.completeness * 100).round();
    return PCard(
      key: const Key('profile_header'),
      padding: const EdgeInsets.all(Sp.l + 4),
      child: Row(children: [
        RingProgress(
          value: prof.completeness,
          size: 80,
          stroke: 5,
          color: p.accent,
          track: p.accentTint,
          child: CircleAvatar(
            radius: 30,
            backgroundColor: p.accent,
            child: prof.initials.isEmpty
                ? Icon(Icons.person_rounded, color: p.onAccent, size: 32)
                : Text(prof.initials, style: th.textTheme.titleLarge?.copyWith(color: p.onAccent, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: Sp.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((prof.name ?? '').trim().isEmpty ? _t('add_name') : prof.name!.trim(),
                style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty) Text(sub, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
            const SizedBox(height: 2),
            Text(pct >= 100 ? _t('complete_full') : _t('complete', {'p': pct}),
                key: const Key('profile_completeness'),
                style: th.textTheme.titleSmall?.copyWith(color: pct >= 100 ? (th.extension<StatusColors>() ?? StatusColors.light).safe : p.accent)),
          ]),
        ),
      ]),
    );
  }

  Widget _details(UserProfile prof, String lang) {
    final p = palOf(context);
    String? v(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    String add(String? s) => v(s) ?? _t('add');
    Color? addC(Object? s) => (s == null || (s is String && s.trim().isEmpty)) ? p.accent : null;
    return PGroup(children: [
      PRow(key: const Key('pf_name'), label: _t('name'), value: add(prof.name), valueColor: addC(prof.name), onTap: () => _editText('name', prof.name, (s) => _save(prof.copyWith(name: s)), hint: _t('name_hint'))),
      PRow(key: const Key('pf_dob'), label: _t('dob'), value: prof.dob == null ? _t('add') : shortDateIn(lang, prof.dob!), valueColor: addC(prof.dob), onTap: () => _pickDob(prof)),
      PRow(key: const Key('pf_gender'), label: _t('gender'), value: prof.gender == null ? _t('add') : _t('g_${prof.gender!.name}'), valueColor: addC(prof.gender),
          onTap: () => _pickEnum<Gender>('gender', Gender.values, prof.gender, (g) => _t('g_${g.name}'), (g) => _save(prof.copyWith(gender: g)))),
      PRow(key: const Key('pf_district'), label: _t('district'), value: add(prof.district), valueColor: addC(prof.district), onTap: () => _pickDistrict(prof)),
      PRow(key: const Key('pf_work'), label: _t('work'), value: add(prof.occupation), valueColor: addC(prof.occupation),
          onTap: () => _editText('work', prof.occupation, (s) => _save(prof.copyWith(occupation: s)), hint: _t('work_hint'))),
      PRow(key: const Key('pf_comfort'), label: _t('comfort'), value: prof.techComfort == null ? _t('add') : _t('c_${prof.techComfort!.name}'), valueColor: addC(prof.techComfort),
          onTap: () => _pickEnum<TechComfort>('comfort', TechComfort.values, prof.techComfort, (c) => _t('c_${c.name}'), (c) => _save(prof.copyWith(techComfort: c)))),
      PRow(key: const Key('pf_phone'), label: _t('phone'), value: add(prof.phone), valueColor: addC(prof.phone), last: true,
          onTap: () => _editText('phone', prof.phone, (s) => _save(prof.copyWith(phone: s)), phone: true)),
    ]);
  }

  Widget _family() {
    final th = Theme.of(context);
    final p = palOf(context);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final paired = _paired == true;
    final c = paired ? st.safe : p.accent;
    return Column(children: [
      Material(
        color: paired ? st.tint(RiskLabel.safe) : p.accentTint,
        borderRadius: BorderRadius.circular(RadX.card),
        child: InkWell(
          key: const Key('profile_family_pair'),
          borderRadius: BorderRadius.circular(RadX.card),
          onTap: () => _go(_t('family_code'), const FamilyScreen()),
          child: Padding(
            padding: const EdgeInsets.all(Sp.l),
            child: Row(children: [
              Icon(Icons.phonelink_lock_rounded, color: c, size: 30),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_t(paired ? 'paired' : 'not_paired'), style: th.textTheme.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 17)),
                  Text(_t(paired ? 'paired_s' : 'not_paired_s'), style: th.textTheme.bodySmall?.copyWith(color: c)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c),
            ]),
          ),
        ),
      ),
      const SizedBox(height: Sp.s + 2),
      ValueListenableBuilder<List<FamilyContact>>(
        valueListenable: ProfileStore.contacts,
        // Sized by its tallest tile, so a name or relation can take two lines at any text size.
        builder: (context, list, _) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < list.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: Sp.s + 2),
                  child: _contactTile(list[i], i, key: Key('family_contact_$i')),
                ),
              _addTile(),
            ]),
          ),
        ),
      ),
    ]);
  }

  static const _avatarColors = [Color(0xFF166F2E), Color(0xFF9A4500), Color(0xFF0066CC), Color(0xFF6E3FB0), Color(0xFF00707A)];

  Widget _contactTile(FamilyContact c, int i, {Key? key}) {
    final th = Theme.of(context);
    final p = palOf(context);
    final bg = _avatarColors[i % _avatarColors.length];
    return SizedBox(
      width: 112,
      child: PCard(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: Sp.s, vertical: Sp.m),
        onTap: () => _editContact(i),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: bg,
            child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
                style: th.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: th.textTheme.titleSmall),
          Text(c.relation, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
        ]),
      ),
    );
  }

  Widget _addTile() {
    final p = palOf(context);
    final th = Theme.of(context);
    return SizedBox(
      width: 112,
      child: PCard(
        key: const Key('family_contact_add'),
        padding: const EdgeInsets.symmetric(horizontal: Sp.s, vertical: Sp.m),
        onTap: () => _editContact(null),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 24, backgroundColor: p.accentTint, child: Icon(Icons.person_add_alt_1_rounded, color: p.accent)),
          const SizedBox(height: 6),
          Text(_t('add'), style: th.textTheme.titleSmall?.copyWith(color: p.accent)),
        ]),
      ),
    );
  }

  Widget _checks() {
    final th = Theme.of(context);
    final p = palOf(context);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final flags = [_prot?.call, _prot?.messages, _prot?.alerts];
    final on = flags.where((f) => f == true).length;
    final m = _model;
    final name = m == null ? null : _catalog.where((c) => c.id == m.idIn(_catalog)).map((c) => c.name).firstOrNull;
    final aiLine = m == null
        ? '…'
        : m.ready
            ? _t('ai_ready')
            : m.status == 'LOADING'
                ? _t('ai_loading')
                : _t('ai_none');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: PCard(
            key: const Key('profile_perms'),
            onTap: () async {
              await openSetupPage(context);
              _refresh();
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_prot == null ? '…' : '$on / ${flags.length}',
                  style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: on == flags.length ? st.safe : st.suspicious)),
              const SizedBox(height: Sp.xs),
              Text(_t('perms_s'), style: th.textTheme.bodySmall?.copyWith(color: p.muted)),
            ]),
          ),
        ),
        const SizedBox(width: Sp.s + 2),
        Expanded(
          child: PCard(
            key: const Key('profile_model'),
            onTap: () => _go(_t('m_title'), const ModelPickerScreen()),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name ?? (m?.ready == true ? 'Gemma' : '—'), style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Sp.xs),
              Text(aiLine, style: th.textTheme.bodySmall?.copyWith(color: p.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _help(String lang) {
    final p = palOf(context);
    final st = Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
    void open(String key, String fallbackTitle, Widget page) =>
        widget.onOpen != null ? widget.onOpen!(key, page) : _go(fallbackTitle, page);
    return ValueListenableBuilder<bool>(
      valueListenable: DemoFlag.enabled,
      builder: (_, demo, _) => PGroup(children: [
        PRow(
          key: const Key('profile_report'),
          label: _t('report'),
          leading: IconBadge(icon: Icons.call_rounded, color: st.scam, size: 36, iconSize: 20),
          onTap: () => openReport(context),
        ),
        PRow(
          key: const Key('profile_family_code'),
          label: _t('family_code'),
          leading: IconBadge(icon: Icons.family_restroom_rounded, color: st.safe, size: 36, iconSize: 20),
          onTap: () => open('family', _t('family_code'), const FamilyScreen()),
        ),
        PRow(
          key: const Key('profile_recording'),
          label: _t('recording'),
          leading: IconBadge(icon: Icons.mic_rounded, color: p.accent, size: 36, iconSize: 20),
          onTap: () => open('recording_title', _t('recording'), const RecordingScreen()),
        ),
        PRow(
          key: const Key('profile_settings'),
          label: _t('settings'),
          leading: IconBadge(icon: Icons.settings_rounded, color: p.ink, size: 36, iconSize: 20),
          onTap: () => open('settings', _t('settings'), const SettingsScreen()),
          last: !demo,
        ),
        if (demo)
          PRow(
            key: const Key('tile_demo_lab'),
            label: _t('demo'),
            leading: IconBadge(icon: Icons.science_rounded, color: p.accent, size: 36, iconSize: 20),
            onTap: () => open('demo', _t('demo'), const DemoLabScreen()),
            last: true,
          ),
      ]),
    );
  }

  // ---- editors (island sheets) ----

  Future<void> _editText(String labelKey, String? current, Future<void> Function(String) onSave, {String? hint, bool phone = false}) async {
    final v = await showIslandSheet<String>(
      context,
      builder: (ctx) => _TextSheet(title: _t(labelKey), initial: current ?? '', hint: hint, phone: phone, saveLabel: _t('save')),
    );
    if (v != null && mounted) await onSave(v.trim());
  }

  Future<void> _pickDob(UserProfile prof) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: prof.dob ?? DateTime(now.year - 40),
      firstDate: DateTime(now.year - 110),
      lastDate: DateTime(now.year - 5),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d != null && mounted) await _save(prof.copyWith(dob: d));
  }

  Future<void> _pickEnum<T extends Enum>(String titleKey, List<T> values, T? current, String Function(T) label, Future<void> Function(T) onSave) async {
    final th = Theme.of(context);
    final p = palOf(context);
    final v = await showIslandSheet<T>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_t(titleKey), style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Sp.m),
        for (final e in values)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s),
            child: Material(
              color: e == current ? p.accentTint : p.page,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: Key('pf_opt_${e.name}'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.pop(ctx, e),
                child: Container(
                  constraints: const BoxConstraints(minHeight: kTouch),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.l),
                  child: Row(children: [
                    Expanded(child: Text(label(e), style: th.textTheme.titleMedium)),
                    if (e == current) Icon(Icons.check_rounded, color: p.accent),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
    if (v != null && mounted) await onSave(v);
  }

  Future<void> _pickDistrict(UserProfile prof) async {
    final th = Theme.of(context);
    final d = await showIslandSheet<String>(
      context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_t('district'), style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Sp.s),
          Expanded(
            child: ListView.builder(
              itemCount: kDistricts.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(kDistricts[i], style: th.textTheme.titleMedium),
                trailing: kDistricts[i] == prof.district ? Icon(Icons.check_rounded, color: palOf(ctx).accent) : null,
                onTap: () => Navigator.pop(ctx, kDistricts[i]),
              ),
            ),
          ),
        ]),
      ),
    );
    if (d != null && mounted) await _save(prof.copyWith(district: d));
  }

  Future<void> _editContact(int? index) async {
    final list = [...ProfileStore.contacts.value];
    final cur = index == null ? null : list[index];
    final r = await showIslandSheet<(String, FamilyContact?)>(
      context,
      builder: (ctx) => _ContactSheet(contact: cur, t: _t),
    );
    if (!mounted || r == null) return;
    final (action, c) = r;
    if (action == 'save' && c != null) {
      if (index == null) {
        list.add(c);
      } else {
        list[index] = c;
      }
      await ProfileStore.saveContacts(list);
    } else if (action == 'delete' && index != null) {
      list.removeAt(index);
      await ProfileStore.saveContacts(list);
    }
  }
}

/// One-field editor in an island sheet; owns its controller so it outlives the closing animation safely.
class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.title, required this.initial, required this.saveLabel, this.hint, this.phone = false});
  final String title, initial, saveLabel;
  final String? hint;
  final bool phone;
  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Sp.m),
        TextField(
          key: const Key('pf_text_field'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: widget.phone ? TextInputType.phone : TextInputType.text,
          textCapitalization: widget.phone ? TextCapitalization.none : TextCapitalization.words,
          decoration: InputDecoration(hintText: widget.hint),
          onSubmitted: (s) => Navigator.pop(context, s),
        ),
        const SizedBox(height: Sp.l),
        FilledButton(key: const Key('pf_save'), onPressed: () => Navigator.pop(context, _ctrl.text), child: Text(widget.saveLabel)),
      ]),
    );
  }
}

/// Add / edit one family contact; pops ('save', contact), ('delete', null) or nothing.
class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.contact, required this.t});
  final FamilyContact? contact;
  final String Function(String key, [Map<String, Object?> args]) t;
  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _rel = TextEditingController(text: widget.contact?.relation ?? '');
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _rel.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop<(String, FamilyContact?)>(context, (
      'save',
      FamilyContact(
        name: _name.text.trim(),
        relation: _rel.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final st = th.extension<StatusColors>() ?? StatusColors.light;
    final t = widget.t;
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t(widget.contact == null ? 'add_member' : 'edit_member').replaceFirst('+ ', ''),
            style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Sp.m),
        TextField(key: const Key('fc_name'), controller: _name, autofocus: widget.contact == null, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t('member_name'))),
        const SizedBox(height: Sp.s),
        TextField(key: const Key('fc_rel'), controller: _rel, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: t('relation'), hintText: t('rel_hint'))),
        const SizedBox(height: Sp.s),
        TextField(key: const Key('fc_phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('phone'))),
        const SizedBox(height: Sp.l),
        FilledButton(key: const Key('fc_save'), onPressed: _save, child: Text(t('save'))),
        if (widget.contact != null)
          TextButton(
            key: const Key('fc_delete'),
            style: TextButton.styleFrom(foregroundColor: st.scam),
            onPressed: () => Navigator.pop<(String, FamilyContact?)>(context, ('delete', null)),
            child: Text(t('delete')),
          ),
      ]),
    );
  }
}
