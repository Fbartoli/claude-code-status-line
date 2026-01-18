#!/bin/bash
# Claude Code Status Line Indicator
# https://github.com/FelixBecker/claude-code-status-line
#
# Shows real-time session metrics in Claude Code's status line:
# [Model] Context% | Tokens | Thinking | Cost | Branch
#
# Installation:
#   1. Copy this script to ~/.claude/scripts/status-indicator.sh
#   2. Make it executable: chmod +x ~/.claude/scripts/status-indicator.sh
#   3. Add to ~/.claude/settings.json:
#      {
#        "statusLine": {
#          "type": "command",
#          "command": "~/.claude/scripts/status-indicator.sh"
#        }
#      }

set -euo pipefail

# Configuration
CONTEXT_LIMIT=200000  # 200K token context window
CLAUDE_DIR="$HOME/.claude/projects"

# Pricing per 1M tokens (adjust for your model)
PRICE_INPUT=15.00
PRICE_OUTPUT=75.00
PRICE_CACHE_READ=1.50
PRICE_CACHE_WRITE=18.75

# Find the most recent session file
find_session() {
    if [[ ! -d "$CLAUDE_DIR" ]]; then
        return 1
    fi

    # macOS compatible find
    if [[ "$(uname)" == "Darwin" ]]; then
        find "$CLAUDE_DIR" -name "*.jsonl" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | \
            sort -rn | head -1 | awk '{print $2}'
    else
        find "$CLAUDE_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -rn | head -1 | cut -d' ' -f2-
    fi
}

# Format token numbers with K/M suffix
format_tokens() {
    local num=$1
    if (( num >= 1000000 )); then
        awk "BEGIN {printf \"%.1fM\", $num/1000000}"
    elif (( num >= 1000 )); then
        awk "BEGIN {printf \"%.0fK\", $num/1000}"
    else
        echo "$num"
    fi
}

# Main
main() {
    local SESSION_FILE
    SESSION_FILE=$(find_session)

    if [[ -z "$SESSION_FILE" || ! -f "$SESSION_FILE" ]]; then
        echo "[--] Ctx: --% | \$0.00"
        exit 0
    fi

    # Extract model name
    local MODEL_RAW MODEL
    MODEL_RAW=$(grep -o '"model":"[^"]*"' "$SESSION_FILE" 2>/dev/null | tail -1 | sed 's/"model":"//;s/"//')

    case "$MODEL_RAW" in
        *opus-4-5*|*opus-4.5*) MODEL="Opus 4.5" ;;
        *opus*) MODEL="Opus" ;;
        *sonnet-4*) MODEL="Sonnet 4" ;;
        *sonnet*) MODEL="Sonnet" ;;
        *haiku*) MODEL="Haiku" ;;
        *) MODEL="${MODEL_RAW:0:12}" ;;
    esac

    # Extract latest usage data for context calculation
    local USAGE_LINE INPUT CACHE_READ CACHE_CREATE
    USAGE_LINE=$(grep -o '"usage":{[^}]*}' "$SESSION_FILE" 2>/dev/null | tail -1)

    INPUT=0; CACHE_READ=0; CACHE_CREATE=0

    if [[ -n "$USAGE_LINE" ]]; then
        INPUT=$(echo "$USAGE_LINE" | grep -o '"input_tokens":[0-9]*' | head -1 | cut -d':' -f2 || echo 0)
        CACHE_READ=$(echo "$USAGE_LINE" | grep -o '"cache_read_input_tokens":[0-9]*' | head -1 | cut -d':' -f2 || echo 0)
        CACHE_CREATE=$(echo "$USAGE_LINE" | grep -o '"cache_creation_input_tokens":[0-9]*' | head -1 | cut -d':' -f2 || echo 0)
    fi

    INPUT=${INPUT:-0}
    CACHE_READ=${CACHE_READ:-0}
    CACHE_CREATE=${CACHE_CREATE:-0}

    # Context usage
    local CONTEXT CONTEXT_PCT
    CONTEXT=$((INPUT + CACHE_READ + CACHE_CREATE))
    CONTEXT_PCT=$((CONTEXT * 100 / CONTEXT_LIMIT))
    (( CONTEXT_PCT > 100 )) && CONTEXT_PCT=100

    # Cumulative token totals
    local TOTAL_INPUT TOTAL_OUTPUT TOTAL_CACHE_READ TOTAL_CACHE_CREATE
    TOTAL_INPUT=$(grep -o '"input_tokens":[0-9]*' "$SESSION_FILE" 2>/dev/null | cut -d':' -f2 | awk '{sum+=$1} END {print sum+0}')
    TOTAL_OUTPUT=$(grep -o '"output_tokens":[0-9]*' "$SESSION_FILE" 2>/dev/null | cut -d':' -f2 | awk '{sum+=$1} END {print sum+0}')
    TOTAL_CACHE_READ=$(grep -o '"cache_read_input_tokens":[0-9]*' "$SESSION_FILE" 2>/dev/null | cut -d':' -f2 | awk '{sum+=$1} END {print sum+0}')
    TOTAL_CACHE_CREATE=$(grep -o '"cache_creation_input_tokens":[0-9]*' "$SESSION_FILE" 2>/dev/null | cut -d':' -f2 | awk '{sum+=$1} END {print sum+0}')

    # Check for thinking mode
    local THINKING_COUNT THINKING_INDICATOR=""
    THINKING_COUNT=$(grep -c '"type":"thinking"' "$SESSION_FILE" 2>/dev/null || echo "0")
    (( THINKING_COUNT > 0 )) && THINKING_INDICATOR="🧠"

    # Format tokens
    local IN_FMT OUT_FMT CACHE_FMT
    IN_FMT=$(format_tokens "$TOTAL_INPUT")
    OUT_FMT=$(format_tokens "$TOTAL_OUTPUT")
    CACHE_FMT=$(format_tokens $((TOTAL_CACHE_READ + TOTAL_CACHE_CREATE)))

    # Calculate cost
    local COST
    COST=$(awk "BEGIN {
        input_cost = $TOTAL_INPUT * $PRICE_INPUT / 1000000
        output_cost = $TOTAL_OUTPUT * $PRICE_OUTPUT / 1000000
        cache_read_cost = $TOTAL_CACHE_READ * $PRICE_CACHE_READ / 1000000
        cache_write_cost = $TOTAL_CACHE_CREATE * $PRICE_CACHE_WRITE / 1000000
        total = input_cost + output_cost + cache_read_cost + cache_write_cost
        printf \"%.2f\", total
    }")

    # Git branch
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "--")

    # ANSI color codes
    local RESET="\033[0m"
    local DIM="\033[2m"
    local RED="\033[91m"
    local YELLOW="\033[93m"
    local GREEN="\033[92m"
    local CYAN="\033[96m"
    local MAGENTA="\033[95m"
    local BLUE="\033[94m"

    # Context status color and icon
    local CTX_COLOR CTX_ICON
    if (( CONTEXT_PCT >= 90 )); then
        CTX_COLOR="$RED"; CTX_ICON="🔴"
    elif (( CONTEXT_PCT >= 70 )); then
        CTX_COLOR="$YELLOW"; CTX_ICON="🟡"
    else
        CTX_COLOR="$GREEN"; CTX_ICON="🟢"
    fi

    # Build output
    # [Opus 4.5] 🟢 Ctx: 52% | 1K↓ 2K↑ 45K⚡ | 🧠 | $5.57 | main
    printf "${DIM}[${RESET}${CYAN}%s${RESET}${DIM}]${RESET} " "$MODEL"
    printf "%s Ctx: ${CTX_COLOR}%d%%${RESET} " "$CTX_ICON" "$CONTEXT_PCT"
    printf "${DIM}|${RESET} ${BLUE}%s${RESET}↓ ${MAGENTA}%s${RESET}↑ ${DIM}%s⚡${RESET} " "$IN_FMT" "$OUT_FMT" "$CACHE_FMT"
    [[ -n "$THINKING_INDICATOR" ]] && printf "${DIM}|${RESET} %s " "$THINKING_INDICATOR"
    printf "${DIM}|${RESET} ${GREEN}\$%s${RESET} " "$COST"
    printf "${DIM}|${RESET} ${YELLOW}%s${RESET}" "$BRANCH"
}

main "$@"
