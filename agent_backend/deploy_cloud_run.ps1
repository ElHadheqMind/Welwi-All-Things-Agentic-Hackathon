# Deploys both welwi_agent (text) and welwi_voice_agent (voice/Live) to
# Cloud Run as separate services. Run from agent_backend/.
#
# Prereqs (one-time, already done for welwi-agent-hack):
#   - Secret Manager secret with the Gemini API key:
#       gcloud secrets create welwi-gemini-api-key --data-file=- <<< "$env:GEMINI_API_KEY"
#   - Cloud Run's default compute service account granted access to it:
#       gcloud secrets add-iam-policy-binding welwi-gemini-api-key `
#         --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" `
#         --role="roles/secretmanager.secretAccessor"
#
# `adk deploy cloud_run` deploys exactly one agent folder per call (it is
# NOT the multi-app parent-directory pattern `adk web` uses locally) — so
# this builds two separate, disposable staging copies, one per service.

param(
    [string]$ProjectId = "welwi-agent-hack",
    [string]$Region = "us-central1",
    [string]$GeminiSecretName = "welwi-gemini-api-key"
)

$ErrorActionPreference = "Stop"
$AgentBackend = $PSScriptRoot
$Staging = Join-Path (Split-Path $AgentBackend -Parent) "agent_backend_deploy_staging"
$Adk = Join-Path $AgentBackend ".venv\Scripts\adk.exe"

if (Test-Path $Staging) { Remove-Item -Recurse -Force $Staging }
New-Item -ItemType Directory -Path $Staging | Out-Null

function Copy-App($name) {
    $dst = Join-Path $Staging $name
    robocopy (Join-Path $AgentBackend $name) $dst /E /XD __pycache__ /XF *.pyc /NFL /NDL /NP | Out-Null
    Copy-Item (Join-Path $AgentBackend "requirements.txt") (Join-Path $dst "requirements.txt")
}

Write-Output "--- Deploying welwi_agent (text) ---"
Copy-App "welwi_agent"
Push-Location $Staging
"n" | & $Adk deploy cloud_run --project=$ProjectId --region=$Region --service_name=welwi-text-agent welwi_agent `
    -- --set-env-vars="GOOGLE_GENAI_USE_VERTEXAI=TRUE,GOOGLE_CLOUD_PROJECT=$ProjectId,GOOGLE_CLOUD_LOCATION=$Region,WELWI_MODEL=gemini-3.6-flash,FIRESTORE_DATABASE=(default)"
Pop-Location

Write-Output "--- Deploying welwi_voice_agent (voice/Live) ---"
# welwi_voice_agent imports welwi_agent's tools/config as a sibling package,
# which doesn't resolve inside a single-folder Cloud Run deploy — vendor a
# copy in and rewrite the import to relative. Only the disposable staging
# copy is touched; the tracked source in welwi_voice_agent/agent.py imports
# `welwi_agent.*` normally, correct for local dev / Agent Engine.
Copy-App "welwi_voice_agent"
$voiceAgentPy = Join-Path $Staging "welwi_voice_agent\agent.py"
robocopy (Join-Path $AgentBackend "welwi_agent") (Join-Path $Staging "welwi_voice_agent\welwi_agent") /E /XD __pycache__ /XF *.pyc /NFL /NDL /NP | Out-Null
(Get-Content $voiceAgentPy) -replace '^from welwi_agent\.', 'from .welwi_agent.' | Set-Content $voiceAgentPy

Push-Location $Staging
# GOOGLE_GENAI_USE_ENTERPRISE=FALSE is required, not optional: `adk deploy
# cloud_run` bakes ENV GOOGLE_GENAI_USE_ENTERPRISE=1 into every generated
# Dockerfile, and it takes priority over GOOGLE_GENAI_USE_VERTEXAI in
# google-genai's Client() resolution — without this override the voice
# agent silently ends up in Vertex mode (which 404s for the Live model
# under a service account) despite GOOGLE_GENAI_USE_VERTEXAI=FALSE.
"n" | & $Adk deploy cloud_run --project=$ProjectId --region=$Region --service_name=welwi-voice-agent welwi_voice_agent `
    -- --set-env-vars="GOOGLE_GENAI_USE_VERTEXAI=FALSE,GOOGLE_GENAI_USE_ENTERPRISE=FALSE,WELWI_LIVE_MODEL=gemini-3.1-flash-live-preview,FIRESTORE_DATABASE=(default)" `
       --set-secrets="GOOGLE_API_KEY=$GeminiSecretName`:latest"
Pop-Location

Remove-Item -Recurse -Force $Staging
Write-Output "--- Done ---"
