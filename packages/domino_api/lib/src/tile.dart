/// A domino tile from a double-six set. Normalized so that [lo] <= [hi].
class Tile {
  final int lo;
  final int hi;

  const Tile._(this.lo, this.hi);

  /// Const constructor for already-normalized values (lo <= hi).
  const Tile.sorted(this.lo, this.hi) : assert(lo <= hi, 'use lo <= hi');

  factory Tile(int a, int b) {
    assert(a >= 0 && a <= 6 && b >= 0 && b <= 6, 'Tile values must be 0..6');
    return a <= b ? Tile._(a, b) : Tile._(b, a);
  }

  /// Canonical id in [0, 28): tiles ordered as (0,0),(0,1),...,(0,6),(1,1),...
  int get id {
    var before = 7 * lo - (lo * (lo - 1)) ~/ 2;
    return before + (hi - lo);
  }

  static Tile fromId(int id) {
    assert(id >= 0 && id < 28);
    for (var lo = 0; lo <= 6; lo++) {
      final count = 7 - lo;
      final before = 7 * lo - (lo * (lo - 1)) ~/ 2;
      if (id < before + count) {
        return Tile._(lo, lo + (id - before));
      }
    }
    throw StateError('unreachable');
  }

  int get pips => lo + hi;
  bool get isDouble => lo == hi;
  bool has(int n) => lo == n || hi == n;

  /// The "other" value when one side equals [n]. Throws if the tile lacks [n].
  int other(int n) {
    if (lo == n) return hi;
    if (hi == n) return lo;
    throw ArgumentError('Tile $this does not contain $n');
  }

  @override
  bool operator ==(Object other) =>
      other is Tile && other.lo == lo && other.hi == hi;

  @override
  int get hashCode => lo * 8 + hi;

  @override
  String toString() => '[$lo|$hi]';
}

/// The 28 tiles of a double-six set, in canonical order.
final List<Tile> kAllTiles = List.unmodifiable(
  List.generate(28, Tile.fromId),
);

/// A tile as placed in the chain: [left] is the value on its left side,
/// [right] the value on its right side, as it lies from the left open end
/// to the right open end of the chain.
class PlacedTile {
  final Tile tile;
  final int left;
  final int right;

  const PlacedTile(this.tile, this.left, this.right);

  bool get isDouble => tile.isDouble;

  @override
  bool operator ==(Object other) =>
      other is PlacedTile &&
      other.tile == tile &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(tile, left, right);

  @override
  String toString() => '<$left:$right>';
}
