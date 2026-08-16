class ApiAdminAnalytics {
  const ApiAdminAnalytics({
    required this.totalEvents,
    required this.totalRunners,
    required this.totalTenants,
    required this.totalFinishers,
    required this.eventsByStatus,
    this.avgLapTimeMs,
  });

  final int totalEvents;
  final int totalRunners;
  final int totalTenants;
  final int totalFinishers;
  final Map<String, int> eventsByStatus;
  final int? avgLapTimeMs;

  factory ApiAdminAnalytics.fromJson(Map<String, dynamic> json) =>
      ApiAdminAnalytics(
        totalEvents: (json['totalEvents'] as num).toInt(),
        totalRunners: (json['totalRunners'] as num).toInt(),
        totalTenants: (json['totalTenants'] as num).toInt(),
        totalFinishers: (json['totalFinishers'] as num).toInt(),
        eventsByStatus: (json['eventsByStatus'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
        avgLapTimeMs: (json['avgLapTimeMs'] as num?)?.toInt(),
      );
}

class ApiTenantWithUser {
  const ApiTenantWithUser({
    required this.id,
    required this.userId,
    required this.organizationName,
    required this.createdAt,
    this.userEmail,
  });

  final int id;
  final String userId;
  final String organizationName;
  final DateTime createdAt;
  final String? userEmail;

  factory ApiTenantWithUser.fromJson(Map<String, dynamic> json) =>
      ApiTenantWithUser(
        id: (json['id'] as num).toInt(),
        userId: json['userId'] as String,
        organizationName: json['organizationName'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        userEmail: json['userEmail'] as String?,
      );
}

class ApiPlatformSettings {
  const ApiPlatformSettings({
    required this.id,
    this.appStoreIosUrl,
    this.playStoreAndroidUrl,
    this.updatedAt,
  });

  final int id;
  final String? appStoreIosUrl;
  final String? playStoreAndroidUrl;
  final DateTime? updatedAt;

  factory ApiPlatformSettings.fromJson(Map<String, dynamic> json) =>
      ApiPlatformSettings(
        id: (json['id'] as num).toInt(),
        appStoreIosUrl: json['appStoreIosUrl'] as String?,
        playStoreAndroidUrl: json['playStoreAndroidUrl'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );
}
