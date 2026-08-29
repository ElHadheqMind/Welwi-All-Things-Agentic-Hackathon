/// A tool call the cloud agent made mid-turn (e.g. propose_note).
class CloudFunctionCall {
  final String name;
  final Map<String, dynamic> args;
  CloudFunctionCall({required this.name, required this.args});
}

/// The result of a tool call (e.g. the outcome of save_note).
class CloudFunctionResponse {
  final String name;
  final Map<String, dynamic> response;
  CloudFunctionResponse({required this.name, required this.response});
}

/// One ADK event from a /run response — one agent's turn (root orchestrator
/// or a sub-agent it transferred to), which may carry spoken text, tool
/// calls, and/or tool results together.
class CloudEvent {
  final String author;
  final String text;
  final List<CloudFunctionCall> functionCalls;
  final List<CloudFunctionResponse> functionResponses;

  CloudEvent({
    required this.author,
    this.text = '',
    this.functionCalls = const [],
    this.functionResponses = const [],
  });

  CloudFunctionCall? findCall(String name) {
    for (final c in functionCalls) {
      if (c.name == name) return c;
    }
    return null;
  }
}
