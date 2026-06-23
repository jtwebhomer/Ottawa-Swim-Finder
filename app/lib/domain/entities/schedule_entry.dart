class ScheduleEntry {
  const ScheduleEntry({
    this.id,
    required this.facilityId,
    required this.category,
    this.rawCategory,
    required this.scheduleType,
    this.dayOfWeek,
    this.date,
    required this.startTime,
    required this.endTime,
    this.notes,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.lastUpdated,
    this.facilityName,
    this.distanceKm,
  });

  final int? id;
  final String facilityId;
  final String category;
  final String? rawCategory;
  final String scheduleType;
  final int? dayOfWeek;
  final String? date;
  final String startTime;
  final String endTime;
  final String? notes;
  final String? dateRangeStart;
  final String? dateRangeEnd;
  final int? lastUpdated;
  final String? facilityName;
  final double? distanceKm;

  ScheduleEntry copyWith({
    String? facilityName,
    double? distanceKm,
  }) {
    return ScheduleEntry(
      id: id,
      facilityId: facilityId,
      category: category,
      rawCategory: rawCategory,
      scheduleType: scheduleType,
      dayOfWeek: dayOfWeek,
      date: date,
      startTime: startTime,
      endTime: endTime,
      notes: notes,
      dateRangeStart: dateRangeStart,
      dateRangeEnd: dateRangeEnd,
      lastUpdated: lastUpdated,
      facilityName: facilityName ?? this.facilityName,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}
