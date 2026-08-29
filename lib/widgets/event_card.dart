import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:welwi/models/calendar_event.dart';
import 'package:welwi/providers/calendar_provider.dart';
import 'package:welwi/theme/app_theme.dart';

class EventCard extends StatefulWidget {
  final CalendarEvent event;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;
  final int index;

  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.onDismissed,
    this.index = 0,
  });

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: event.isMissedStudyBlock
                  ? AppColors.streakFire.withValues(alpha: 0.4)
                  : event.isCompleted
                      ? AppColors.dopamineMid.withValues(alpha: 0.3)
                      : event.color.withValues(alpha: 0.15),
              width: event.isMissedStudyBlock ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Color strip
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(
                  color: event.isMissedStudyBlock
                      ? AppColors.streakFire
                      : event.isCompleted
                          ? AppColors.dopamineMid
                          : event.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              // Event info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (event.isStudyBlock) ...[
                          Icon(
                            event.isCompleted
                                ? Icons.check_circle_rounded
                                : event.isMissedStudyBlock
                                    ? Icons.local_fire_department_rounded
                                    : Icons.menu_book_rounded,
                            size: 16,
                            color: event.isCompleted
                                ? AppColors.dopamineMid
                                : event.isMissedStudyBlock
                                    ? AppColors.streakFire
                                    : event.color,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            event.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: event.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: event.isCompleted
                                      ? AppColors.textHint
                                      : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (event.subject != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: event.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              event.subject!,
                              style: TextStyle(
                                color: event.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (event.description.isNotEmpty)
                          Expanded(
                            child: Text(
                              event.description,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side: time badge + optional checkbox
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: event.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      event.formattedTime,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: event.color,
                            fontSize: 13,
                          ),
                    ),
                  ),
                  if (event.isStudyBlock && !event.isCompleted && !event.isMissedStudyBlock)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () {
                          Provider.of<CalendarProvider>(context, listen: false)
                              .markStudyBlockCompleted(event.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.dopamineMid.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '✓ Done',
                            style: TextStyle(
                              color: AppColors.dopamineMid,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (event.isMissedStudyBlock)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '🔥 Missed!',
                        style: TextStyle(
                          color: AppColors.streakFire,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
