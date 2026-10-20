#!/usr/bin/env bash

log() {
    local level="$1"
    shift
    jq -cn --arg time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg level "$level" --arg file "${BASH_SOURCE[1]##*/}" \
        --argjson line "${BASH_LINENO[0]}" --arg func "${FUNCNAME[1]:-main}" \
        --arg msg "$*" \
        '{time:$time,level:$level,file:$file,line:$line,func:$func,msg:$msg}' >&2
}

fail() {
    log ERROR "$*"
    exit 1
}
