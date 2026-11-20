// Pure tracker logic, ported from app-core.js: no widgets, network or global state.
// test/core_test.dart checks it with the same cases the website relies on.

class Subsection {
  Subsection({required this.id, required this.code, required this.title, required this.covered, required this.date, required this.notes});

  factory Subsection.fromJson(Map<String, dynamic> json) => Subsection(
        id: json['id'] as int,
        code: json['code'] as String,
        title: json['title'] as String,
        covered: json['covered'] as bool,
        date: json['date'] as String,
        notes: json['notes'] as String,
      );

  final int id;
  final String code;
  final String title;
  bool covered;
  String date;
  String notes;

  Map<String, dynamic> toPatch() => {'covered': covered, 'date': date, 'notes': notes};
}

class Regulation {
  Regulation({required this.id, required this.heading, required this.isLocked, required this.subsections});

  factory Regulation.fromJson(Map<String, dynamic> json) => Regulation(
        id: json['id'] as int,
        heading: json['regulation'] as String,
        isLocked: json['isLocked'] as bool,
        subsections: [for (final item in json['subsections'] as List) Subsection.fromJson(item as Map<String, dynamic>)],
      );

  final int id;
  String heading;
  final bool isLocked;
  final List<Subsection> subsections;
}

enum CoverageFilter { all, uncovered, covered }

final _sectionNumberPattern = RegExp(r'^\s*(\d+\.\d+)');

/// "91.103 — Preflight action" -> "91.103", or null when the heading doesn't start with a number.
String? sectionNumber(String heading) => _sectionNumberPattern.firstMatch(heading)?.group(1);

String ecfrUrl(String part, String section, [String code = '']) {
  final url = 'https://www.ecfr.gov/current/title-14/part-$part/section-$section';
  return code.isEmpty ? '$url#section-$section' : '$url#p-$section($code)';
}

/// "91.103(a)", "91.5" for an entire-section item, or the heading itself when it has no section number.
String referenceFor(String heading, String code) {
  final number = sectionNumber(heading);
  if (number == null) return heading;
  return code.isEmpty ? number : '$number($code)';
}

String normalizeQuery(String value) => value.trim().toLowerCase();

/// The regulation's subsections that pass the filter and match the (already normalized) query.
List<Subsection> matchingSubsections(Regulation regulation, String query, CoverageFilter filter) {
  final regulationMatches = regulation.heading.toLowerCase().contains(query);
  return regulation.subsections.where((subsection) {
    final matchesFilter = switch (filter) {
      CoverageFilter.all => true,
      CoverageFilter.covered => subsection.covered,
      CoverageFilter.uncovered => !subsection.covered,
    };
    final text = '${referenceFor(regulation.heading, subsection.code)} ${subsection.title} ${subsection.notes}'.toLowerCase();
    return matchesFilter && (query.isEmpty || regulationMatches || text.contains(query));
  }).toList();
}

class Summary {
  const Summary({required this.total, required this.covered, required this.remaining, required this.progress});
  final int total;
  final int covered;
  final int remaining;
  final int progress;
}

Summary summarize(Iterable<Subsection> subsections) {
  final total = subsections.length;
  final covered = subsections.where((item) => item.covered).length;
  return Summary(
    total: total,
    covered: covered,
    remaining: total - covered,
    progress: total == 0 ? 0 : (covered / total * 100).round(),
  );
}

/// YYYY-MM-DD in the device's local time zone (not UTC).
String localDate([DateTime? now]) {
  final date = (now ?? DateTime.now()).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}
