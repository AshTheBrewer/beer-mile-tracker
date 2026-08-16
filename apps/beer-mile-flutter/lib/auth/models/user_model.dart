class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.preferredName,
    this.gender,
    this.birthdate,
  });

  final String id;
  final String email;
  final String role; // 'runner' | 'host' | 'super_admin'
  final String? preferredName;
  final String? gender;
  final String? birthdate;

  bool get isRunner => role == 'runner';
  bool get isHost => role == 'host';
  bool get isSuperAdmin => role == 'super_admin';

  String get displayName => preferredName ?? email.split('@').first;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        preferredName: json['preferredName'] as String?,
        gender: json['gender'] as String?,
        birthdate: json['birthdate'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'preferredName': preferredName,
        'gender': gender,
        'birthdate': birthdate,
      };

  AppUser copyWith({
    String? id,
    String? email,
    String? role,
    String? preferredName,
    String? gender,
    String? birthdate,
  }) =>
      AppUser(
        id: id ?? this.id,
        email: email ?? this.email,
        role: role ?? this.role,
        preferredName: preferredName ?? this.preferredName,
        gender: gender ?? this.gender,
        birthdate: birthdate ?? this.birthdate,
      );
}
