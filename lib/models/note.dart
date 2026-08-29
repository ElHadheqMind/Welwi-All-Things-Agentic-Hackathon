class Note {
  final String id;
  final String title;
  final String content;
  final DateTime date;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? date,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      date: date ?? this.date,
    );
  }
}
