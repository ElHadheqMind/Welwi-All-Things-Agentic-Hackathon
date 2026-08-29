package com.gemma4hackathon.gemma4

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.welwi.rag"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeDatabase" -> {
                    // TODO: Initialize AI Edge RAG SDK
                    Log.d("RagService", "Native database initialized")
                    result.success(null)
                }
                "upsertDocument" -> {
                    val id = call.argument<String>("id")
                    val text = call.argument<String>("text")
                    // TODO: Chunk, embed, and store
                    Log.d("RagService", "Upsert document: $id")
                    result.success(null)
                }
                "deleteDocument" -> {
                    val id = call.argument<String>("id")
                    // TODO: Remove from vector store
                    Log.d("RagService", "Delete document: $id")
                    result.success(null)
                }
                "retrieveContext" -> {
                    val query = call.argument<String>("query")
                    val topK = call.argument<Int>("topK") ?: 3
                    // TODO: Embed query and perform vector search
                    Log.d("RagService", "Retrieving context for: $query")
                    
                    // Return empty list until native SDK is fully wired
                    result.success(emptyList<String>())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
