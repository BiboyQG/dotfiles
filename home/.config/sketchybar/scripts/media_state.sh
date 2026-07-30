#!/usr/bin/env zsh
set -u

JQ=/opt/homebrew/bin/jq
NOWPLAYING=/opt/homebrew/bin/nowplaying-cli
CACHE_DIR="$HOME/Library/Caches/sketchybar"

if [[ "${1:-}" == "--stdin" ]]; then
  if (( $# > 2 )); then
    print -u2 "Usage: $0 [--stdin [cache-dir]]"
    exit 2
  fi
  [[ -n "${2:-}" ]] && CACHE_DIR="$2"
  payload="$(/bin/cat)"
elif (( $# == 0 )); then
  if ! payload="$($NOWPLAYING get --json title artist playbackRate clientBundleIdentifier artworkData 2>/dev/null)"; then
    payload=null
  fi
else
  print -u2 "Usage: $0 [--stdin [cache-dir]]"
  exit 2
fi

if ! playing="$($JQ -er '
  if type != "object" then false
  else
    ((.playbackRate // 0 | tonumber? // 0) > 0)
      and (.clientBundleIdentifier == "com.spotify.client"
        or .clientBundleIdentifier == "com.apple.Music")
  end
' <<<"$payload" 2>/dev/null)" || [[ "$playing" != "true" ]]; then
  $JQ -cn '{playing:false}'
  exit 0
fi

title="$($JQ -r '.title // "" | tostring' <<<"$payload")"
artist="$($JQ -r '.artist // "" | tostring' <<<"$payload")"
artwork_data="$($JQ -r '.artworkData // "" | tostring' <<<"$payload")"
artwork_path=""

if [[ -n "$artwork_data" ]] && /bin/mkdir -p "$CACHE_DIR"; then
  if temporary_artwork="$(/usr/bin/mktemp "$CACHE_DIR/media-artwork.XXXXXX" 2>/dev/null)" \
    && [[ -n "$temporary_artwork" ]]; then
    if print -rn -- "$artwork_data" | /usr/bin/base64 -D >"$temporary_artwork" 2>/dev/null \
      && [[ -s "$temporary_artwork" ]]; then
      artwork_hash="$(/usr/bin/shasum -a 256 "$temporary_artwork" | /usr/bin/awk '{ print $1 }')"
      candidate_artwork="$CACHE_DIR/media-artwork-$artwork_hash"
      if [[ -z "$artwork_hash" ]]; then
        /bin/rm -f "$temporary_artwork"
      elif [[ -f "$candidate_artwork" ]]; then
        /bin/rm -f "$temporary_artwork"
        artwork_path="$candidate_artwork"
      elif /bin/mv "$temporary_artwork" "$candidate_artwork" 2>/dev/null; then
        artwork_path="$candidate_artwork"
      else
        /bin/rm -f "$temporary_artwork"
      fi
      /usr/bin/find "$CACHE_DIR" -type f -name 'media-artwork-*' -mtime +7 -delete 2>/dev/null || true
    else
      /bin/rm -f "$temporary_artwork"
    fi
  fi
fi

$JQ -cn \
  --arg title "$title" \
  --arg artist "$artist" \
  --arg artwork "$artwork_path" \
  '{playing:true, title:$title, artist:$artist, artwork:$artwork}'
