import 'package:domino_ai/domino_ai.dart';
import 'package:simulations/arena.dart';
import 'package:test/test.dart';

/// AI strength regression tests — enforce the ACCEPTANCE CRITERIA agreed in
/// RULES.md §10 (2026-11-19), which replace the original infeasible "95% vs
/// random" target:
///
///   1. Master ≥ 75% vs Random over the fixed-seed 1000-round benchmark
///      (regression floor; measured 76.5% at introduction).
///   2. Strict ordering Master > Professional > Skilled > Casual > Beginner,
///      with Beginner ≡ Random by construction (parity ~45–55%).
///   3. Fairness is non-negotiable (see the no-cheat isolation test in
///      domino_ai); nothing here may be "fixed" by leaking hidden info.
///
/// All matchups use fixed seeds (runMatchup default seedBase=1000 and the
/// per-game AI seeds below), so results are deterministic for a given code
/// revision. Master tests are slow (determinization Monte Carlo) and carry
/// generous timeouts.
void main() {
  DominoAI Function() masterFactory(int i) => () => DominoAI(AiConfig(
      level: AiLevel.master,
      masterDeterminizations: 150,
      seed: i * 7 + 1));

  test(
    'Master beats Random in >= 75% of 1000 fixed-seed rounds',
    () {
      final r = runMatchup(
        rounds: 1000,
        makeA: (i) => masterFactory(i)().choose,
        makeB: (i) => randomPlayer(i * 31 + 5),
      );
      // ignore: avoid_print
      print('MASTER vs random: $r');
      expect(r.winRateA, greaterThanOrEqualTo(0.75),
          reason: 'regression floor is 75% (RULES.md §10.1); got $r');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'Master beats Professional head-to-head (500 fixed-seed rounds)',
    () {
      final r = runMatchup(
        rounds: 500,
        makeA: (i) => masterFactory(i)().choose,
        makeB: (i) =>
            DominoAI(AiConfig(level: AiLevel.professional, seed: i * 31 + 5))
                .choose,
      );
      // ignore: avoid_print
      print('MASTER vs professional: $r');
      expect(r.winRateA, greaterThan(0.5),
          reason: 'ordering Master > Professional must hold (RULES.md §10.2)');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'ordering Professional > Skilled > Casual > Beginner (1500 rounds each)',
    () {
      const pairs = [
        (AiLevel.professional, AiLevel.skilled),
        (AiLevel.skilled, AiLevel.casual),
        (AiLevel.casual, AiLevel.beginner),
      ];
      for (final (hi, lo) in pairs) {
        final r = runMatchup(
          rounds: 1500,
          makeA: (i) => DominoAI(AiConfig(level: hi, seed: i * 7 + 1)).choose,
          makeB: (i) => DominoAI(AiConfig(level: lo, seed: i * 31 + 5)).choose,
        );
        // ignore: avoid_print
        print('${hi.name} vs ${lo.name}: $r');
        expect(r.winRateA, greaterThan(0.5),
            reason: 'ordering ${hi.name} > ${lo.name} must hold '
                '(RULES.md §10.2); got $r');
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'Beginner stays at parity with Random (45%-55%, 1000 rounds)',
    () {
      final r = runMatchup(
        rounds: 1000,
        makeA: (i) => DominoAI(AiConfig(level: AiLevel.beginner, seed: i * 7 + 1)).choose,
        makeB: (i) => randomPlayer(i * 31 + 5),
      );
      // ignore: avoid_print
      print('BEGINNER vs random: $r');
      expect(r.winRateA, inInclusiveRange(0.45, 0.55),
          reason: 'Beginner IS the random baseline (RULES.md §10.2); '
              'a large drift means the level definitions changed; got $r');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
