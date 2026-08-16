import 'dart:convert';
import 'package:http/http.dart' as http;

import '../auth/models/user_model.dart';
import 'models/api_event.dart';
import 'models/api_registration.dart';
import 'models/api_leaderboard.dart';
import 'models/api_admin.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  final http.Client _http = http.Client();

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return null;
      return jsonDecode(resp.body);
    }
    String msg = resp.body;
    try {
      final j = jsonDecode(resp.body);
      msg = (j as Map<String, dynamic>)['error']?.toString() ?? msg;
    } catch (_) {}
    throw ApiException(resp.statusCode, msg);
  }

  Future<T> _get<T>(String path, String? token,
      T Function(dynamic) fromJson) async {
    final resp = await _http.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
    return fromJson(_decode(resp));
  }

  Future<T> _post<T>(String path, String? token, Map<String, dynamic> body,
      T Function(dynamic) fromJson) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    return fromJson(_decode(resp));
  }

  Future<T> _patch<T>(String path, String? token, Map<String, dynamic> body,
      T Function(dynamic) fromJson) async {
    final resp = await _http.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    return fromJson(_decode(resp));
  }

  Future<void> _delete(String path, String? token) async {
    final resp = await _http.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
    _decode(resp);
  }

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<AppUser> provisionUser({
    required String token,
    String? preferredName,
  }) =>
      _post('/users/me/provision', token,
          {if (preferredName != null) 'preferredName': preferredName},
          (j) => AppUser.fromJson(j as Map<String, dynamic>));

  Future<AppUser> getMe({required String token}) =>
      _get('/users/me', token,
          (j) => AppUser.fromJson(j as Map<String, dynamic>));

  Future<AppUser> updateMe({
    required String token,
    String? preferredName,
    String? gender,
    String? birthdate,
  }) =>
      _patch(
        '/users/me',
        token,
        {
          if (preferredName != null) 'preferredName': preferredName,
          if (gender != null) 'gender': gender,
          if (birthdate != null) 'birthdate': birthdate,
        },
        (j) => AppUser.fromJson(j as Map<String, dynamic>),
      );

  // ── Events ─────────────────────────────────────────────────────────────────

  Future<List<ApiEvent>> listEvents({String? token}) =>
      _get('/events', token, (j) {
        final list = j as List<dynamic>;
        return list
            .map((e) => ApiEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<ApiEvent> getEvent(int id, {String? token}) =>
      _get('/events/$id', token,
          (j) => ApiEvent.fromJson(j as Map<String, dynamic>));

  Future<ApiEvent> createEvent(Map<String, dynamic> body,
          {required String token}) =>
      _post('/events', token, body,
          (j) => ApiEvent.fromJson(j as Map<String, dynamic>));

  Future<ApiEvent> updateEvent(int id, Map<String, dynamic> body,
          {required String token}) =>
      _patch('/events/$id', token, body,
          (j) => ApiEvent.fromJson(j as Map<String, dynamic>));

  Future<void> deleteEvent(int id, {required String token}) =>
      _delete('/events/$id', token);

  Future<ApiEvent> joinEventByCode(String code, {String? token}) =>
      _post('/events/join', token, {'eventCode': code},
          (j) => ApiEvent.fromJson(j as Map<String, dynamic>));

  // ── Registrations ──────────────────────────────────────────────────────────

  Future<ApiRegistration> createRegistration(int eventId,
          {required String token}) =>
      _post('/events/$eventId/registrations', token, {},
          (j) => ApiRegistration.fromJson(j as Map<String, dynamic>));

  Future<List<ApiRegistrationWithUser>> listRegistrations(int eventId,
          {required String token}) =>
      _get('/events/$eventId/registrations', token, (j) {
        final list = j as List<dynamic>;
        return list
            .map((e) =>
                ApiRegistrationWithUser.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<ApiRegistration> updateRegistration(
    int registrationId,
    Map<String, dynamic> body, {
    required String token,
  }) =>
      _patch('/registrations/$registrationId', token, body,
          (j) => ApiRegistration.fromJson(j as Map<String, dynamic>));

  // ── Lap logs ───────────────────────────────────────────────────────────────

  Future<List<String>> ingestLapLogs(
    List<Map<String, dynamic>> records, {
    required String token,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/lap-logs'),
      headers: _headers(token),
      body: jsonEncode({'records': records}),
    );
    final body = _decode(resp) as Map<String, dynamic>;
    return (body['processedIds'] as List<dynamic>).cast<String>();
  }

  // ── Leaderboard ────────────────────────────────────────────────────────────

  Future<List<ApiLeaderboardEntry>> getLeaderboard(int eventId,
          {String? token}) =>
      _get('/events/$eventId/leaderboard', token, (j) {
        final list = j as List<dynamic>;
        return list
            .map((e) =>
                ApiLeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Fetches all completed race results for the current runner in a single
  /// request, replacing the old per-event leaderboard loop.
  Future<List<ApiRaceHistoryEntry>> getRaceHistory(
          {required String token}) =>
      _get('/users/me/race-history', token, (j) {
        final list = j as List<dynamic>;
        return list
            .map((e) =>
                ApiRaceHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  // ── Admin ──────────────────────────────────────────────────────────────────

  Future<ApiAdminAnalytics> getAnalytics({required String token}) =>
      _get('/admin/analytics', token,
          (j) => ApiAdminAnalytics.fromJson(j as Map<String, dynamic>));

  Future<List<ApiTenantWithUser>> listTenants({required String token}) =>
      _get('/admin/tenants', token, (j) {
        final list = j as List<dynamic>;
        return list
            .map((e) => ApiTenantWithUser.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<ApiPlatformSettings> getPlatformSettings({String? token}) =>
      _get('/platform-settings', token,
          (j) => ApiPlatformSettings.fromJson(j as Map<String, dynamic>));

  Future<ApiPlatformSettings> updatePlatformSettings(
    Map<String, dynamic> body, {
    required String token,
  }) =>
      _patch('/platform-settings', token, body,
          (j) => ApiPlatformSettings.fromJson(j as Map<String, dynamic>));
}
