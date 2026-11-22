import 'dart:convert';
import 'dart:io';

import 'reports.dart';

/// Minimal pluggable storage (offline). The Flutter app implements this with
/// Hive; tests and tools use the file or in-memory implementations.
abstract class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
  List<String> keys();
}

class InMemoryKeyValueStore extends KeyValueStore {
  final Map<String, String> _m = {};
  @override
  String? read(String key) => _m[key];
  @override
  void write(String key, String value) => _m[key] = value;
  @override
  void delete(String key) => _m.remove(key);
  @override
  List<String> keys() => _m.keys.toList();
}

/// Simple JSON-file-backed store (pure dart:io, fully offline).
class JsonFileKeyValueStore extends KeyValueStore {
  final String path;
  late Map<String, String> _m;

  JsonFileKeyValueStore(this.path) {
    final f = File(path);
    if (f.existsSync()) {
      try {
        _m = Map<String, String>.from(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      } catch (_) {
        _m = {};
      }
    } else {
      _m = {};
    }
  }

  void _flush() {
    File(path).writeAsStringSync(jsonEncode(_m));
  }

  @override
  String? read(String key) => _m[key];
  @override
  void write(String key, String value) {
    _m[key] = value;
    _flush();
  }

  @override
  void delete(String key) {
    _m.remove(key);
    _flush();
  }

  @override
  List<String> keys() => _m.keys.toList();
}

/// An aggregated educational record (one per category+reason pattern).
class MistakeRecord {
  final String key; // category|reasonCode
  final MistakeCategory category;
  final String titleAr;
  String whyWrongAr;
  String alternativeAr;
  int frequency;
  int firstSeenMatch;
  int lastSeenMatch;
  String status; // 'new' | 'recurring' | 'improving'

  MistakeRecord({
    required this.key,
    required this.category,
    required this.titleAr,
    required this.whyWrongAr,
    required this.alternativeAr,
    required this.frequency,
    required this.firstSeenMatch,
    required this.lastSeenMatch,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'category': category.name,
        'titleAr': titleAr,
        'whyWrongAr': whyWrongAr,
        'alternativeAr': alternativeAr,
        'frequency': frequency,
        'firstSeenMatch': firstSeenMatch,
        'lastSeenMatch': lastSeenMatch,
        'status': status,
      };

  static MistakeRecord fromJson(Map<String, dynamic> j) => MistakeRecord(
        key: j['key'] as String,
        category: MistakeCategory.values.byName(j['category'] as String),
        titleAr: j['titleAr'] as String,
        whyWrongAr: j['whyWrongAr'] as String,
        alternativeAr: j['alternativeAr'] as String,
        frequency: (j['frequency'] as num).toInt(),
        firstSeenMatch: (j['firstSeenMatch'] as num).toInt(),
        lastSeenMatch: (j['lastSeenMatch'] as num).toInt(),
        status: j['status'] as String,
      );
}

/// Aggregated mistake memory. Stores ONLY educational aggregates (no game
/// recordings, no tile histories) — per the privacy rules.
class MistakeMemory {
  static const _recordsKey = 'mistakeRecords';
  static const _matchCountKey = 'matchesAnalyzed';

  final KeyValueStore store;
  MistakeMemory(this.store);

  int get matchesAnalyzed =>
      int.tryParse(store.read(_matchCountKey) ?? '0') ?? 0;

  List<MistakeRecord> get records {
    final raw = store.read(_recordsKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(MistakeRecord.fromJson).toList();
  }

  void _saveRecords(List<MistakeRecord> records) {
    store.write(_recordsKey,
        jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  /// Records a batch of mistake reports from one finished match/analysis.
  void recordReports(List<MistakeReport> reports,
      {String Function(MistakeReport)? title,
      String Function(MistakeReport)? whyWrong,
      String Function(MistakeReport)? alternative}) {
    final matchId = matchesAnalyzed + 1;
    store.write(_matchCountKey, '$matchId');
    final all = records;
    final byKey = {for (final r in all) r.key: r};
    for (final rep in reports) {
      final key = '${rep.category.name}|${rep.reasonCode}';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = MistakeRecord(
          key: key,
          category: rep.category,
          titleAr: title?.call(rep) ?? rep.category.nameAr,
          whyWrongAr: whyWrong?.call(rep) ?? '',
          alternativeAr: alternative?.call(rep) ?? '',
          frequency: 1,
          firstSeenMatch: matchId,
          lastSeenMatch: matchId,
          status: 'new',
        );
      } else {
        existing.frequency++;
        existing.lastSeenMatch = matchId;
        existing.whyWrongAr = whyWrong?.call(rep) ?? existing.whyWrongAr;
        existing.alternativeAr =
            alternative?.call(rep) ?? existing.alternativeAr;
      }
    }
    // Update statuses.
    for (final r in byKey.values) {
      if (r.lastSeenMatch < matchId - 1 && r.frequency >= 1) {
        r.status = 'improving'; // didn't recur in the latest match
      } else if (r.frequency >= 3) {
        r.status = 'recurring';
      } else {
        r.status = 'new';
      }
    }
    _saveRecords(byKey.values.toList());
  }

  void clear() {
    store.delete(_recordsKey);
    store.delete(_matchCountKey);
  }
}
