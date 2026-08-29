import 'package:flutter/material.dart';
import 'package:welwi/theme/app_theme.dart';

enum CalendarEventType {
  studyBlock,
  meal,
  exercise,
  sleep,
  breakTime,
  walk,
  other,
}

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final String description;
  final Color color;

  // Study block fields
  final String? subject;
  final bool isStudyBlock;
  bool isCompleted;
  bool wasMissed;

  // Companion fields
  final CalendarEventType eventType;
  final int durationMinutes; // default 60

  CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.description = '',
    Color? color,
    this.subject,
    this.isStudyBlock = false,
    this.isCompleted = false,
    this.wasMissed = false,
    this.eventType = CalendarEventType.other,
    this.durationMinutes = 60,
  }) : color = color ??
            AppColors.eventColors[
                title.hashCode.abs() % AppColors.eventColors.length];

  String get formattedTime {
    if (time == null) return 'All day';
    final hour = time!.hour.toString().padLeft(2, '0');
    final minute = time!.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get formattedDate {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Whether this study block's scheduled time has passed and it wasn't completed
  bool get isMissedStudyBlock {
    if (!isStudyBlock || isCompleted) return false;
    if (time == null) return false;
    final scheduledEnd = DateTime(
      date.year, date.month, date.day,
      time!.hour + 1, time!.minute, // Assume 1-hour study blocks
    );
    return DateTime.now().isAfter(scheduledEnd);
  }

  CalendarEvent copyWith({
    String? title,
    DateTime? date,
    TimeOfDay? time,
    String? description,
    Color? color,
    String? subject,
    bool? isStudyBlock,
    bool? isCompleted,
    bool? wasMissed,
    CalendarEventType? eventType,
    int? durationMinutes,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      description: description ?? this.description,
      color: color ?? this.color,
      subject: subject ?? this.subject,
      isStudyBlock: isStudyBlock ?? this.isStudyBlock,
      isCompleted: isCompleted ?? this.isCompleted,
      wasMissed: wasMissed ?? this.wasMissed,
      eventType: eventType ?? this.eventType,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  /// Compute the DateTime when this event ends
  DateTime? get endTime {
    if (time == null) return null;
    final start = DateTime(date.year, date.month, date.day, time!.hour, time!.minute);
    return start.add(Duration(minutes: durationMinutes));
  }
}
