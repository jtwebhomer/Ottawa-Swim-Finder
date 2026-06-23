import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiFacilityDto {
  const ApiFacilityDto({
    required this.id,
    required this.name,
    required this.type,
    this.facilityType,
    this.address,
    this.lat,
    this.lng,
    this.scheduleMode,
    this.dataModel,
    this.hasSwimSchedule,
    this.displayStatus,
    this.region,
    this.lastUpdated,
    this.lastVerified,
  });

  final String id;
  final String name;
  final String type;
  final String? facilityType;
  final String? address;
  final double? lat;
  final double? lng;
  final String? scheduleMode;
  final String? dataModel;
  final bool? hasSwimSchedule;
  final String? displayStatus;
  final String? region;
  final int? lastUpdated;
  final int? lastVerified;

  factory ApiFacilityDto.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'];
    return ApiFacilityDto(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'indoor',
      facilityType: json['facility_type'] as String?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble() ??
          (coords is Map<String, dynamic>
              ? (coords['lat'] as num?)?.toDouble()
              : null),
      lng: (json['lng'] as num?)?.toDouble() ??
          (coords is Map<String, dynamic>
              ? (coords['lng'] as num?)?.toDouble()
              : null),
      scheduleMode: json['schedule_mode'] as String?,
      dataModel: json['data_model'] as String?,
      hasSwimSchedule: json['has_swim_schedule'] as bool?,
      displayStatus: json['display_status'] as String?,
      region: json['region'] as String?,
      lastUpdated: json['last_updated'] as int?,
      lastVerified: json['last_verified'] as int?,
    );
  }
}

class ApiScheduleDto {
  const ApiScheduleDto({
    this.date,
    required this.startTime,
    required this.endTime,
    required this.activityType,
    this.rawCategory,
    this.sourceStatus,
    this.scheduleType,
    this.dayOfWeek,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.recurrencePattern,
    this.source,
    this.confidenceScore,
    this.lastUpdated,
  });

  final String? date;
  final String startTime;
  final String endTime;
  final String activityType;
  final String? rawCategory;
  final String? sourceStatus;
  final String? scheduleType;
  final int? dayOfWeek;
  final String? dateRangeStart;
  final String? dateRangeEnd;
  final String? recurrencePattern;
  final String? source;
  final double? confidenceScore;
  final int? lastUpdated;

  factory ApiScheduleDto.fromJson(Map<String, dynamic> json) {
    return ApiScheduleDto(
      date: json['date'] as String?,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      activityType: json['activity_type'] as String,
      rawCategory: json['raw_category'] as String?,
      sourceStatus: json['source_status'] as String?,
      scheduleType: json['schedule_type'] as String?,
      dayOfWeek: json['day_of_week'] as int?,
      dateRangeStart: json['date_range_start'] as String?,
      dateRangeEnd: json['date_range_end'] as String?,
      recurrencePattern: json['recurrence_pattern'] as String?,
      source: json['source'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      lastUpdated: json['last_updated'] as int?,
    );
  }
}

class ApiTodayFacilityDto {
  const ApiTodayFacilityDto({
    required this.facilityId,
    required this.facilityName,
    required this.swims,
    this.type,
    this.lat,
    this.lng,
  });

  final String facilityId;
  final String facilityName;
  final String? type;
  final double? lat;
  final double? lng;
  final List<ApiScheduleDto> swims;

  factory ApiTodayFacilityDto.fromJson(Map<String, dynamic> json) {
    final swims = (json['swims'] as List<dynamic>? ?? [])
        .map((e) => ApiScheduleDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiTodayFacilityDto(
      facilityId: json['facility_id'] as String,
      facilityName: json['facility_name'] as String,
      type: json['type'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      swims: swims,
    );
  }
}

class ApiTodaySwimsDto {
  const ApiTodaySwimsDto({required this.date, required this.facilities});

  final String date;
  final List<ApiTodayFacilityDto> facilities;

  factory ApiTodaySwimsDto.fromJson(Map<String, dynamic> json) {
    final list = (json['facilities'] as List<dynamic>? ?? [])
        .map((e) => ApiTodayFacilityDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApiTodaySwimsDto(
      date: json['date'] as String,
      facilities: list,
    );
  }
}

class ApiSyncStatusDto {
  const ApiSyncStatusDto({
    this.lastSyncTime,
    this.lastSuccessfulSync,
    this.totalFacilities,
    this.totalSessions,
    this.blockedFacilities,
    this.syncHealth,
    this.syncRunning,
    this.lastStatus,
    this.successCount,
    this.errorCount,
    this.dataFreshnessScore,
  });

  final int? lastSyncTime;
  final int? lastSuccessfulSync;
  final int? totalFacilities;
  final int? totalSessions;
  final List<Map<String, dynamic>>? blockedFacilities;
  final String? syncHealth;
  final bool? syncRunning;
  final String? lastStatus;
  final int? successCount;
  final int? errorCount;
  final double? dataFreshnessScore;

  factory ApiSyncStatusDto.fromJson(Map<String, dynamic> json) {
    return ApiSyncStatusDto(
      lastSyncTime: json['last_sync_time'] as int? ?? json['last_sync'] as int?,
      lastSuccessfulSync: json['last_successful_sync'] as int?,
      totalFacilities: json['total_facilities'] as int?,
      totalSessions: json['total_sessions'] as int?,
      blockedFacilities: (json['blocked_facilities'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      syncHealth: json['sync_health'] as String?,
      syncRunning: json['sync_running'] as bool?,
      lastStatus: json['last_status'] as String? ?? json['last_sync_status'] as String?,
      successCount: json['success_count'] as int?,
      errorCount: json['error_count'] as int?,
      dataFreshnessScore: (json['data_freshness_score'] as num?)?.toDouble(),
    );
  }

  int? get lastSync => lastSyncTime;
  int? get facilitiesUpdated => successCount;
  int? get facilitiesFailed => errorCount;
  int? get blockedCount => blockedFacilities?.length;
  int? get parsedCount => totalSessions;
  int? get facilitiesTotal => totalFacilities;
  int? get facilitiesVerified => null;
  String? get lastSyncStatus => lastStatus;
}

/// HTTP client for the self-hosted Ottawa Swim Finder API.
class ApiService {
  ApiService({http.Client? client, String? baseUrl, String? apiKey})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConstants.apiBaseUrl,
        _apiKey = apiKey ?? AppConstants.apiKey;

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base =
        _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<List<ApiFacilityDto>> getFacilities() => fetchFacilities();

  Future<List<ApiScheduleDto>> getSchedules(String facilityId) =>
      fetchSchedules(facilityId);

  Future<ApiTodaySwimsDto> getTodaySwims() async {
    final response = await _client
        .get(_uri('/swims/today'), headers: _headers)
        .timeout(const Duration(seconds: 45));
    _ensureOk(response);
    return ApiTodaySwimsDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ApiSyncStatusDto> getSyncStatus() => fetchSyncStatus();

  Future<List<ApiFacilityDto>> fetchFacilities() async {
    final response = await _client
        .get(_uri('/facilities'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    _ensureOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['facilities'] as List<dynamic>? ?? [];
    return list
        .map((e) => ApiFacilityDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ApiScheduleDto>> fetchSchedules(String facilityId) async {
    final response = await _client
        .get(
          _uri('/schedules', {'facility_id': facilityId}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    _ensureOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['schedules'] as List<dynamic>? ?? [];
    return list
        .map((e) => ApiScheduleDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ApiSyncStatusDto> fetchSyncStatus() async {
    final response = await _client
        .get(_uri('/sync/status'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _ensureOk(response);
    return ApiSyncStatusDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'User-Agent': AppConstants.userAgent,
        if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
      };

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApiException(
      response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
}
