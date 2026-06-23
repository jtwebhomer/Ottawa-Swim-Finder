class SavedSwimOccurrence {
  const SavedSwimOccurrence({
    required this.date,
    required this.startTime,
    required this.endTime,
    this.facilityName,
  });

  final String date;
  final String startTime;
  final String endTime;
  final String? facilityName;
}

class SavedSwim {
  const SavedSwim({
    this.id,
    this.scheduleId,
    required this.facilityId,
    required this.category,
    this.rawCategory,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.reminderMinutes,
    this.createdAt,
    this.facilityName,
    this.isRecurring = false,
    this.dayOfWeek,
    this.upcomingOccurrences = const [],
  });

  final int? id;
  final int? scheduleId;
  final String facilityId;
  final String category;
  final String? rawCategory;
  /// Concrete date for one-off saves; empty for recurring patterns.
  final String date;
  final String startTime;
  final String endTime;
  final int? reminderMinutes;
  final int? createdAt;
  final String? facilityName;
  final bool isRecurring;
  final int? dayOfWeek;
  final List<SavedSwimOccurrence> upcomingOccurrences;

  SavedSwim copyWith({
    String? facilityName,
    List<SavedSwimOccurrence>? upcomingOccurrences,
  }) =>
      SavedSwim(
        id: id,
        scheduleId: scheduleId,
        facilityId: facilityId,
        category: category,
        rawCategory: rawCategory,
        date: date,
        startTime: startTime,
        endTime: endTime,
        reminderMinutes: reminderMinutes,
        createdAt: createdAt,
        facilityName: facilityName ?? this.facilityName,
        isRecurring: isRecurring,
        dayOfWeek: dayOfWeek,
        upcomingOccurrences: upcomingOccurrences ?? this.upcomingOccurrences,
      );

  String get patternLabel {
    if (!isRecurring || dayOfWeek == null) return date;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return 'Every ${days[dayOfWeek! - 1]}';
  }
}
