class ApiEvent {
  const ApiEvent({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.eventCode,
    required this.eventDate,
    required this.status,
    required this.createdAt,
    this.locationLat,
    this.locationLng,
    this.locationName,
    this.beerType,
    this.entryFee,
    this.paymentInstructions,
    this.prizesJson,
    this.updatedAt,
  });

  final int id;
  final int tenantId;
  final String title;
  final String eventCode;
  final String eventDate;
  final String status; // draft | open | active | completed | cancelled
  final DateTime createdAt;
  final double? locationLat;
  final double? locationLng;
  final String? locationName;
  final String? beerType;
  final String? entryFee;
  final String? paymentInstructions;
  final List<Map<String, dynamic>>? prizesJson;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';
  bool get isOpen => status == 'open';

  factory ApiEvent.fromJson(Map<String, dynamic> json) => ApiEvent(
        id: (json['id'] as num).toInt(),
        tenantId: (json['tenantId'] as num).toInt(),
        title: json['title'] as String,
        eventCode: json['eventCode'] as String,
        eventDate: json['eventDate'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        locationLat: (json['locationLat'] as num?)?.toDouble(),
        locationLng: (json['locationLng'] as num?)?.toDouble(),
        locationName: json['locationName'] as String?,
        beerType: json['beerType'] as String?,
        entryFee: json['entryFee'] as String?,
        paymentInstructions: json['paymentInstructions'] as String?,
        prizesJson: (json['prizesJson'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenantId': tenantId,
        'title': title,
        'eventCode': eventCode,
        'eventDate': eventDate,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        if (locationLat != null) 'locationLat': locationLat,
        if (locationLng != null) 'locationLng': locationLng,
        if (locationName != null) 'locationName': locationName,
        if (beerType != null) 'beerType': beerType,
        if (entryFee != null) 'entryFee': entryFee,
        if (paymentInstructions != null)
          'paymentInstructions': paymentInstructions,
        if (prizesJson != null) 'prizesJson': prizesJson,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
