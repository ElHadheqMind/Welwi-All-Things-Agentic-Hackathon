import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:welwi/models/note.dart';
import 'package:welwi/services/rag_service.dart';

class NotesProvider extends ChangeNotifier {
  final List<Note> _notes = [];
  final _uuid = const Uuid();
  final _ragService = RagService();

  NotesProvider() {
    // Inject seed data for the hackathon demo
    createNote(
      title: "Hackathon Pitch",
      content: "The pitch is tomorrow at 3 PM. Remember to emphasize the voice-first architecture and the three-agent system.",
    );
    createNote(
      title: "Grocery List",
      content: "Milk, eggs, coffee, and apples.",
    );
  }

  List<Note> get notes => List.unmodifiable(_notes);

  List<Note> getNotesForDay(DateTime date) {
    return _notes.where((note) {
      return note.date.year == date.year &&
          note.date.month == date.month &&
          note.date.day == date.day;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Note> getAllNotes() {
    final sorted = List<Note>.from(_notes);
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  Note createNote({
    required String title,
    required String content,
    String? id,
  }) {
    final note = Note(
      id: id ?? _uuid.v4(),
      title: title,
      content: content,
      date: DateTime.now(),
    );
    _notes.add(note);

    // Sync to RAG for note querying
    final chunk = "Note: ${note.title}\nContent: ${note.content}\nDate: ${note.date.toIso8601String()}";
    _ragService.upsertDocument(note.id, chunk);

    notifyListeners();
    return note;
  }

  // Keep backward-compat alias
  Note createNoteFromWelwi({required String title, required String content}) =>
      createNote(title: title, content: content);

  void deleteNote(String id) {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notes.removeAt(idx);
      _ragService.deleteDocument(id);
      notifyListeners();
    }
  }

  /// Mirrors a backend `update_note` call — `id` is the same Firestore
  /// document id the note was created with (see `createNote`'s `id` param).
  void updateNote(String id, {String? title, String? content}) {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final old = _notes[idx];
    final updated = Note(
      id: old.id,
      title: title ?? old.title,
      content: content ?? old.content,
      date: old.date,
    );
    _notes[idx] = updated;
    final chunk = "Note: ${updated.title}\nContent: ${updated.content}\nDate: ${updated.date.toIso8601String()}";
    _ragService.upsertDocument(updated.id, chunk);
    notifyListeners();
  }
}
