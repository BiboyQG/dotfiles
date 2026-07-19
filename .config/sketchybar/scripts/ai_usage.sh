#!/usr/bin/env zsh
set -u

API_BASE="http://127.0.0.1:6736/v1/usage"
BAR_DIR="${TMPDIR:-/tmp}/sketchybar-ai-usage"
BAR_WIDTH=52
TRACK_COLOR="#414550"

mkdir -p "$BAR_DIR"

bar_fill_width() {
  local value="$1"

  if [[ "$value" == "--" ]]; then
    print 0
    return
  fi

  local percent="${value%%.*}"
  if ! [[ "$percent" =~ '^[0-9]+$' ]]; then
    print 0
    return
  fi

  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  print $(((percent * BAR_WIDTH + 50) / 100))
}

generate_bar() {
  local provider="$1"
  local color="$2"
  local session="$3"
  local weekly="$4"
  local session_width weekly_width output

  session_width="$(bar_fill_width "$session")"
  weekly_width="$(bar_fill_width "$weekly")"
  output="${BAR_DIR}/${provider}-${session}-${weekly}.png"

  if [[ -f "$output" ]]; then
    print -r -- "$output"
    return
  fi

  local -a draw=(
    -fill "$TRACK_COLOR" -draw "roundrectangle 0,2 51,4 1,1"
    -fill "$TRACK_COLOR" -draw "roundrectangle 0,9 51,11 1,1"
  )

  if (( session_width > 0 )); then
    draw+=(-fill "$color" -draw "roundrectangle 0,2 $((session_width - 1)),4 1,1")
  fi

  if (( weekly_width > 0 )); then
    draw+=(-fill "$color" -draw "roundrectangle 0,9 $((weekly_width - 1)),11 1,1")
  fi

  if command -v magick >/dev/null 2>&1; then
    magick -size "${BAR_WIDTH}x14" xc:none "${draw[@]}" "$output" >/dev/null 2>&1
  fi

  print -r -- "$output"
}

emit_unavailable() {
  local provider="$1"
  local provider_status="${2:-unavailable}"

  print -r -- "${provider}_status=${provider_status}"
  print -r -- "${provider}_name=${provider}"
  print -r -- "${provider}_plan="
  print -r -- "${provider}_session=--"
  print -r -- "${provider}_weekly=--"
  print -r -- "${provider}_bar=$(generate_bar "$provider" "#7f8490" "--" "--")"
  print -r -- "${provider}_fetched_at="
}

emit_provider() {
  local provider="$1"
  local body parsed

  if ! body="$(curl -fsS --max-time 3 "${API_BASE}/${provider}" 2>/dev/null)"; then
    emit_unavailable "$provider"
    return
  fi

  if [[ -z "$body" ]]; then
    emit_unavailable "$provider" "empty"
    return
  fi

  parsed="$(
    jq -r --arg provider "$provider" '
      if type == "array" then .[0] // empty else . end
      |
      def progress($label):
        [ .lines[]? | select(.type == "progress" and .label == $label) ][0];
      def remaining_pct($line):
        if $line == null or ($line.limit // 0) <= 0 then "--"
        else
          (((($line.limit | tonumber) - ($line.used | tonumber)) / ($line.limit | tonumber) * 100)
            | if . < 0 then 0 elif . > 100 then 100 else . end
            | round
            | tostring)
        end;

      [
        ($provider + "_status=ok"),
        ($provider + "_name=" + (.displayName // $provider)),
        ($provider + "_plan=" + (.plan // "")),
        ($provider + "_session=" + remaining_pct(progress("Session"))),
        ($provider + "_weekly=" + remaining_pct(progress("Weekly"))),
        ($provider + "_fetched_at=" + (.fetchedAt // ""))
      ][]
    ' <<<"$body" 2>/dev/null
  )"

  if [[ -z "$parsed" ]]; then
    emit_unavailable "$provider" "parse_error"
    return
  fi

  print -r -- "$parsed"

  local session weekly color
  session="$(awk -F= -v key="${provider}_session" '$1 == key { print $2; exit }' <<<"$parsed")"
  weekly="$(awk -F= -v key="${provider}_weekly" '$1 == key { print $2; exit }' <<<"$parsed")"
  color="#7f8490"
  [[ "$provider" == "codex" ]] && color="#74AA9C"
  [[ "$provider" == "claude" ]] && color="#DE7356"
  print -r -- "${provider}_bar=$(generate_bar "$provider" "$color" "$session" "$weekly")"
}

emit_provider codex
emit_provider claude
