import 'package:far_notes/core.dart';
import 'package:flutter_test/flutter_test.dart';

Subsection item(String code, {bool covered = false, String notes = '', String title = ''}) =>
    Subsection(id: code.hashCode, code: code, title: title, covered: covered, date: '', notes: notes);

void main() {
  final preflight = Regulation(id: 1, heading: '91.103 — Preflight action', isLocked: true, subsections: [
    item('a', title: 'For a flight under IFR or not in the vicinity of an airport', covered: true),
    item('b', notes: 'runway lengths'),
  ]);

  test('sectionNumber reads the number at the start of a heading', () {
    expect(sectionNumber('91.103 — Preflight action'), '91.103');
    expect(sectionNumber('  61.56 Flight review'), '61.56');
    expect(sectionNumber('Preflight 91.103'), isNull);
  });

  test('referenceFor adds the paragraph code, or falls back to the heading', () {
    expect(referenceFor('91.103 — Preflight action', 'a'), '91.103(a)');
    expect(referenceFor('91.5 — Pilot in command', ''), '91.5');
    expect(referenceFor('My own topic', ''), 'My own topic');
  });

  test('ecfrUrl links a section or one of its paragraphs', () {
    expect(ecfrUrl('91', '91.103'), 'https://www.ecfr.gov/current/title-14/part-91/section-91.103#section-91.103');
    expect(ecfrUrl('91', '91.103', 'a'), 'https://www.ecfr.gov/current/title-14/part-91/section-91.103#p-91.103(a)');
  });

  test('matchingSubsections filters by coverage and searches references, titles and notes', () {
    expect(matchingSubsections(preflight, '', CoverageFilter.all), hasLength(2));
    expect(matchingSubsections(preflight, '', CoverageFilter.covered).single.code, 'a');
    expect(matchingSubsections(preflight, '', CoverageFilter.uncovered).single.code, 'b');
    expect(matchingSubsections(preflight, normalizeQuery(' RUNWAY '), CoverageFilter.all).single.code, 'b');
    expect(matchingSubsections(preflight, '91.103(a)', CoverageFilter.all).single.code, 'a');
    // A heading match shows every item in the section.
    expect(matchingSubsections(preflight, 'preflight', CoverageFilter.all), hasLength(2));
    expect(matchingSubsections(preflight, 'altimeter', CoverageFilter.all), isEmpty);
  });

  test('summarize counts covered items and rounds the percentage', () {
    final summary = summarize([item('a', covered: true), item('b'), item('c')]);
    expect([summary.total, summary.covered, summary.remaining, summary.progress], [3, 1, 2, 33]);
    expect(summarize([]).progress, 0);
  });

  test('localDate formats the local calendar date', () {
    expect(localDate(DateTime(2026, 3, 7, 23, 30)), '2026-03-07');
  });
}
