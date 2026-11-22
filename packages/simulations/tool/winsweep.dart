import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:simulations/arena.dart';

void main() {
  const rounds = 400, det = 100;
  for (final wb in [10.0, 30.0, 100.0, 300.0]) {
    activeWinBonus = wb;
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => DominoAI(AiConfig(
              level: AiLevel.master,
              masterDeterminizations: det,
              seed: i * 7 + 1,
              masterOppModel: RolloutOpponent.random))
          .choose,
      makeB: (i) => randomPlayer(i * 31 + 5),
    );
    print('winBonus=$wb: ${(r.winRateA * 100).toStringAsFixed(1)}%');
  }
}
