import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// A service that interfaces with the Native AI Edge RAG SDK
class RagService {
  static const MethodChannel _channel = MethodChannel('com.welwi.rag');
  
  // In-memory fallback if the native plugin isn't linked yet during testing
  final List<String> _fallbackChunkStore = [];

  Future<void> initializeDatabase() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('initializeDatabase');
        debugPrint('Native RAG DB initialized successfully.');
      } else {
        debugPrint('Fallback RAG DB initialized.');
        _fallbackChunkStore.clear();
      }
    } catch (e) {
      debugPrint('Error initializing RAG DB: $e');
    }
  }

  Future<void> upsertDocument(String id, String text) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('upsertDocument', {
          'id': id,
          'text': text,
        });
        debugPrint('Native RAG DB upsert successful: $id');
      } else {
        _fallbackChunkStore.add("[$id] $text");
      }
    } catch (e) {
      debugPrint('Error upserting to RAG DB: $e');
      _fallbackChunkStore.add("[$id] $text");
    }
  }

  Future<void> deleteDocument(String id) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('deleteDocument', {
          'id': id,
        });
      } else {
        _fallbackChunkStore.removeWhere((chunk) => chunk.startsWith("[$id]"));
      }
    } catch (e) {
      debugPrint('Error deleting from RAG DB: $e');
    }
  }

  Future<String> retrieveContext(String query, {int topK = 3}) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final List<dynamic>? results = await _channel.invokeMethod('retrieveContext', {
          'query': query,
          'topK': topK,
        });
        if (results == null || results.isEmpty) return "";
        return results.cast<String>().join("\n");
      }
    } catch (e) {
      debugPrint('Native retrieval failed, using fallback keyword match: $e');
    }
    
    // Fallback: naive keyword matching
    final keywords = query.toLowerCase().split(' ').where((w) => w.length > 3);
    final scored = _fallbackChunkStore.map((chunk) {
      int score = 0;
      final ch = chunk.toLowerCase();
      for (var kw in keywords) {
        if (ch.contains(kw)) score++;
      }
      return MapEntry(chunk, score);
    }).where((e) => e.value > 0).toList();
    
    scored.sort((a, b) => b.value.compareTo(a.value));
    final topChunks = scored.take(topK).map((e) => e.key).toList();
    
    return topChunks.join("\n");
  }
}
