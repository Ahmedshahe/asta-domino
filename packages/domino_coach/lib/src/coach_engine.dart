import 'analyzer.dart';
import 'classifier.dart';
import 'decisions.dart';
import 'memory.dart';
import 'reports.dart';
import 'templates_ar.dart';

/// The coach's public facade.
class CoachEngine {
  final DecisionAnalyzer analyzer;
  final MistakeClassifier classifier;
  final MistakeMemory memory;

  CoachEngine({
    this.analyzer = const DecisionAnalyzer(),
    this.classifier = const MistakeClassifier(),
    required this.memory,
  });

  /// Analyzes all recorded decisions of a finished match and returns the
  /// findings (sorted by expected advantage, biggest first).
  List<MistakeReport> analyzeMatch(DecisionLog log) {
    final reports = <MistakeReport>[];
    for (final p in log.points) {
      final analysis = analyzer.analyze(p, seed: p.ply * 31 + p.round * 7);
      final report = classifier.classify(analysis);
      if (report != null) reports.add(report);
    }
    reports.sort((a, b) => b.expectedAdvantage.compareTo(a.expectedAdvantage));
    return reports;
  }

  /// Analyzes and persists the findings into the mistake memory.
  List<MistakeReport> analyzeAndRecord(DecisionLog log) {
    final reports = analyzeMatch(log);
    memory.recordReports(
      reports,
      title: (r) => r.category.nameAr,
      whyWrong: EgyptianTemplates.explain,
      alternative: (r) => r.alternative.toString(),
    );
    return reports;
  }

  /// Renders a full explanation for one report.
  String explain(MistakeReport r) => EgyptianTemplates.explain(r);

  /// Renders a one-line summary.
  String summarize(MistakeReport r) => EgyptianTemplates.short(r);
}
