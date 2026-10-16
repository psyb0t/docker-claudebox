# Turns Claude Code's stream-json events into readable CI log lines.
# Used by action.yml with `jq -R --unbuffered -r -f stream-log.jq`, one event
# per input line. Lines that are not JSON pass through unchanged.

def cut($n): if length > $n then .[0:$n] + " [... \(length - $n) more chars]" else . end;
def oneline: gsub("\r"; "") | gsub("\n"; " | ");

def tool_summary:
  if .name == "Bash" then "Bash: " + ((.input.command // "") | oneline | cut(400))
  elif (.input.file_path // null) != null then .name + ": " + .input.file_path
  elif (.input.pattern // null) != null then .name + ": " + .input.pattern
  elif (.input.url // null) != null then .name + ": " + .input.url
  else .name + ": " + ((.input // {}) | tojson | cut(300))
  end;

def result_text:
  if (.content | type) == "string" then .content
  elif (.content | type) == "array" then [.content[] | select(.type == "text") | .text] | join(" ")
  else "" end;

. as $line
| (try fromjson catch null) as $e
| if $e == null then $line
  elif $e.type == "system" and $e.subtype == "init" then
    "[start] model=\($e.model // "?") cwd=\($e.cwd // "?")"
  elif $e.type == "assistant" then
    ($e.message.content // [])[]
    | if .type == "text" then "[claude] " + (.text | oneline | cut(2000))
      elif .type == "tool_use" then "[tool] " + tool_summary
      else empty end
  elif $e.type == "user" then
    ($e.message.content // [])[]
    | select(.type == "tool_result")
    | (if .is_error == true then "[result:error] " else "[result] " end) + (result_text | oneline | cut(600))
  elif $e.type == "result" then
    "[done] is_error=\($e.is_error) subtype=\($e.subtype) num_turns=\($e.num_turns) duration_ms=\($e.duration_ms) total_cost_usd=\($e.total_cost_usd // "n/a")"
  else empty end
