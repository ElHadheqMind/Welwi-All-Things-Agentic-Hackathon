import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:welwi/models/calendar_event.dart';
import 'package:welwi/theme/app_theme.dart';
import 'package:welwi/services/rag_service.dart';

class CalendarProvider extends ChangeNotifier {
  final List<CalendarEvent> _events = [];
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  final _uuid = const Uuid();
  final _ragService = RagService();

  List<CalendarEvent> get events => List.unmodifiable(_events);
  DateTime get selectedDay => _selectedDay;
  DateTime get focusedDay => _focusedDay;

  CalendarProvider() {
    final now = DateTime.now();
    _applyDailyTemplate(DateTime(now.year, now.month, now.day));
    _applyDailyTemplate(DateTime(now.year, now.month, now.day + 1));

    // Seed data
    _events.add(CalendarEvent(
      id: _uuid.v4(),
      title: '🏆 Hackathon Judging',
      date: DateTime(now.year, now.month, now.day),
      time: const TimeOfDay(hour: 15, minute: 0),
      description: 'Presenting Welwi to the judges.',
      color: AppColors.eventColors[3],
      isStudyBlock: false,
      eventType: CalendarEventType.other,
      durationMinutes: 60,
    ));

    // Demo seed data — "Doctor Visit" is deliberately relative to app launch
    // time (now + 5 min), not a fixed clock time, so the proactive-reminder
    // flow (CloudVoiceScreen._checkDueReminders) has something real to fire
    // on a few minutes into any demo run, whenever that happens to be. Also
    // mirrored into Firestore (see agent_backend seeding) so the agent's own
    // list_upcoming_events can see it too, not just this local display copy.
    final doctorVisitTime = now.add(const Duration(seconds: 30));
    _events.add(CalendarEvent(
      id: _uuid.v4(),
      title: '🩺 Doctor Visit',
      date: DateTime(doctorVisitTime.year, doctorVisitTime.month, doctorVisitTime.day),
      time: TimeOfDay(hour: doctorVisitTime.hour, minute: doctorVisitTime.minute),
      description: 'Annual checkup.',
      color: AppColors.eventColors[2],
      isStudyBlock: false,
      eventType: CalendarEventType.other,
      durationMinutes: 30,
    ));
    _events.add(CalendarEvent(
      id: _uuid.v4(),
      title: '🛒 Grocery Shopping',
      date: DateTime(now.year, now.month, now.day),
      time: TimeOfDay(hour: now.hour, minute: (now.minute + 30) % 60),
      description: 'Milk, eggs, coffee, and apples.',
      color: AppColors.eventColors[0],
      isStudyBlock: false,
      eventType: CalendarEventType.other,
      durationMinutes: 45,
    ));

    _initRag();
  }

  /// Generic daily structure — accessible and simple, no study-specific blocks.
  void _applyDailyTemplate(DateTime day) {
    final template = [
      {
        'title': '🌅 Morning Routine',
        'hour': 7, 'minute': 0,
        'desc': 'Wake up, hydrate, and start your day.',
        'color': AppColors.eventColors[0],
        'type': CalendarEventType.other,
        'duration': 30,
      },
      {
        'title': '🍳 Breakfast',
        'hour': 7, 'minute': 30,
        'desc': 'Have a nutritious breakfast.',
        'color': AppColors.eventColors[1],
        'type': CalendarEventType.meal,
        'duration': 30,
      },
      {
        'title': '🚶 Morning Walk',
        'hour': 8, 'minute': 0,
        'desc': 'Fresh air and light movement to start the day.',
        'color': AppColors.eventColors[2],
        'type': CalendarEventType.walk,
        'duration': 30,
      },
      {
        'title': '🥗 Lunch',
        'hour': 13, 'minute': 0,
        'desc': 'Take a break and have a balanced lunch.',
        'color': AppColors.eventColors[1],
        'type': CalendarEventType.meal,
        'duration': 60,
      },
      {
        'title': '🍲 Dinner',
        'hour': 19, 'minute': 0,
        'desc': 'End the day with a healthy dinner.',
        'color': AppColors.eventColors[2],
        'type': CalendarEventType.meal,
        'duration': 60,
      },
      {
        'title': '🌙 Wind Down',
        'hour': 21, 'minute': 30,
        'desc': 'Relax, reflect on the day, and prepare for sleep.',
        'color': AppColors.eventColors[4],
        'type': CalendarEventType.other,
        'duration': 60,
      },
    ];

    for (var item in template) {
      _events.add(CalendarEvent(
        id: _uuid.v4(),
        title: item['title'] as String,
        date: day,
        time: TimeOfDay(hour: item['hour'] as int, minute: item['minute'] as int),
        description: item['desc'] as String,
        color: item['color'] as Color,
        isStudyBlock: false,
        eventType: item['type'] as CalendarEventType,
        durationMinutes: item['duration'] as int,
      ));
    }
  }

  Future<void> _initRag() async {
    for (var event in _events) {
      _syncToRag(event);
    }
  }

  void _syncToRag(CalendarEvent event) {
    final timeStr = event.time != null
        ? "${event.time!.hour}:${event.time!.minute.toString().padLeft(2, '0')}"
        : "All day";
    final chunk =
        "Event on ${event.date.toIso8601String().split('T')[0]} at $timeStr:\n"
        "Title: ${event.title}\nDescription: ${event.description}";
    _ragService.upsertDocument(event.id, chunk);
  }

  List<CalendarEvent> getEventsForDay(DateTime day) {
    return _events.where((event) {
      return event.date.year == day.year &&
          event.date.month == day.month &&
          event.date.day == day.day;
    }).toList()
      ..sort((a, b) {
        if (a.time == null && b.time == null) return 0;
        if (a.time == null) return 1;
        if (b.time == null) return -1;
        return (a.time!.hour * 60 + a.time!.minute)
            .compareTo(b.time!.hour * 60 + b.time!.minute);
      });
  }

  void setSelectedDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  void setFocusedDay(DateTime day) {
    _focusedDay = day;
    notifyListeners();
  }

  void addEvent(CalendarEvent event) {
    _events.add(event);
    _syncToRag(event);
    notifyListeners();
  }

  void deleteEvent(String id) {
    final idx = _events.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _events.removeAt(idx);
      _ragService.deleteDocument(id);
      notifyListeners();
    }
  }

  void addEventsFromWelwi(List<CalendarEvent> events) {
    _events.addAll(events);
    for (var event in events) {
      _syncToRag(event);
    }
    notifyListeners();
  }

  CalendarEvent createEventFromWelwi({
    required String title,
    required DateTime date,
    TimeOfDay? time,
    String description = '',
    Color? color,
    String? subject,
    bool isStudyBlock = false,
    String? id,
  }) {
    final event = CalendarEvent(
      id: id ?? _uuid.v4(),
      title: title,
      date: date,
      time: time,
      description: description,
      color: color ?? AppColors.eventColors[3],
      subject: subject,
      isStudyBlock: false,
    );
    addEvent(event);
    return event;
  }

  /// Mirrors a backend `update_calendar_event` call — `id` is the same
  /// Firestore document id the event was created with (see
  /// `createEventFromWelwi`'s `id` param).
  void updateEvent(
    String id, {
    String? title,
    DateTime? date,
    TimeOfDay? time,
    String? description,
  }) {
    final idx = _events.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final old = _events[idx];
    final updated = old.copyWith(
      title: title,
      date: date,
      time: time,
      description: description,
    );
    _events[idx] = updated;
    _syncToRag(updated);
    notifyListeners();
  }

  // Stub kept for compile compatibility — no longer used for study blocks
  void markStudyBlockCompleted(String id) {}
  void markStudyBlockMissed(String id) {}
  int get completedToday => 0;
  int get totalTodayBlocks => 0;
}
