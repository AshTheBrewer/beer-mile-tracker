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

/// A single completed race in the runner's history, returned by
/// `GET /users/me/race-history`.  All fields needed to build a
/// [RunnerRaceResult] are included so no per-event leaderboard call is needed.
class ApiRaceHistoryEntry {
  const ApiRaceHistoryEntry({
    required this.eventId,
    required this.tenantId,
    required this.eventTitle,
    required this.eventCode,
    required this.eventDate,
    required this.eventStatus,
    required this.eventCreatedAt,
    required this.registrationId,
    required this.registeredAt,
    required this.totalElapsedMs,
    required this.finished,
    required this.laps,
    this.locationName,
    this.finishPosition,
    this.totalFinishers,
  });

  final int eventId;
  final int tenantId;
  final String eventTitle;
  final String eventCode;
  final String eventDate;
  final String eventStatus;
  final DateTime eventCreatedAt;
  final String? locationName;
  final int registrationId;
  final DateTime registeredAt;
  final int totalElapsedMs;
  final bool finished;
  final List<ApiLapSplit> laps;
  final int? finishPosition;
  final int? totalFinishers;

  factory ApiRaceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ApiRaceHistoryEntry(
        eventId: (json['eventId'] as num).toInt(),
        tenantId: (json['tenantId'] as num).toInt(),
        eventTitle: json['eventTitle'] as String,
        eventCode: json['eventCode'] as String,
        eventDate: json['eventDate'] as String,
        eventStatus: json['eventStatus'] as String,
        eventCreatedAt: DateTime.parse(json['eventCreatedAt'] as String),
        locationName: json['locationName'] as String?,
        registrationId: (json['registrationId'] as num).toInt(),
        registeredAt: DateTime.parse(json['registeredAt'] as String),
        totalElapsedMs: (json['totalElapsedMs'] as num).toInt(),
        finished: json['finished'] as bool? ?? false,
        laps: (json['laps'] as List<dynamic>)
            .map((e) => ApiLapSplit.fromJson(e as Map<String, dynamic>))
            .toList(),
        finishPosition: (json['finishPosition'] as num?)?.toInt(),
        totalFinishers: (json['totalFinishers'] as num?)?.toInt(),
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
