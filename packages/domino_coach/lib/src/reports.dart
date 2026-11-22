import 'package:domino_api/domino_api.dart';

/// How certain the coach is that the decision was wrong.
enum MistakeClass {
  /// Worse in ALL sampled consistent worlds.
  provenMistake,

  /// Clearly lower expected value.
  weakerMove,

  /// Better by probability only (small but consistent EV gap).
  betterEstimate,
}

extension MistakeClassAr on MistakeClass {
  String get nameAr => switch (this) {
        MistakeClass.provenMistake => 'غلطة مؤكدة',
        MistakeClass.weakerMove => 'نقلة أضعف',
        MistakeClass.betterEstimate => 'تقدير أفضل بالاحتمالات',
      };
}

/// Educational categories (as specified).
enum MistakeCategory {
  wrongTile,
  wrongDrawEnd,
  missedBetterPlay,
  keptHighPips,
  gaveOpponentAdvantage,
  openedUnfavorableNumber,
  missedBlock,
  poorTileManagement,
  poorEndgame,
  badProbabilityEstimate,
}

extension MistakeCategoryAr on MistakeCategory {
  String get nameAr => switch (this) {
        MistakeCategory.wrongTile => 'حجر غلط',
        MistakeCategory.wrongDrawEnd => 'طرف سحب غلط',
        MistakeCategory.missedBetterPlay => 'فاتتك نقلة أحسن',
        MistakeCategory.keptHighPips => 'مسكت أحجار تقيلة',
        MistakeCategory.gaveOpponentAdvantage => 'ديت الخصم أفضلية',
        MistakeCategory.openedUnfavorableNumber => 'فتحت رقم مش في صالحك',
        MistakeCategory.missedBlock => 'فاتتك فرصة قفلة',
        MistakeCategory.poorTileManagement => 'إدارة أحجار ضعيفة',
        MistakeCategory.poorEndgame => 'نهاية جولة ضعيفة',
        MistakeCategory.badProbabilityEstimate => 'تقدير احتمالات غلط',
      };
}

/// A single structured coaching finding.
class MistakeReport {
  final MistakeCategory category;
  final MistakeClass severity;

  /// Machine reason code (drives the Arabic template rendering).
  final String reasonCode;

  /// What the player decided.
  final DominoAction chosen;

  /// The better decision.
  final DominoAction alternative;

  /// Expected advantage lost, in EV points.
  final double expectedAdvantage;

  /// Fraction of sampled worlds where the chosen action was worse.
  final double worseFraction;

  /// Extra named values for the template (tile, number, ends, ...).
  final Map<String, Object?> context;

  /// Round / ply for reference.
  final int round;
  final int ply;

  const MistakeReport({
    required this.category,
    required this.severity,
    required this.reasonCode,
    required this.chosen,
    required this.alternative,
    required this.expectedAdvantage,
    required this.worseFraction,
    required this.context,
    required this.round,
    required this.ply,
  });

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'severity': severity.name,
        'reasonCode': reasonCode,
        'chosen': chosen.toString(),
        'alternative': alternative.toString(),
        'expectedAdvantage': expectedAdvantage,
        'worseFraction': worseFraction,
        'round': round,
        'ply': ply,
      };
}
