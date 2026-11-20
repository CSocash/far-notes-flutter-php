import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../core.dart';
import '../save_queue.dart';
import '../theme.dart';
import 'login.dart';

/// The study tracker: one part (61 or 91) at a time, sections that open to show their lettered
/// subsections, and autosaved coverage, dates and notes.
///
/// Accessibility labels match the website's ("Study items in `heading`", "Mark 91.103(a) as covered",
/// "Notes for 91.103(a)"), so Appium finds the same names Playwright does.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key, required this.api, required this.username});
  final FarNotesApi api;
  final String username;

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

enum _LoadState { loading, connected, failed }

class _TrackerScreenState extends State<TrackerScreen> {
  final _saves = SaveQueue();
  final _search = TextEditingController();
  List<Regulation> _regulations = [];
  String _part = '91';
  CoverageFilter _filter = CoverageFilter.all;
  _LoadState _loadState = _LoadState.loading;
  int _loadSequence = 0;
  // Sections start collapsed. _expanded holds the ids the user opened. While a search is active,
  // sections with matches open automatically, and _searchCollapsed holds the ones closed during it.
  Set<int> _expanded = {};
  Set<int> _searchCollapsed = {};

  @override
  void initState() {
    super.initState();
    _loadPart(_part);
  }

  @override
  void dispose() {
    _saves.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _query => normalizeQuery(_search.text);

  Future<void> _loadPart(String part) async {
    final sequence = ++_loadSequence;
    setState(() {
      _part = part;
      _regulations = [];
      _expanded = {};
      _searchCollapsed = {};
      _loadState = _LoadState.loading;
    });
    try {
      final regulations = await widget.api.regulations(part);
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _regulations = regulations;
        _loadState = _LoadState.connected;
      });
    } on ApiException catch (error) {
      if (!mounted || sequence != _loadSequence) return;
      if (error.status == 401) return _goToSignIn();
      setState(() => _loadState = _LoadState.failed);
      _toast('Could not load regulations: ${error.message}');
    }
  }

  void _goToSignIn() {
    Navigator.of(context)
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)), (_) => false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2400)));
  }

  void _onSaveError(String what, Object error) {
    if (!mounted) return;
    if (error is ApiException && error.status == 401) return _goToSignIn();
    _toast('Could not save $what: $error');
  }

  void _saveSubsection(Subsection subsection, {bool immediate = false}) {
    final part = _part;
    _saves.queue('subsection:${subsection.id}', () => widget.api.saveSubsection(part, subsection),
        immediate: immediate, onError: (error) => _onSaveError('study item', error));
  }

  void _saveHeading(Regulation regulation) {
    final part = _part;
    _saves.queue('regulation:${regulation.id}', () => widget.api.saveHeading(part, regulation),
        immediate: true, onError: (error) => _onSaveError('section', error));
  }

  bool _isExpanded(Regulation regulation) =>
      _query.isNotEmpty ? !_searchCollapsed.contains(regulation.id) : _expanded.contains(regulation.id);

  void _toggle(Regulation regulation) {
    setState(() {
      final sections = _query.isNotEmpty ? _searchCollapsed : _expanded;
      if (!sections.remove(regulation.id)) sections.add(regulation.id);
    });
  }

  void _setAll(bool expand) {
    setState(() {
      final ids = {for (final regulation in _regulations) regulation.id};
      if (_query.isNotEmpty) {
        _searchCollapsed = expand ? {} : ids;
      } else {
        _expanded = expand ? ids : {};
      }
    });
  }

  void _setCovered(Regulation regulation, Subsection subsection, bool covered) {
    setState(() {
      subsection.covered = covered;
      subsection.date = covered ? localDate() : '';
    });
    _saveSubsection(subsection, immediate: true);
  }

  Future<void> _pickDate(Subsection subsection) async {
    final current = DateTime.tryParse(subsection.date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Date covered',
    );
    if (picked == null || !mounted) return;
    setState(() => subsection.date = localDate(picked));
    _saveSubsection(subsection, immediate: true);
  }

  void _clearDate(Subsection subsection) {
    setState(() => subsection.date = '');
    _saveSubsection(subsection, immediate: true);
  }

  Future<void> _editHeading(Regulation regulation) async {
    final controller = TextEditingController(text: regulation.heading);
    final heading = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Section heading'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Regulation section', hintText: '91.103 — Preflight action'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (heading == null || heading == regulation.heading || !mounted) return;
    setState(() => regulation.heading = heading);
    _saveHeading(regulation);
  }

  Future<void> _addSection() async {
    try {
      final regulation = await widget.api.addRegulation(_part);
      if (!mounted) return;
      setState(() {
        _regulations.add(regulation);
        _expanded.add(regulation.id);
        _filter = CoverageFilter.all;
        _search.clear();
      });
      _toast('New section added. Enter a regulation number to get started.');
      await _editHeading(regulation);
    } on ApiException catch (error) {
      if (mounted) _toast('Could not add section: ${error.message}');
    }
  }

  Future<void> _signOut() async {
    await _saves.flush();
    try {
      await widget.api.signOut();
    } on ApiException catch (_) {
      // The saved token is gone either way; the server session expires on its own.
    }
    if (mounted) _goToSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = [for (final regulation in _regulations) ...regulation.subsections];
    final summary = summarize(allItems);
    final query = _query;
    final groups = [
      for (final regulation in _regulations)
        (regulation: regulation, items: matchingSubsections(regulation, query, _filter)),
    ].where((group) => group.items.isNotEmpty).toList();
    final visibleCount = groups.fold<int>(0, (count, group) => count + group.items.length);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Brand(suffix: 'PART $_part'),
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Log out')),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadState == _LoadState.connected ? _addSection : null,
        icon: const Icon(Icons.add),
        label: const Text('Add section'),
      ),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.list(children: [
              _header(summary),
              const SizedBox(height: 16),
              _toolbar(summary),
              const SizedBox(height: 12),
            ]),
          ),
          if (_loadState == _LoadState.failed || (_loadState == _LoadState.connected && visibleCount == 0))
            SliverToBoxAdapter(child: _emptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(children: [
                for (final group in groups) _section(group.regulation, group.items),
              ]),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            sliver: SliverToBoxAdapter(
              child: Text('Showing $visibleCount of ${summary.total} study items',
                  style: const TextStyle(color: muted, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(Summary summary) {
    final status = switch (_loadState) {
      _LoadState.loading => 'Loading regulations...',
      _LoadState.connected => 'Connected to SQLite',
      _LoadState.failed => 'Database unavailable',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '91', label: Text('Part 91')),
              ButtonSegment(value: '61', label: Text('Part 61')),
            ],
            selected: {_part},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              _filter = CoverageFilter.all;
              _search.clear();
              _loadPart(selection.first);
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.circle, size: 8, color: _loadState == _LoadState.failed ? errorRed : green),
        const SizedBox(width: 6),
        // Separate accessibility elements, so Appium finds the status text on its own.
        Semantics(container: true, child: Text(status, style: const TextStyle(color: muted, fontSize: 12))),
        const Spacer(),
        Semantics(container: true, child: Text(widget.username, style: const TextStyle(color: muted, fontSize: 12))),
      ]),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('OVERALL PROGRESS',
                  style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const Spacer(),
              Text('${summary.progress}%',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: ink)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: summary.progress / 100, minHeight: 6, color: green, backgroundColor: greenSoft),
            ),
            const SizedBox(height: 8),
            Text('${summary.covered} of ${summary.total} study items covered',
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
      ),
    ]);
  }

  Widget _toolbar(Summary summary) {
    Widget filterChip(CoverageFilter filter, String label, int count) => ChoiceChip(
          label: Text('$label $count'),
          selected: _filter == filter,
          onSelected: (_) => setState(() => _filter = filter),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        decoration: InputDecoration(
          labelText: 'Search regulations or notes',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _search.clear();
                    _searchCollapsed = {};
                  }),
                ),
        ),
        onChanged: (_) => setState(() => _searchCollapsed = {}),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 4, children: [
        filterChip(CoverageFilter.all, 'All', summary.total),
        filterChip(CoverageFilter.uncovered, 'To study', summary.remaining),
        filterChip(CoverageFilter.covered, 'Covered', summary.covered),
      ]),
      Row(children: [
        TextButton(onPressed: () => _setAll(true), child: const Text('Expand all')),
        TextButton(onPressed: () => _setAll(false), child: const Text('Collapse all')),
      ]),
    ]);
  }

  Widget _emptyState() {
    final failed = _loadState == _LoadState.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(children: [
        const Icon(Icons.search_off, color: muted, size: 32),
        const SizedBox(height: 8),
        Text(failed ? 'Database connection unavailable' : 'No study items found',
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 4),
        Text(
          failed
              ? 'Start the server, then pull down or switch parts to try again.'
              : 'Try another search, or add a regulation section to your list.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        if (failed) TextButton(onPressed: () => _loadPart(_part), child: const Text('Try again')),
      ]),
    );
  }

  Widget _section(Regulation regulation, List<Subsection> items) {
    final expanded = _isExpanded(regulation);
    final sectionSummary = summarize(regulation.subsections);
    final heading = regulation.heading.isEmpty ? 'New section' : regulation.heading;
    return Padding(
      key: ValueKey('section-${regulation.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                label: 'Study items in ${regulation.heading}',
                identifier: 'section-toggle-${regulation.id}',
                onTap: () => _toggle(regulation),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _toggle(regulation),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                    child: Row(children: [
                      Icon(expanded ? Icons.expand_more : Icons.chevron_right, color: green),
                      const SizedBox(width: 6),
                      Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w600, color: ink))),
                    ]),
                  ),
                ),
              ),
            ),
            if (!regulation.isLocked)
              TextButton(
                onPressed: () => _editHeading(regulation),
                child: Semantics(
                    label: 'Edit section heading ${regulation.heading}',
                    excludeSemantics: true,
                    child: const Text('Edit')),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Semantics(
                label: '${sectionSummary.covered}/${sectionSummary.total} covered',
                excludeSemantics: true,
                child: Text('${sectionSummary.covered}/${sectionSummary.total}',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ),
            ),
          ]),
          if (expanded)
            for (final subsection in items)
              _SubsectionTile(
                key: ValueKey('subsection-${subsection.id}'),
                regulation: regulation,
                subsection: subsection,
                onCovered: (covered) => _setCovered(regulation, subsection, covered),
                onPickDate: () => _pickDate(subsection),
                onClearDate: () => _clearDate(subsection),
                onNotes: (notes) {
                  subsection.notes = notes;
                  _saveSubsection(subsection);
                },
                onNotesDone: () => _saveSubsection(subsection, immediate: true),
              ),
        ]),
      ),
    );
  }
}

class _SubsectionTile extends StatefulWidget {
  const _SubsectionTile({
    super.key,
    required this.regulation,
    required this.subsection,
    required this.onCovered,
    required this.onPickDate,
    required this.onClearDate,
    required this.onNotes,
    required this.onNotesDone,
  });

  final Regulation regulation;
  final Subsection subsection;
  final ValueChanged<bool> onCovered;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final ValueChanged<String> onNotes;
  final VoidCallback onNotesDone;

  @override
  State<_SubsectionTile> createState() => _SubsectionTileState();
}

class _SubsectionTileState extends State<_SubsectionTile> {
  late final _notes = TextEditingController(text: widget.subsection.notes);
  final _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) widget.onNotesDone();
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subsection = widget.subsection;
    final reference = referenceFor(widget.regulation.heading, subsection.code);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(reference, style: const TextStyle(fontWeight: FontWeight.w700, color: green)),
        if (subsection.title.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subsection.title, style: const TextStyle(color: ink)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          // One accessibility element: a switch named like the website's checkbox, read as on/off.
          MergeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Semantics(
                label: 'Mark $reference as covered',
                identifier: 'covered-$reference',
                child: Switch(value: subsection.covered, onChanged: widget.onCovered),
              ),
              const SizedBox(width: 6),
              ExcludeSemantics(child: Text(subsection.covered ? 'Yes' : 'No', style: const TextStyle(color: muted))),
            ]),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Date covered for $reference',
            value: subsection.date.isEmpty ? 'Not set' : subsection.date,
            identifier: 'date-$reference',
            excludeSemantics: true,
            child: OutlinedButton.icon(
              onPressed: widget.onPickDate,
              icon: const Icon(Icons.event, size: 18),
              label: Text(subsection.date.isEmpty ? 'Date' : subsection.date),
            ),
          ),
          if (subsection.date.isNotEmpty)
            IconButton(
                tooltip: 'Clear date for $reference',
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClearDate),
        ]),
        const SizedBox(height: 8),
        Semantics(
          identifier: 'notes-$reference',
          child: TextField(
            controller: _notes,
            focusNode: _notesFocus,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(labelText: 'Notes for $reference', hintText: 'Add a note...', isDense: true),
            onChanged: widget.onNotes,
          ),
        ),
      ]),
    );
  }
}
