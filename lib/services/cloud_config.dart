/// Endpoints for the deployed ADK multi-agent backend (Cloud Run).
///
/// Both services are deployed with `--allow-unauthenticated` deliberately,
/// as a documented hackathon-demo scope decision: a mobile client can't
/// carry a `gcloud`-style IAM identity token, and building a full
/// Firebase-Auth exchange layer was out of scope for the remaining time.
/// The GCP service account credentials (Gemini, Firestore, Calendar) never
/// leave the server — only the HTTP/WebSocket endpoint itself is public.
/// See agent_backend/README.md for the full tradeoff writeup.
class CloudConfig {
  static const String textAgentBaseUrl =
      'https://welwi-text-agent-549628512893.us-central1.run.app';
  static const String voiceAgentWsUrl =
      'wss://welwi-voice-agent-549628512893.us-central1.run.app';

  static const String textAppName = 'welwi_agent';
  static const String voiceAppName = 'welwi_voice_agent';
}
