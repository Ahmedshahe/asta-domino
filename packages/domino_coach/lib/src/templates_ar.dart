import 'package:domino_api/domino_api.dart';

import 'reports.dart';

/// Egyptian number names for natural explanations.
const _nums = ['صفر', 'واحد', 'اتنين', 'تلاتة', 'أربعة', 'خمسة', 'ستة'];

String tileAr(Tile? t) => t == null ? 'حجر' : '[${t.lo}|${t.hi}]';
String numAr(int? n) => n == null ? '' : _nums[n];
String sideAr(DrawSide? s) =>
    s == DrawSide.front ? 'أول الصف' : 'آخر الصف';
String endAr(ChainEnd? e) => e == ChainEnd.left ? 'الشمال' : 'اليمين';

/// Renders [MistakeReport]s into Egyptian Arabic explanations.
///
/// Templates are driven by the reason code (no free-form guessing): each
/// template states WHAT happened, WHY the alternative is better, and the
/// real strategic reason.
class EgyptianTemplates {
  const EgyptianTemplates._();

  /// One-line summary (for lists).
  static String short(MistakeReport r) {
    final cat = r.category.nameAr;
    return '$cat — ${r.severity.nameAr} (فقدت تقريباً ${r.expectedAdvantage.toStringAsFixed(0)} نقطة متوقعة)';
  }

  /// Full explanation for the review screen.
  static String explain(MistakeReport r) {
    final chosenTile = r.context['chosenTile'];
    final bestTile = r.context['bestTile'];
    switch (r.reasonCode) {
      case 'drawEnd.playableTile':
        return 'أنت اخترت تسحب من ${sideAr((r.chosen as ChooseDrawEnd).side)}، '
            'لكن كان الأفضل تسحب من ${sideAr((r.alternative as ChooseDrawEnd).side)}.\n'
            'ليه؟ لأن الحجر اللي على ${sideAr((r.alternative as ChooseDrawEnd).side)} '
            'هو ${tileAr(bestTile as Tile?)} وكان قابل للّعب على طول، فكنت هتوقف السحب بسرعة '
            'وتلعبه فوراً بدل ما تكبّر إيدك بأحجار زيادة. '
            'اختيارك قلل فرصك في التحكم في اللعب.';
      case 'drawEnd.synergy':
        return 'أنت اخترت تسحب من ${sideAr((r.chosen as ChooseDrawEnd).side)}، '
            'لكن كان الأفضل تسحب من ${sideAr((r.alternative as ChooseDrawEnd).side)}.\n'
            'ليه؟ لأن الحجر ${tileAr(bestTile as Tile?)} اللي على ${sideAr((r.alternative as ChooseDrawEnd).side)} '
            'بي complement الأرقام اللي في إيدك (عندك منها أحجار كتير)، '
            'فكان هيساعدك تفضل قادر تلعب وتتخلص من رقم عندك منه أحجار كتير. '
            'الحجر اللي اخترته ${tileAr(chosenTile as Tile?)} مش بيساعد إيدك بنفس الشكل.';
      case 'play.missedBlock':
        final n = r.context['blockedNumber'];
        return 'كان ممكن تقفل رقم ${numAr(n as int?)} على الخصم.\n'
            'من اللي حصل قبل كده، الخصم غالباً ميعندوش رقم ${numAr(n)}، '
            'فلو لعبت ${tileAr((r.alternative as PlayTile).tile)} كنت هتخليه يسحب '
            'أو يعدّي، وتكبر إيده وتقلل فرصته. نقالتك سابتله اللعب مفتوح.';
      case 'play.wrongEnd':
        return 'نفس الحجر ${tileAr((r.chosen as PlayTile).tile)} كان الأفضل يتلعب '
            'على طرف ${endAr((r.alternative as PlayTile).end)} مش ${endAr((r.chosen as PlayTile).end)}.\n'
            'ليه؟ لأن الطرف اللي هتسيبه مفتوح بيفرق: الأفضل يفضل عندك أحجار '
            'بتغطي الطرفين الجداد عشان ميتقفلش عليك الدور الجاي.';
      case 'play.keptHighPips':
        return 'لعبت ${tileAr((r.chosen as PlayTile).tile)} وسيبت أحجار تقيلة في إيدك.\n'
            'كان الأفضل تلعب ${tileAr((r.alternative as PlayTile).tile)} '
            '(${r.context['couldDump']} نقطة) عشان تتخلص من النقط التقيلة بدري. '
            'لو الجولة اتقفلت (القفلة) وإيدك مليانة نقط عالية، هتخسرها كلها.';
      case 'play.dumpEndgame':
        return 'في نهاية الجولة، الأولوية الأولى هي تقليل نقط إيدك.\n'
            'كان الأفضل تلعب ${tileAr((r.alternative as PlayTile).tile)} بدل '
            '${tileAr((r.chosen as PlayTile).tile)}، لأن كل نقطة بتفضل في إيدك '
            'ممكن تتحسب عليك لو حصلت قفلة.';
      case 'play.openedStrong':
        final n = r.context['strongNumber'];
        return 'فتحت طرف برقم ${numAr(n as int?)}، والخصم شكله مرتاح للرقم ده '
            '(لعبه كتير قبل كده).\n'
            'كأنك بتقدمله لعبة سهلة. كان الأفضل ${tileAr((r.alternative as PlayTile).tile)} '
            'عشان متفتحش عليه رقم هو مسيطر عليه.';
      case 'play.openedUnfavorable':
        final n = r.context['unfavorableNumber'];
        return 'فتحت رقم ${numAr(n as int?)} والاحتمالات بتقول إن الخصم غالباً معاه.\n'
            'كان الأفضل تقفل على رقم تاني نادر في الأحجار الباقية. '
            'دي غلطة احتمالات: الرقم اللي فتحته متوقع يكون مع الخصم.';
      case 'play.lostCoverage':
        return 'نقالتك قللت تنوع الأرقام في إيدك (خسرت تغطية ${r.context['coverageLost']} أرقام).\n'
            'اللي بيحصل بعد كده: سهلة تتقفل عليك وتضطر تسحب. '
            'كان الأفضل ${tileAr((r.alternative as PlayTile).tile)} عشان تفضل مغطي أرقام أكتر.';
      case 'play.wrongTile':
        return '${tileAr((r.alternative as PlayTile).tile)} كان أحسن من '
            '${tileAr((r.chosen as PlayTile).tile)} في الموقف ده.\n'
            'الفرق مش ضخم لكنه ثابت عبر معظم الاحتمالات: النقلة الأحسن بتوازن '
            'بين التخلص من النقط، وتغطية الأرقام، وعدم فتح اللعب للخصم.';
      default:
        return 'كان في نقلة أفضل بالاحتمالات. المتوقع إن البديل كان هيديك '
            '${r.expectedAdvantage.toStringAsFixed(0)} نقطة أكتر في المتوسط.';
    }
  }
}
