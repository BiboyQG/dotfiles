#!/usr/bin/env zsh
set -euo pipefail

JQ=/opt/homebrew/bin/jq
MEDIA_CONTROL=/opt/homebrew/bin/media-control
CACHE_DIR="$HOME/Library/Caches/sketchybar"

if (( $# == 2 )) && [[ "$1" == "--stdin" ]]; then
  CACHE_DIR="$2"
  payload="$(/bin/cat)"
elif (( $# == 0 )); then
  # media-control prints null when nothing is playing; the filter treats that
  # like any other non-object payload.
  if ! payload="$($MEDIA_CONTROL get 2>/dev/null)"; then
    payload=null
  fi
else
  print -u2 "Usage: $0 [--stdin cache-dir]"
  exit 2
fi

if ! $JQ -e '
  if type != "object" then false
  else
    ((.playbackRate // 0 | tonumber? // 0) > 0)
      and (.bundleIdentifier == "com.spotify.client"
        or .bundleIdentifier == "com.apple.Music")
  end
' <<<"$payload" >/dev/null 2>&1; then
  $JQ -cn '{playing:false}'
  exit 0
fi

artwork_data="$($JQ -r '.artworkData // "" | tostring' <<<"$payload")"
artwork_path=""

if [[ -n "$artwork_data" ]] && /bin/mkdir -p "$CACHE_DIR"; then
  if temporary_artwork="$(/usr/bin/mktemp "$CACHE_DIR/media-artwork.XXXXXX" 2>/dev/null)"; then
    if print -rn -- "$artwork_data" | /usr/bin/base64 -D >"$temporary_artwork" 2>/dev/null \
      && [[ -s "$temporary_artwork" ]]; then
      artwork_hash="$(/usr/bin/shasum -a 256 "$temporary_artwork" | /usr/bin/awk '{ print $1 }')"
      candidate_artwork="$CACHE_DIR/media-artwork-$artwork_hash"
      if [[ -f "$candidate_artwork" ]]; then
        /bin/rm -f "$temporary_artwork"
        artwork_path="$candidate_artwork"
      elif /bin/mv "$temporary_artwork" "$candidate_artwork" 2>/dev/null; then
        artwork_path="$candidate_artwork"
      else
        /bin/rm -f "$temporary_artwork"
      fi
      # The current cover may be old but must exist when SketchyBar loads it.
      /usr/bin/find "$CACHE_DIR" -type f -name 'media-artwork-*' \
        ! -name "media-artwork-$artwork_hash" -mtime +7 -delete 2>/dev/null || true
    else
      /bin/rm -f "$temporary_artwork"
    fi
  fi
fi

$JQ -c --arg artwork "$artwork_path" \
  '{playing:true, title:(.title // "" | tostring), artist:(.artist // "" | tostring), artwork:$artwork}' \
  <<<"$payload"
