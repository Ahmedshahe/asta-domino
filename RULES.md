# RULES.md — Egyptian Domino Master (أسطى الدومينو)

Version 1.0 — Logic-first build. This document is the **source of truth** for the
rules implemented in `domino_engine`. Where this document and generic domino
literature disagree, **this document wins**.

---

## 1. Scope of this version

- **Mode implemented:** Egyptian Domino **1 vs 1** (one human vs one AI), match to **101 points**.
- Fully offline. No network, no cloud, no accounts.
- Simple temporary 2D UI (flat tiles with dots). Graphics/3D/sound come later on
  top of the same engine.

Rules documented but **not** implemented in v1: 2v2 team play (see §3.4), other
international variants beyond the notes below.

---

## 2. Terminology (common Egyptian café usage)

| Egyptian term | Meaning |
|---|---|
| حجر / بلاطة | a domino tile |
| دبل (e.g. دبل ستة) | a double tile (e.g. double-six) |
| صف السحب | the draw line (boneyard) — one horizontal line of face-down tiles |
| أول الصف / آخر الصف | the front / back end of the draw line |
| اسحب | draw a tile |
| باص / عدّي | pass (no move and line is empty) |
| القفلة | a blocked round (nobody can play, line empty) |
| دومينو! | declared when a player plays their last tile |
| قفل الرقم | blocking a number (making both ends a number the opponent lacks) |
| عدّ النقاط | pip counting / tile counting |
| أسطى / معلم | master (used in AI taunts) |

---

## 3. Rule variants

### 3.1 International "Draw Dominoes"
- Double-six set (28 tiles), 2 players × 7 tiles, remainder is the boneyard.
- A player who cannot play **must draw until they can play or the boneyard is empty**,
  then passes. Traditionally the boneyard is face-down and unordered; players draw
  blindly. The last two tiles are sometimes left undrawn (house rule, **not used here**).

### 3.2 International "Block Dominoes"
- Same deal, **no drawing at all**: a player who cannot play simply passes.
  Blocked game: lowest pip total wins, usually scoring the *difference* of totals.

### 3.3 Common Egyptian rules
Egyptian café play is a **Draw** variant with three signature differences:
1. The boneyard is a **single ordered horizontal line** (صف السحب), not a shuffled pile.
2. The **first player who must draw inspects both end tiles** of the line and
   **chooses which end** the whole round will draw from. That direction is then
   **fixed for both players for the rest of the round**.
3. Blocked game (القفلة): the lower hand wins and scores the opponent's
   **full** remaining pip total — **not** the difference (see §5).

### 3.4 2v2 (documented, not in v1)
Two teams of two, partners sit opposite. Usually 6 tiles each (4 tiles boneyard
in some houses, or 7 each with a 2-tile line is not standard — open question).
Round ends when one player goes out (their team wins) or on القفلة (team totals
compared). Communication about hands is forbidden. **Deferred to v2.**

---

## 4. Core rules implemented (SOURCE OF TRUTH)

1. **Set & deal:** standard double-six set, 28 unique tiles `[a|b]`, `0≤a≤b≤6`.
   Each player gets **7 tiles**; the remaining **14** form the draw line, in a
   fixed random order determined by the match seed.
2. **Opening:** the round starter may play **any** tile. No double is required.
3. **Playing:** a tile may be attached to either open end of the chain when one
   of its numbers matches that end. Doubles are placed crosswise (a purely
   visual convention; logically they behave like any tile). Playing the same
   tile on different ends counts as different actions. The first tile of an
   empty board is placed in a canonical orientation (low|high).
4. **The Egyptian draw system:**
   - The 14 leftover tiles are one ordered line. The **first** and **last**
     tiles of the line are shown to a player **at the moment they must draw**
     (and have not yet chosen a direction). House-rule toggle
     `alwaysRevealLineEnds` can reveal both ends at all times.
   - The **first** player who must draw chooses which end (`front` = first tile
     of the line, `back` = last tile) to draw from. This becomes the
     **fixed draw direction for the whole round, for both players**.
   - A player with no valid move, while the line is non-empty, must draw
     **one tile at a time from the fixed end**, and **stops immediately** when
     a playable tile appears; **that tile must be played** (on either end, if
     both are legal). Non-playable drawn tiles stay in hand.
   - If the line is empty and no tile is playable, the player **passes**.
   - Identical rules for human and AI.
5. **Turn structure:** a turn is: play one tile → turn passes; *or* choose draw
   end → draw… → play the forced tile → turn passes; *or* pass.
   Note (implementation fact): when you start a turn with no playable tile, the
   chain ends do not change while you draw, so the first playable tile you draw
   is the *only* playable tile in your hand — "must play it" is therefore
   enforced by ordinary legal-move computation, with no special state.
6. **Round end:**
   - **Going out (دومينو):** a player plays their last tile → wins the round.
   - **Blocked (القفلة):** the draw line is empty **and neither** player has a
     legal move. Checked after every action (including the draw that empties
     the line), so the round ends immediately without waiting for a pass.
7. **Scoring:**
   - Going out: winner scores the **full pip sum of the opponent's remaining hand**.
   - Blocked: the player with the **lower** pip total wins and scores the
     opponent's **full** total. Example: A=12, B=30 → **A scores 30** (not 18).
   - Equal totals on a blocked round → **draw, 0 points** (default;
     configurable, see `equalTotalsDraw`).
8. **Match:** first player to reach **101** match points (configurable
   `matchTarget`) wins the match. Scores may exceed the target.

---

## 5. Configurable defaults (`GameConfig`)

| Option | Default | Meaning |
|---|---|---|
| `matchTarget` | 101 | points to win the match |
| `tilesPerHand` | 7 | tiles dealt to each player |
| `equalTotalsDraw` | true | blocked round with equal pip totals → 0 points draw. If false → round is replayed, same starter, no points |
| `firstRoundStarter` | null | null → random (seeded); else 0/1 |
| `alwaysRevealLineEnds` | false | if true, both end tiles of the line are always visible |
| **Starter rule** | — | Round 1: random (seeded) or `firstRoundStarter`. Later rounds: **winner of the previous round starts**. After a drawn round: **same starter as before**. |

---

## 6. Determinism & fairness

- The engine is deterministic given an integer seed: same seed ⇒ same shuffle,
  same starter, same everything. RNG is a platform-safe 32-bit xorshift
  (`Rng`), identical results on VM and web.
- `GameState`/`MatchState` are immutable; `apply` returns new states.
- **Information hiding is structural:** the AI and coach packages depend only on
  `domino_api`, which contains **no** `GameState`. They receive `PlayerView`
  (own hand, board, draw-line size, end tiles only when the rules reveal them,
  opponent hand **size**, public action history). `TileDrawn` events are
  redacted (tile hidden) in the opponent's view. A test suite verifies
  (a) `domino_ai` has no import path to the engine and (b) identical views with
  different hidden states produce identical AI decisions.

---

## 7. Strategy concepts (implemented by AI & taught by the coach)

- **Tile counting:** 7 tiles of each number exist (0..6). Tracking played tiles
  + your hand tells you what can still exist in the line/opponent's hand.
- **Inference:** an opponent who passes or draws with ends `(a,b)` did not hold
  `a` or `b` at that moment. Later plays/draws relax this. The AI keeps
  "hard lacks" (most recent evidence) with an allowance for tiles drawn in
  earlier eras (documented approximation).
- **Blocking (قفل الرقم):** setting an open end to a number the opponent lacks
  forces them to draw or pass.
- **Suit control:** playing from your longest number-group keeps future options open.
- **Pip management:** high-pip tiles (6-6, 6-5…) are dangerous to hold into
  القفلة; dump them unless they serve control.
- **Draw-end choice:** the end tile you choose is *exactly* the first tile you
  will draw — prefer one that is immediately playable (stops the draw) or that
  matches numbers you already control.
- **Endgame:** with the line empty and small hands, minimizing your own pip
  exposure and forcing the opponent into القفلة dominates.
- **Probability:** unseen tiles are uniformly distributed *subject to*
  consistency with the public history; both the Master AI and the coach sample
  consistent worlds (determinization) and compare expected values.

---

## 8. Open questions (with chosen defaults)

| # | Question | Default chosen |
|---|---|---|
| OQ1 | When the drawn playable tile may go on *both* ends, may the player choose? | **Yes** — both `PlayTile` actions are legal. |
| OQ2 | Are line end tiles visible *between* draws, mid-round? | Only at a player's own draw decision (and the fixed-end tile before each `DrawOne`); `alwaysRevealLineEnds` toggles full visibility. |
| OQ3 | Equal-total blocked round: 0 points or replay? | **0 points draw** (`equalTotalsDraw=true`), replay available as house rule. |
| OQ4 | Does the round end instantly when the *draw* that empties the line leaves both players stuck? | **Yes**, blocked is checked after every action. |
| OQ5 | 2v2 deal size (6 vs 7 tiles)? | Deferred with the whole 2v2 mode to v2. |
| OQ6 | Is "دومينو" announced / does it affect scoring? | Purely ceremonial; shown in the UI, no scoring effect. |
| OQ7 | Must the drawn playable tile be played *even if another move looks better*? | Yes — and (see §4.5) no other tile can be playable at that moment anyway. |
| OQ8 | Original target "Master ≥95% vs Random over 1000 rounds" — achievable fairly? | **RESOLVED (2026-11-19): No.** A 1-ply *cheating* oracle caps at ~91.5% and 2-ply cheating expectimax at ~68%; a fair Master reaches ~75–79%. The gap is the price of hidden information, so ≥95% is unreachable without breaking the no-cheat constraint. **Revised acceptance criteria (§10).** |

---

## 9. Architecture summary

```
packages/
  domino_api/      contracts + pure table rules (NO GameState, NO Flutter)
  domino_engine/   MatchState, match flow, seeded RNG, PlayerView redaction
  domino_ai/       5-level AI (depends ONLY on domino_api)
  domino_coach/    mistake analysis, Egyptian-Arabic templates, memory, exercises
app/               temporary Flutter UI (Arabic RTL), talks to engine via public API
```

Public engine API (see README for details):

```dart
MatchState newMatch(int seed, [GameConfig config])
List<DominoAction> legalActions(MatchState state, int player)
({MatchState state, List<GameEvent> events}) apply(MatchState state, DominoAction action)
({MatchState state, List<GameEvent> events}) dealNextRound(MatchState state)
PlayerView playerView(MatchState state, int viewer)
```

Actions: `PlayTile(tile, end)`, `ChooseDrawEnd(side)`, `DrawOne()`, `Pass()`.
Events: `RoundStarted`, `TilePlayed`, `DrawEndChosen`, `TileDrawn` (redacted for
opponent), `TurnPassed`, `RoundEnded(reason, points)`, `MatchEnded`.

---

## 10. AI strength — ACCEPTANCE CRITERIA (replaces the original 95% target)

Agreed with the project owner on 2026-11-19:

1. **Master ≥ 75% vs Random** over the fixed-seed 1000-round benchmark
   (measured: **76.5%**). 75% is a *regression floor*: no later change may
   drop below it. Enforced by
   `packages/simulations/test/strength_regression_test.dart`.
2. **Strict strength ordering** in head-to-head sims (fixed seeds):
   `Master > Professional > Skilled > Casual > Beginner`, with **Beginner ≡
   Random by construction** (Beginner *is* the uniform-random baseline, so
   Beginner vs Random must stay at parity, ~45–55%).
   Measured (3000 rounds for adjacent levels, 1000 rounds for Master matchups):
   Master 66.2% > Professional · Professional 51.9% > Skilled ·
   Skilled 55.4% > Casual · Casual 51.9% > Beginner · Beginner 49.6% ≈ Random.
3. **Fairness is non-negotiable**: AI and Coach receive `PlayerView` only;
   the structural no-cheat isolation test must stay green. No cheating may be
   added to raise win rates.
4. **Ceiling documentation**: the reference cheating ceilings (1-ply oracle
   ~91.5%, 2-ply expectimax ~68%) are kept in the README as documentation of
   the hidden-information gap.
