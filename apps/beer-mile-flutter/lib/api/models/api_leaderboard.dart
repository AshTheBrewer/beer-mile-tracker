class ApiLapSplit {
  const ApiLapSplit({
    required this.lapNumber,
    required this.elapsedMs,
    required this.pourConfirmed,
    this.splitTimeMs,
  });

  final int lapNumber;
  final int elapsedMs;
  final bool pourConfirmed;
  final int? splitTimeMs;

  factory ApiLapSplit.fromJson(Map<String, dynamic> json) => ApiLapSplit(
        lapNumber: (json['lapNumber'] as num).toInt(),
        elapsedMs: (json['elapsedMs'] as num).toInt(),
        pourConfirmed: json['pourConfirmed'] as bool? ?? false,
        splitTimeMs: (json['splitTimeMs'] as num?)?.toInt(),
      );
}

class ApiLeaderboardEntry {
  const ApiLeaderboardEntry({
    required this.registrationId,
    required this.userId,
    required this.totalElapsedMs,
    required this.lapCount,
    required this.finished,
    required this.laps,
    this.preferredName,
    this.gender,
  });

  final int registrationId;
  final String userId;
  final int totalElapsedMs;
  final int lapCount;
  final bool finished;
  final List<ApiLapSplit> laps;
  final String? preferredName;
  final String? gender;

  String get displayName => preferredName ?? userId;

  String get formattedTime {
    final m = totalElapsedMs ~/ 60000;
    final s = (totalElapsedMs % 60000) / 1000;
    return '${m}m ${s.toStringAsFixed(1)}s';
  }

  factory ApiLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      ApiLeaderboardEntry(
        registrationId: (json['registrationId'] as num).toInt(),
        userId: json['userId'] as String,
        totalElapsedMs: (json['totalElapsedMs'] as num).toInt(),
        lapCount: (json['lapCount'] as num).toInt(),
        finished: json['finished'] as bool? ?? false,
        laps: (json['laps'] as List<dynamic>)
            .map((e) => ApiLapSplit.fromJson(e as Map<String, dynamic>))
            .toList(),
        preferredName: json['preferredName'] as String?,
        gender: json['gender'] as String?,
      );
}
