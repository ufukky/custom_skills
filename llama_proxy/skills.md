# 🤖 Skill Specification: Llama.cpp Dynamic Context Manager

[![Agent Compatible](https://img.shields.io/badge/Agent_Compatible-Yes-brightgreen.svg)](#)
[![API Version](https://img.shields.io/badge/API-v1.0-blue.svg)](#)

This document defines the systemic capabilities, operational playbooks, and programmatic interfaces required for an autonomous AI agent (e.g., AutoGen, CrewAI, LangChain) to manage and consume LLM inference engines controlled by this local Llama.cpp Cluster Manager.

## 🏗️ Operational Architecture Overview

The system operates using dual-port multiplexing:
* **Admin Control Panel Port (`8077`)**: Handles model registry configurations, manual context swapping, state telemetry, and real-time event logging.
* **Dynamic Inference Proxy Port (`8078`)**: Exposes a reverse-proxy routing layer that forwards standard OpenAI/Llama.cpp API payloads directly to the underlying engine once deployed.

---

## 📡 1. Skill Discovery & Administrative Endpoint Directory

Agents interacting with the environment must use the following standard administrative routes on port `8077`.

### Get System Dashboard State
* **Endpoint:** `GET http://127.0.0.1:8077/api/dashboard`
* **Purpose:** Collect real-time telemetry, model maps, operational logs, and current server settings.
* **Response Signature (JSON):**
  ```json
  {
    "current_model": "Abiray/Huihui-Qwythos-9B...",
    "is_running": true,
    "pid": 26996,
    "models": { ... },
    "history": [ ... ],
    "live_requests": [],
    "settings": { ... }
  }
Hot-Swap Execution Model Context
Endpoint: POST http://127.0.0.1:8077/api/change-model

Payload Structure:

JSON
{
  "model": "Target-Model-Key-From-Registry"
}
Notes: This endpoint terminates the active engine process, purges the VRAM memory context, and spawns the target model. It waits for a successful readiness probe (up to 60 seconds for speculative or large contexts).

Upsert Model Configuration Profile
Endpoint: POST http://127.0.0.1:8077/api/models

Payload Structure:

JSON
{
  "name": "Custom-Model-Id",
  "args": ["-hf", "username/repo-id", "-c", "16384", "-ngl", "99", "--flash-attn", "on"]
}
Delete Model Configuration Profile
Endpoint: DELETE http://127.0.0.1:8077/api/models/{model_name}

🧠 2. Agent Operational Playbooks
Playbook A: Verifying Core Operational Status
Before routing an execution loop, an agent must verify if a model is ready:

Issue a request to GET /api/dashboard.

Evaluate current_model and is_running.

If current_model is "None (Idle)" or is_running is false, the dynamic proxy layer will reject inference calls with 503 Service Unavailable. Proceed to Playbook B.

Playbook B: Deploying or Context-Swapping an Engine
When an agent needs to activate a specific model:

Issue GET /api/dashboard to check the keys under the "models" block.

If the required target identifier is missing, issue POST /api/models to register its execution flags first. Ensure arguments are strict JSON arrays of strings.

Issue POST /api/change-model passing the chosen model identifier.

Error Strategy: Monitor the backend Server-Sent Events console (GET /api/logs/stream) or history array to verify the SERVER_READY state. Do not send completion payloads while context transitions.

⚡ 3. Programmatic Consumption (Proxy Layer)
Once an engine state transition completes cleanly, the model's core completion and embedding engines are ready to receive inference workloads.

Target Routing Parameters
Agents must point downstream clients to the Internal Port / Proxy Pipeline:

Base Endpoint URL: http://127.0.0.1:8078/

Supported Interception Paths
Chat completions: /v1/chat/completions

Base legacy completions: /v1/completions

Token embeddings: /v1/embeddings

⚠️ 4. Constraints & Argument Hygiene
Critical Rule for Automated Scripts
When registering model argument profiles via POST /api/models, agents must format command line arguments as isolated, clean array items.

❌ Incorrect: ["-ngl 99", "--no-mmproj "]

✅ Correct: ["-ngl", "99", "--no-mmproj"]

System Recovery
If an application returns an HTTP status code 500 or 504 during context changes, check the event history (GET /api/dashboard). If the engine crashed with return code 1, verify VRAM parameters and ensure server_bin path resolution is correct.