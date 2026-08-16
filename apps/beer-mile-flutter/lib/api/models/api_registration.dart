class ApiRegistration {
  const ApiRegistration({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.paymentStatus,
    required this.registeredAt,
    this.tagUid,
    this.runnerToken,
    this.updatedAt,
  });

  final int id;
  final int eventId;
  final String userId;
  final String paymentStatus; // pending | confirmed
  final DateTime registeredAt;
  final String? tagUid;
  final String? runnerToken;
  final DateTime? updatedAt;

  bool get isConfirmed => paymentStatus == 'confirmed';

  factory ApiRegistration.fromJson(Map<String, dynamic> json) =>
      ApiRegistration(
        id: (json['id'] as num).toInt(),
        eventId: (json['eventId'] as num).toInt(),
        userId: json['userId'] as String,
        paymentStatus: json['paymentStatus'] as String,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
        tagUid: json['tagUid'] as String?,
        runnerToken: json['runnerToken'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );
}

class ApiRegistrationWithUser extends ApiRegistration {
  const ApiRegistrationWithUser({
    required super.id,
    required super.eventId,
    required super.userId,
    required super.paymentStatus,
    required super.registeredAt,
    super.tagUid,
    super.runnerToken,
    super.updatedAt,
    this.userEmail,
    this.preferredName,
    this.gender,
    this.birthdate,
  });

  final String? userEmail;
  final String? preferredName;
  final String? gender;
  final String? birthdate;

  String get displayName => preferredName ?? userEmail ?? userId;

  factory ApiRegistrationWithUser.fromJson(Map<String, dynamic> json) =>
      ApiRegistrationWithUser(
        id: (json['id'] as num).toInt(),
        eventId: (json['eventId'] as num).toInt(),
        userId: json['userId'] as String,
        paymentStatus: json['paymentStatus'] as String,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
        tagUid: json['tagUid'] as String?,
        runnerToken: json['runnerToken'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        userEmail: json['userEmail'] as String?,
        preferredName: json['preferredName'] as String?,
        gender: json['gender'] as String?,
        birthdate: json['birthdate'] as String?,
      );
}
