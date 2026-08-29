import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:welwi/providers/calendar_provider.dart';
import 'package:welwi/widgets/event_card.dart';
import 'package:welwi/theme/app_theme.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CalendarProvider>(
      builder: (context, calendarProvider, child) {
        final selectedDay = calendarProvider.selectedDay;
        final focusedDay = calendarProvider.focusedDay;
        final eventsForDay = calendarProvider.getEventsForDay(selectedDay);

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Calendar widget
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.textHint.withValues(alpha: 0.1),
                  ),
                ),
                child: TableCalendar(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: focusedDay,
                  selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                  onDaySelected: (selected, focused) {
                    calendarProvider.setSelectedDay(selected);
                    calendarProvider.setFocusedDay(focused);
                  },
                  onPageChanged: (focused) {
                    calendarProvider.setFocusedDay(focused);
                  },
                  eventLoader: (day) =>
                      calendarProvider.getEventsForDay(day),
                  calendarFormat: CalendarFormat.month,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle:
                        Theme.of(context).textTheme.titleLarge!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    leftChevronIcon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.textPrimary,
                    ),
                    rightChevronIcon: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textPrimary,
                    ),
                    headerPadding:
                        const EdgeInsets.symmetric(vertical: 16),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle:
                        Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w600,
                            ),
                    weekendStyle:
                        Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: AppColors.textHint.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    cellMargin: const EdgeInsets.all(4),
                    defaultTextStyle: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    weekendTextStyle: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    todayDecoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    selectedDecoration: const BoxDecoration(
                      gradient: AppColors.dopamineGradient,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    markerDecoration: const BoxDecoration(
                      color: AppColors.dopamineStart,
                      shape: BoxShape.circle,
                    ),
                    markerSize: 6,
                    markersMaxCount: 3,
                    markerMargin: const EdgeInsets.symmetric(horizontal: 1),
                  ),
                ),
              ),
            ),

            // Day header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: AppColors.dopamineGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isToday(selectedDay)
                          ? 'Today'
                          : DateFormat('EEEE, MMM d').format(selectedDay),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${eventsForDay.length} event${eventsForDay.length != 1 ? 's' : ''}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Events list
            if (eventsForDay.isEmpty)
              SliverToBoxAdapter(
                child: _buildEmptyDayState(context),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return EventCard(
                        event: eventsForDay[index],
                        index: index,
                        onTap: () => _showEventDetail(
                            context, eventsForDay[index]),
                      );
                    },
                    childCount: eventsForDay.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  Widget _buildEmptyDayState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.dopamineStart.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                size: 28,
                color: AppColors.dopamineStart,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing scheduled',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the Calendar Agent (tap Add Event)\nto schedule something for this day.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetail(BuildContext context, dynamic event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 40,
                  decoration: BoxDecoration(
                    color: event.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    event.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow(context, Icons.access_time_rounded,
                'Time', event.formattedTime),
            const SizedBox(height: 12),
            _buildDetailRow(context, Icons.calendar_today_rounded,
                'Date', DateFormat('EEEE, MMM d, yyyy').format(event.date)),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDetailRow(context, Icons.description_rounded,
                  'Details', event.description),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Provider.of<CalendarProvider>(context, listen: false)
                      .deleteEvent(event.id);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Delete Event'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textHint),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ],
    );
  }
}
