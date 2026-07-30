local icons = require("icons")
local colors = require("colors")

local media_script = "$HOME/.config/sketchybar/scripts/media_state.sh"

sbar.add("event", "spotify_media_change", "com.spotify.client.PlaybackStateChanged")
sbar.add("event", "music_media_change", "com.apple.Music.playerInfo")

local media_cover = sbar.add("item", {
  position = "right",
  background = {
    image = {
      drawing = false,
      scale = 0.85,
    },
    color = colors.transparent,
  },
  label = { drawing = false },
  icon = { drawing = false },
  drawing = false,
  updates = true,
  popup = {
    align = "center",
    horizontal = true,
  }
})

local media_artist = sbar.add("item", {
  position = "right",
  drawing = false,
  padding_left = 3,
  padding_right = 0,
  width = 0,
  icon = { drawing = false },
  label = {
    width = 0,
    font = { size = 9 },
    color = colors.with_alpha(colors.white, 0.6),
    max_chars = 18,
    y_offset = 6,
  },
})

local media_title = sbar.add("item", {
  position = "right",
  drawing = false,
  padding_left = 3,
  padding_right = 0,
  icon = { drawing = false },
  label = {
    font = { size = 11 },
    width = 0,
    max_chars = 16,
    y_offset = -5,
  },
})

sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.back },
  label = { drawing = false },
  click_script = "/opt/homebrew/bin/nowplaying-cli previous",
})
sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.play_pause },
  label = { drawing = false },
  click_script = "/opt/homebrew/bin/nowplaying-cli togglePlayPause",
})
sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.forward },
  label = { drawing = false },
  click_script = "/opt/homebrew/bin/nowplaying-cli next",
})

local detail_revision = 0
local media_hovered = false
local function animate_detail(detail)
  sbar.animate("tanh", 30, function()
    media_artist:set({ label = { width = detail and "dynamic" or 0 } })
    media_title:set({ label = { width = detail and "dynamic" or 0 } })
  end)
end

local function show_temporary_detail()
  detail_revision = detail_revision + 1
  local revision = detail_revision
  animate_detail(true)
  sbar.delay(5, function()
    if revision == detail_revision and not media_hovered then animate_detail(false) end
  end)
end

local function hide_media()
  detail_revision = detail_revision + 1
  media_hovered = false
  media_artist:set({ drawing = false, label = { width = 0 } })
  media_title:set({ drawing = false, label = { width = 0 } })
  media_cover:set({ drawing = false, popup = { drawing = false } })
end

local function apply_media_state(state)
  if type(state) ~= "table" or state.playing ~= true then
    hide_media()
    return
  end

  local artwork = type(state.artwork) == "string" and state.artwork or ""
  local has_artwork = artwork ~= ""
  local image = { drawing = has_artwork }
  if has_artwork then image.string = artwork end

  media_artist:set({
    drawing = true,
    label = { string = tostring(state.artist or "") },
  })
  media_title:set({
    drawing = true,
    label = { string = tostring(state.title or "") },
  })
  media_cover:set({
    drawing = true,
    background = { image = image },
    icon = {
      drawing = not has_artwork,
      string = icons.media.play_pause,
    },
  })
  show_temporary_detail()
end

local media_revision = 0
local refresh_running = false
local refresh_pending = false
local start_refresh

start_refresh = function()
  refresh_running = true
  local revision = media_revision
  sbar.exec(media_script, function(state, exit_code)
    if revision == media_revision then
      if exit_code == 0 then
        apply_media_state(state)
      else
        hide_media()
      end
    end
    refresh_running = false
    if refresh_pending then
      refresh_pending = false
      start_refresh()
    end
  end)
end

local function request_refresh()
  media_revision = media_revision + 1
  if refresh_running then
    refresh_pending = true
  else
    start_refresh()
  end
end

media_cover:subscribe({ "spotify_media_change", "music_media_change" }, request_refresh)
media_cover:subscribe({ "forced", "system_woke" }, request_refresh)

media_cover:subscribe("mouse.entered", function(env)
  media_hovered = true
  detail_revision = detail_revision + 1
  animate_detail(true)
end)

media_cover:subscribe("mouse.exited", function(env)
  media_hovered = false
  detail_revision = detail_revision + 1
  animate_detail(false)
end)

media_cover:subscribe("mouse.clicked", function(env)
  media_cover:set({ popup = { drawing = "toggle" }})
end)

media_title:subscribe("mouse.exited.global", function(env)
  media_cover:set({ popup = { drawing = false }})
end)
