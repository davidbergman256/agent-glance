#!/bin/sh
# Temporary spike logger: appends {"source":..,"ts":..,"payload":<hook json>} to spike.jsonl
LOG="$HOME/Library/Logs/AgentGlance/spike.jsonl"
{ printf '{"source":"%s","ts":"%s","payload":' "$1" "$(date +%H:%M:%S)"; cat; printf '}\n'; } >> "$LOG" 2>/dev/null
exit 0
