/// domino_api: public contracts and pure table rules for Egyptian Domino.
///
/// This package intentionally contains NO GameState/MatchState. The AI and
/// coach packages depend only on this library, which makes it structurally
/// impossible for them to access hidden game information: they receive
/// [PlayerView]s and may build their own hypothetical [TableState]s, nothing
/// more.
library domino_api;

export 'src/actions.dart';
export 'src/config.dart';
export 'src/events.dart';
export 'src/player_view.dart';
export 'src/rng.dart';
export 'src/table.dart';
export 'src/tile.dart';
