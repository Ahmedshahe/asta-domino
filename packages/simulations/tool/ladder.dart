import 'package:domino_ai/domino_ai.dart';
import 'package:simulations/arena.dart';

void main(List<String> args) {
  var rounds = 300;
  var det = 60;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--rounds') rounds = int.parse(args[i + 1]);
    if (args[i] == '--det') det = int.parse(args[i + 1]);
  }
  print('ladder vs RANDOM, $rounds rounds each, master det=$det');
  for (final lvl in [
    AiLevel.casual,
    AiLevel.skilled,
    AiLevel.professional,
  ]) {
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => DominoAI(AiConfig(level: lvl, seed: i * 7 + 1)).choose,
      makeB: (i) => randomPlayer(i * 31 + 5),
    );
    print('${lvl.name.padRight(13)} vs random: $r');
  }
  for (final om in [RolloutOpponent.strong, RolloutOpponent.random]) {
    final mvr = runMatchup(
      rounds: rounds,
      makeA: (i) => DominoAI(AiConfig(
              level: AiLevel.master,
              masterDeterminizations: det,
              seed: i * 7 + 1,
              masterOppModel: om))
          .choose,
      makeB: (i) => randomPlayer(i * 31 + 5),
    );
    print('master(${om.name}) vs random: $mvr');
  }
}
