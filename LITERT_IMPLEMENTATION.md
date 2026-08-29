# Comprehensive Guide: Building an Offline Text AI App with LiteRT and Flutter

This documentation provides an exhaustive, deep-dive architectural and implementation guide to integrating the Gemma 4 Large Language Model (LLM) into a Flutter application using **Google's LiteRT-LM** engine. 

By following this guide, developers can understand exactly how our text-only baseline works—from extracting a massive 2+ GB model from an APK into native storage, to orchestrating complex prompt engineering that forces the AI to output structured JSON data natively on the user's CPU, without ever connecting to the internet.

*Note: This documentation is focused strictly on the baseline Text-to-Text inference pipeline. Processing complex multimodalities like audio is built upon this foundation.*

---

## Table of Contents
1. **Introduction and On-Device Philosophy**
2. **Architecture Map: Dart, JNI, and C++**
3. **Phase 1: Zero to Hero — Model Loading & Initialization**
4. **Phase 2: Anatomy of Text Inference (Tokenization & Sessions)**
5. **Phase 3: The Exact Implementation (Code Walkthrough)**
6. **Phase 4: Prompt Engineering for Strict JSON Output**
7. **Phase 5: Parsing, Cleaning, and State Building**
8. **Under the Hood: How XNNPack Keeps the Phone from Melting**

---

## 1. Introduction and On-Device Philosophy

### The Goal
To build a Flutter application that can analyze user text input (such as a messy paragraph like *"I need to buy groceries next tuesday at 4pm and maybe grab some milk from the store"*) and convert it into structured data formats (like Calendar Events or Notes) entirely offline.

### What is LiteRT-LM?
To achieve offline capability, we utilize **LiteRT-LM** (previously the TensorFlow Lite Language Model backend). Standard LiteRT is built for simple tasks like image classification. LiteRT-LM is a heavily optimized orchestration engine specifically designed for **Transformer architectures (LLMs)**. 

When you run an LLM, you are essentially multiplying massive matrices billions of times per second. LiteRT-LM manages these mathematical operations efficiently on mobile ARM processors.

---

## 2. Architecture Map: Dart, JNI, and C++

Because Flutter applications compile Dart code, they cannot natively execute gigabytes of raw C++ matrix math at optimal speeds. 

We bridge this divide using the `flutter_gemma` package:
1.  **Flutter UI (Dart)** grabs the user's String input from a TextField.
2.  **`flutter_gemma`** receives the String and passes it through Flutter's MethodChannel.
3.  **JNI (Android) / Swift (iOS)** receives the String natively and prepares standard C buffers.
4.  **LiteRT-LM (C++)** takes the buffer, converts letters to Numbers (Tokenization), runs it through the weights of the Gemma model, and spits out Numbers (Tokens).
5.  **De-Tokenizer (C++)** converts the numbers back to a String and sends it back up the chain.

---

## 3. Phase 1: Zero to Hero — Model Loading & Initialization

Before you can run text, the model must be loaded into Random Access Memory (RAM). Our model is `gemma-4-E2B-it.litertlm` (Instruction Tuned, 2 Billion Parameters).

### The Asset Extraction Problem
In mobile development, anything in your `assets` folder is heavily compressed inside the `.apk` or `.ipa` archive. A C++ engine cannot directly memory-map a file that is compressed inside an archive. 

If we tried to load it directly, the C++ library would crash because it requires direct, contiguous disk access. Therefore, our `GemmaService` utilizes `installModel()`.

### The Loading Implementation

We built a singleton service to ensure we don't accidentally load 2GB into RAM twice.

```dart
// lib/services/gemma_service.dart

import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaService {
  static final GemmaService _instance = GemmaService._internal();
  factory GemmaService() => _instance;
  GemmaService._internal();

  bool isInitialized = false;
  InferenceModel? _model;
  
  // The path inside the Flutter Bundle
  final String _assetPath = 'assets/models/gemma-4-E2B-it.litertlm';

  Future<void> init() async {
    // Prevent double-loading
    if (isInitialized && _model != null) return;
    
    try {
      // Step 1: Check if it's already installed on the OS file system
      _model = await FlutterGemma.getActiveModel();
      isInitialized = true;
      print('Gemma: Model found in disk cache. Mapped to RAM.');
      
    } catch (e) {
      // Step 2: Extract from the compressed app bundle (APK/IPA)
      print('Gemma: Model not found. Extracting 2GB asset bundle. Please wait...');
      
      // This physically copies the file from the APK to the app's private sandbox storage
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt, 
        fileType: ModelFileType.litertlm
      ).fromAsset(_assetPath).install();
      
      // Step 3: Now that it exists as a raw file, map it into RAM
      _model = await FlutterGemma.getActiveModel();
      isInitialized = true;
      print('Gemma: Setup complete. Ready for Text Inference.');
    }
  }
}
```

---

## 4. Phase 2: Anatomy of Text Inference (Tokenization & Sessions)

When dealing with LLMs locally, we don't just "ping an API". We must manage the **KV Cache** (Key-Value Cache).

### What is a Session?
When you start a chat loop with Gemma, it opens a `Session`. A session is essentially a block of memory that remembers the current context. As you add words to the prompt, LiteRT-LM tokenizes them and stores them in the KV cache so it doesn't have to re-evaluate the entire beginning of the sentence for every new word it generates.

For our application (Note taking / Calendar tracking), we don't need back-and-forth chat history. Every action is a "One-Shot" interaction. Therefore, we **open and close** sessions explicitly to flush the RAM.

---

## 5. Phase 3: The Exact Implementation (Code Walkthrough)

Here is exactly how text flows through the service:

```dart
  Future<String> _getResponse(String prompt) async {
    // 1. Safety Check: Ensure the 2GB matrices are loaded into RAM
    if (!isInitialized) await init();
    if (_model == null) throw Exception('Gemma model not initialized');
    
    // 2. Open a new Memory Block (Session)
    // Starting fresh ensures old notes don't hallucinate into new notes
    final session = await _model!.createSession();
    
    // 3. Inject the text payload into the C++ Engine context
    await session.addQueryChunk(Message.text(
      text: prompt, 
      isUser: true // Indicates this is the user query, not the assistant history
    ));
    
    // 4. Trigger Autoregressive Generation
    // The device CPU/GPU loops hundreds of times, predicting the next word 
    // based on highest mathematical probability.
    final response = await session.getResponse();
    
    // 5. Destruct the Session buffer to free hundreds of Megabytes of RAM
    await session.close();
    
    return response;
  }
```

---

## 6. Phase 4: Prompt Engineering for Strict JSON Output

Running an LLM on a phone is computationally expensive. We cannot afford for it to return "chatty" responses like *"Hello there! Based on your text, I think you want a note..."* because it wastes battery, time, and makes programmatic UI parsing impossible.

We use **System Prompt Wrappers** to force the AI into a strict "Data Extraction" mode.

### Calendar Example

```dart
  Future<List<Map<String, dynamic>>> generateCalendarEvents(String userMessage) async {
    final now = DateTime.now();
    
    // THE PROMPT:
    // We inject exact temporal context (${now.xxx}) because offline models 
    // do not have access to the internet or system clocks internally.
    final prompt = '''
    You are a calendar assistant. Extract event details from the following text: 
    "$userMessage"
    
    Today's date is: ${now.year}-${now.month}-${now.day}.
    
    You must return ONLY a JSON object. Do not include markdown or conversational text.
    {"title": "...", "description": "...", "year": ${now.year}, "month": ${now.month}, "day": ${now.day}, "hour": 14, "minute": 30}
    ''';

    // Send to LiteRT Engine
    final rawStringResponse = await _getResponse(prompt);
    
    // Execute cleaning/parsing
    return _parseToDartMap(rawStringResponse);
  }
```

---

## 7. Phase 5: Parsing, Cleaning, and State Building

Even with strict prompts, smaller quantizations of Gemma can occasionally "hallucinate" minor structural aberrations (like wrapping the response in ```json markdown tags). 

Our Dart implementation features a sanitization pipeline to guarantee no fatal XML/JSON parsing errors crash the Flutter UI.

```dart
  Map<String, dynamic> _cleanAndParseGemmaResponse(String rawResponse) {
    String cleanText = rawResponse;
    
    // PASS 1: Strip Code Blocks
    if (cleanText.contains('```json')) {
      cleanText = cleanText.split('```json')[1].split('```')[0].trim();
    } 
    // PASS 2: Surgical Extraction (Fallback)
    // If it generated "Sure! { "title": "hello" }", we find the brackets.
    else if (cleanText.contains('{')) {
      cleanText = cleanText.substring(cleanText.indexOf('{'));
      final lastBrace = cleanText.lastIndexOf('}');
      if (lastBrace != -1) {
        cleanText = cleanText.substring(0, lastBrace + 1);
      }
    }

    // PASS 3: Safe Property Mapping
    // Rather than jsonDecode(which throws errors easily), we utilize regex 
    // extraction for absolute stability on volatile on-device output.
    return {
      'title': _extractField(cleanText, "title"),
      'description': _extractField(cleanText, "description"),
      'year': int.tryParse(_extractField(cleanText, "year", isNumber: true)) ?? DateTime.now().year,
    };
  }

  // Regex utility
  String _extractField(String jsonStr, String field, {bool isNumber = false}) {
    try {
      final key = '"$field":';
      if (!jsonStr.contains(key)) return "";
      var tail = jsonStr.substring(jsonStr.indexOf(key) + key.length).trim();
      
      if (isNumber) {
        final match = RegExp(r'(\d+)').firstMatch(tail);
        return match?.group(1) ?? "";
      } else {
        if (tail.startsWith('"')) tail = tail.substring(1);
        int endQ = tail.indexOf('"');
        if (endQ != -1) return tail.substring(0, endQ);
        return tail;
      }
    } catch (_) { return ""; }
  }
```

---

## 8. Under the Hood: How XNNPack Keeps the Phone from Melting

Why does this actually work on a phone without lagging the UI? 

When `flutter_gemma` calls LiteRT-LM, it utilizes **XNNPack Delegates**. 

*   **Floating-Point Kernels**: Neural networks are just floating-point multiplications (e.g., 0.0413 * -0.9912). Doing 2 billion of these per word is tough. XNNPack applies highly optimized assembly-level instructions (like ARM NEON) to multiply arrays of these numbers simultaneously (SIMD).
*   **Asynchronous Engine**: You'll notice `await _getResponse()` returns a `Future`. Natively, the C++ engine spawns a background thread. This ensures the 60 FPS Flutter UI Thread is never blocked while the model thinks. The user can continue scrolling or typing while Gemma computes in the background.

By strictly standardizing our text flow as shown above, we guarantee a robust, private, offline-first intelligence layer that performs flawlessly without relying on external APIs.
