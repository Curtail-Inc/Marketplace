#!/bin/bash
#
# ReGrade MCP Bridge - Stdio to HTTP MCP Server Bridge
#
# This script bridges Claude Code's stdio-based MCP protocol to ReGrade's HTTP-based MCP server.
# It handles API key to JWT token exchange and automatic token refresh.
#
# Environment Variables:
#   REGRADE_API_KEY      - Optional: API key for authentication (if not set, reads from key file)
#   REGRADE_API_URL      - Optional: Base URL for ReGrade API (default: https://api.regrade.curtail.com)
#                          Accepts both http://localhost and http://localhost/api/v1 formats
#   REGRADE_MCP_ENDPOINT - Optional: MCP endpoint path without /api/v1 prefix (default: /mcp)
#   REGRADE_KEY_FILE     - Optional: Path to API key file (default: ~/.regrade/key)
#   REGRADE_TOKEN_CACHE  - Optional: Path to cache JWT token (default: <key_file>.token)
#   REGRADE_DEBUG        - Optional: Enable debug logging to stderr (default: false)

set -euo pipefail

# Debug logging function
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Error logging function
error() {
    echo "[ERROR] $*" >&2
}

# Configuration
API_KEY="${REGRADE_API_KEY:-}"
API_URL="${REGRADE_API_URL:-https://api.regrade.curtail.com}"
MCP_ENDPOINT="${REGRADE_MCP_ENDPOINT:-/mcp}"
KEY_FILE="${REGRADE_KEY_FILE:-$HOME/.regrade/key}"
DEBUG="${REGRADE_DEBUG:-false}"

# Normalize API_URL: strip /api/v1 suffix if present (we'll add it back)
# This allows both formats: http://localhost and http://localhost/api/v1
API_URL="${API_URL%/api/v1}"
API_URL="${API_URL%/}"  # Also strip trailing slash

# If API_KEY is not set in environment, try reading from key file
if [ -z "$API_KEY" ]; then
    if [ -f "$KEY_FILE" ]; then
        debug "Reading API key from $KEY_FILE"
        API_KEY=$(cat "$KEY_FILE" | tr -d '[:space:]')
        if [ -z "$API_KEY" ]; then
            error "API key file $KEY_FILE is empty"
            exit 1
        fi
    fi
fi

# Token cache defaults to key file path + '.token' suffix
# This ensures different key files get different token caches
TOKEN_CACHE="${REGRADE_TOKEN_CACHE:-${KEY_FILE}.token}"

# Derived URLs
# Note: auth/token is at /v1/auth/token but accessible without /v1 for backward compat
AUTH_URL="${API_URL}/api/v1/auth/token"
MCP_URL="${API_URL}/api/v1${MCP_ENDPOINT}"

# Validate required configuration
if [ -z "$API_KEY" ]; then
    error "API key not found. Please set REGRADE_API_KEY environment variable or create $KEY_FILE"
    exit 1
fi

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$TOKEN_CACHE")"

# Function to exchange API key for JWT token
exchange_token() {
    debug "Exchanging API key for JWT token..."

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$AUTH_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d '{}')

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        error "Token exchange failed with HTTP $http_code"
        error "Response: $body"
        return 1
    fi

    # Extract access_token and expires_at from response
    local access_token
    access_token=$(echo "$body" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"//;s/"//')

    local expires_at
    expires_at=$(echo "$body" | grep -o '"expires_at":"[^"]*"' | sed 's/"expires_at":"//;s/"//')

    if [ -z "$access_token" ]; then
        error "Failed to extract access_token from response"
        return 1
    fi

    # Cache the token with expiration
    echo "$access_token" > "$TOKEN_CACHE"
    echo "$expires_at" > "${TOKEN_CACHE}.expires"

    debug "Token cached successfully (expires: $expires_at)"
    echo "$access_token"
}

# Function to get valid JWT token (from cache or exchange)
get_token() {
    # Invalidate cache if API key file is newer than cached token
    if [ -f "$KEY_FILE" ] && [ -f "$TOKEN_CACHE" ]; then
        if [ "$KEY_FILE" -nt "$TOKEN_CACHE" ]; then
            debug "API key file is newer than cached token, invalidating cache..."
            rm -f "$TOKEN_CACHE" "${TOKEN_CACHE}.expires"
        fi
    fi

    # Check if token cache exists
    if [ -f "$TOKEN_CACHE" ] && [ -f "${TOKEN_CACHE}.expires" ]; then
        local cached_token
        cached_token=$(cat "$TOKEN_CACHE")

        local expires_at
        expires_at=$(cat "${TOKEN_CACHE}.expires")

        # Convert expiration to epoch time
        local expires_epoch
        if date --version >/dev/null 2>&1; then
            # GNU date
            expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
        else
            # BSD/macOS date
            expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s 2>/dev/null || echo "0")
        fi

        local current_epoch
        current_epoch=$(date +%s)

        # Refresh token if it expires in less than 5 minutes
        local buffer=300
        if [ $((expires_epoch - buffer)) -gt "$current_epoch" ]; then
            debug "Using cached token (expires: $expires_at)"
            echo "$cached_token"
            return 0
        else
            debug "Cached token expired or expiring soon, refreshing..."
        fi
    fi

    # Exchange API key for new token
    exchange_token
}

# Function to forward JSON-RPC request to HTTP MCP server
forward_request() {
    local request="$1"
    local token
    token=$(get_token)

    if [ -z "$token" ]; then
        error "Failed to obtain JWT token"
        # Return JSON-RPC error response
        echo '{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error: Failed to obtain JWT token"}}'
        return 1
    fi

    debug "Forwarding request to $MCP_URL"

    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" -X POST "$MCP_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$request")

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "401" ]; then
        debug "Token expired, refreshing and retrying..."
        # Remove cached token and retry once
        rm -f "$TOKEN_CACHE" "${TOKEN_CACHE}.expires"
        token=$(get_token)

        response=$(curl -s -w "\n%{http_code}" -X POST "$MCP_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "$request")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
    fi

    if [ "$http_code" != "200" ]; then
        error "HTTP request failed with code $http_code"
        # Return JSON-RPC error response
        echo "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"HTTP error: $http_code\",\"data\":$(echo "$body" | jq -R .)}}"
        return 1
    fi

    debug "Received response (HTTP $http_code)"
    echo "$body"
}

# Main loop - read JSON-RPC requests from stdin and forward to HTTP
debug "ReGrade MCP Bridge started"
debug "API URL: $API_URL"
debug "MCP URL: $MCP_URL"

while IFS= read -r line; do
    debug "Received request: ${line:0:100}..."
    forward_request "$line"
done
