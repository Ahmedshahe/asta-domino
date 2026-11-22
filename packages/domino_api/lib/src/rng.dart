/// Deterministic, platform-safe RNG (xorshift32).
///
/// All intermediate values stay below 2^45, so results are bit-identical on
/// the native VM and on the web (where ints are backed by doubles).
class Rng {
  int _state;

  Rng(int seed) : _state = _normalize(seed);

  static int _normalize(int seed) {
    var s = seed & 0x7FFFFFFF;
    if (s == 0) s = 0x1F2E3D4C;
    return s;
  }

  /// The current internal state (for immutable state snapshots).
  int get state => _state;

  /// Restore an RNG to a previously captured [state].
  factory Rng.fromState(int state) => Rng._fromState(state);
  Rng._fromState(this._state);

  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0x7FFFFFFF;
    x ^= (x >> 17) & 0x7FFFFFFF;
    x ^= (x << 5) & 0x7FFFFFFF;
    _state = x & 0x7FFFFFFF;
    if (_state == 0) _state = 0x1F2E3D4C;
    return _state;
  }

  /// Uniform integer in [0, n).
  int nextInt(int n) => nextUint32() % n;

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 2147483648.0;

  /// In-place Fisher–Yates shuffle (deterministic given the seed).
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  T pick<T>(List<T> items) => items[nextInt(items.length)];
}
