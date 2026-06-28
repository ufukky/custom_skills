#!/usr/bin/env bash
#
# =============================================================================
# Skill: llama_proxy
# =============================================================================
#
# Purpose:
#   Manage a local Llama.cpp Cluster Manager and interact with its dynamic
#   inference proxy.
#
# Provides:
#   - Dashboard inspection
#   - Model registration
#   - Model switching
#   - Model deletion
#   - Readiness checks
#   - OpenAI-compatible proxy endpoint helpers
#
# Environment:
#   LLAMA_ADMIN=http://127.0.0.1:8077
#   LLAMA_PROXY=http://127.0.0.1:8078
#
# Requirements:
#   curl
#   jq
#
# =============================================================================

set -euo pipefail

LLAMA_ADMIN="${LLAMA_ADMIN:-http://127.0.0.1:8077}"
LLAMA_PROXY="${LLAMA_PROXY:-http://127.0.0.1:8078}"

###############################################################################
# Utilities
###############################################################################

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing dependency: $1" >&2
        exit 1
    }
}

require curl
require jq

###############################################################################
# Dashboard
###############################################################################

dashboard() {
    curl -fsSL \
        "$LLAMA_ADMIN/api/dashboard"
}

status() {
    dashboard | jq \
        '{model:.current_model,running:.is_running,pid:.pid}'
}

models() {
    dashboard | jq '.models'
}

###############################################################################
# Health
###############################################################################

ready() {

    dashboard |
    jq -e '
        .is_running == true and
        .current_model != "None (Idle)"
    ' >/dev/null
}

wait_ready() {

    local timeout="${1:-60}"
    local elapsed=0

    until ready; do
        sleep 2
        elapsed=$((elapsed+2))

        if (( elapsed >= timeout )); then
            echo "Timed out waiting for model." >&2
            return 1
        fi
    done
}

###############################################################################
# Model Management
###############################################################################

register_model() {

    local name="$1"
    shift

    if (( $# == 0 )); then
        echo "Arguments required." >&2
        return 1
    fi

    jq -n \
        --arg name "$name" \
        --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
        '{name:$name,args:$args}' |
    curl -fsSL \
        -X POST \
        -H "Content-Type: application/json" \
        -d @- \
        "$LLAMA_ADMIN/api/models"
}

delete_model() {

    local model="$1"

    curl -fsSL \
        -X DELETE \
        "$LLAMA_ADMIN/api/models/$model"
}

switch_model() {

    local model="$1"

    jq -n --arg model "$model" \
        '{model:$model}' |
    curl -fsSL \
        -X POST \
        -H "Content-Type: application/json" \
        -d @- \
        "$LLAMA_ADMIN/api/change-model"

    wait_ready
}

###############################################################################
# Logs
###############################################################################

logs() {
    curl -N \
        "$LLAMA_ADMIN/api/logs/stream"
}

###############################################################################
# Proxy
###############################################################################

proxy_url() {
    echo "$LLAMA_PROXY"
}

chat_endpoint() {
    echo "$LLAMA_PROXY/v1/chat/completions"
}

completion_endpoint() {
    echo "$LLAMA_PROXY/v1/completions"
}

embedding_endpoint() {
    echo "$LLAMA_PROXY/v1/embeddings"
}

###############################################################################
# OpenAI Compatible Requests
###############################################################################

chat() {

    if ! ready; then
        echo "No model loaded." >&2
        return 1
    fi

    curl -fsSL \
        "$LLAMA_PROXY/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @-
}

completion() {

    if ! ready; then
        echo "No model loaded." >&2
        return 1
    fi

    curl -fsSL \
        "$LLAMA_PROXY/v1/completions" \
        -H "Content-Type: application/json" \
        -d @-
}

embeddings() {

    if ! ready; then
        echo "No model loaded." >&2
        return 1
    fi

    curl -fsSL \
        "$LLAMA_PROXY/v1/embeddings" \
        -H "Content-Type: application/json" \
        -d @-
}

###############################################################################
# Recovery Guidance
###############################################################################

recover() {

cat <<EOF

Recovery Procedure

1. Check dashboard:
   dashboard

2. Inspect history:
   dashboard | jq '.history'

3. Watch logs:
   logs

4. Common failures:

   • Exit code 1
       Verify VRAM arguments.

   • HTTP 500
       Model crashed.

   • HTTP 504
       Model still loading.

   • Invalid arguments
       Every CLI flag must be a separate array element.

       GOOD:
         ["-ngl","99","-c","16384"]

       BAD:
         ["-ngl 99","-c 16384"]

EOF
}

###############################################################################
# Help
###############################################################################

help() {

cat <<EOF

llama_proxy Skill

Commands:

dashboard
status
models

ready
wait_ready

register_model NAME ARGS...
delete_model NAME
switch_model NAME

logs

proxy_url
chat_endpoint
completion_endpoint
embedding_endpoint

chat
completion
embeddings

recover

EOF
}
