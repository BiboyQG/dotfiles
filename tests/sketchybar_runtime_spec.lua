local sketchybar_root = assert(arg[1]) .. "/home/.config/sketchybar"

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local function merge(target, source)
  for key, value in pairs(source or {}) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      merge(target[key], value)
    else
      target[key] = value
    end
  end
end

local function fake_sbar()
  local state = {
    objects = {},
    brackets = {},
    events = {},
    subscriptions = {},
    execs = {},
    triggers = {},
    delays = {},
    delay_seconds = {},
    pushes = {},
    removed = {},
    generated = 0,
  }

  local function new_object(name, properties)
    local object = {
      name = name,
      properties = properties or {},
      callbacks = {},
    }

    function object:set(update)
      self.set_count = (self.set_count or 0) + 1
      merge(self.properties, update)
    end

    function object:push(values)
      table.insert(state.pushes, { values = values })
    end

    function object:subscribe(events, callback)
      if type(events) == "string" then events = { events } end
      for _, event in ipairs(events) do
        self.callbacks[event] = callback
        state.subscriptions[event] = state.subscriptions[event] or {}
        table.insert(state.subscriptions[event], { callback = callback })
      end
    end

    function object:query()
      local popup = type(self.properties.popup) == "table" and self.properties.popup.drawing or false
      return { popup = { drawing = popup == true and "on" or "off" } }
    end

    state.objects[name] = object
    return object
  end

  local sbar = {}

  function sbar.add(kind, first, second, third)
    if kind == "event" then
      state.events[first] = second
      return { name = first }
    end

    local name
    local properties
    local members
    if kind == "bracket" then
      if type(first) == "string" then
        name, members, properties = first, second, third
      else
        state.generated = state.generated + 1
        name, members, properties = "bracket." .. state.generated, first, second
      end
    elseif kind == "graph" then
      name, properties = first, third
    elseif kind == "slider" then
      state.generated = state.generated + 1
      name, properties = "slider." .. state.generated, second
    elseif type(first) == "string" then
      name, properties = first, second
    else
      state.generated = state.generated + 1
      name, properties = "item." .. state.generated, first
    end

    local object = new_object(name, properties)
    if kind == "bracket" then
      for _, member in ipairs(members or {}) do state.brackets[member] = object end
    end
    return object
  end

  function sbar.exec(command, callback)
    table.insert(state.execs, { command = command, callback = callback })
  end

  function sbar.trigger(event)
    table.insert(state.triggers, event)
  end

  function sbar.remove(target)
    expect(target == "/volume.device\\.*/", "unexpected remove target " .. target)
    table.insert(state.removed, target)
    for name in pairs(state.objects) do
      if name:match("^volume%.device%.") then state.objects[name] = nil end
    end
  end

  function sbar.animate(_, _, callback)
    callback()
  end

  function sbar.delay(seconds, callback)
    table.insert(state.delay_seconds, seconds)
    table.insert(state.delays, callback)
  end

  function sbar.set(target, update)
    if target == "/menu\\..*/" then
      for name, object in pairs(state.objects) do
        if name:match("^menu%.") then object:set(update) end
      end
    else
      state.objects[target]:set(update)
    end
  end

  function state.emit(event, env)
    for _, subscription in ipairs(state.subscriptions[event] or {}) do
      subscription.callback(env or {})
    end
  end

  function state.emit_object(name, event, env)
    state.objects[name].callbacks[event](env or {})
  end

  _G.sbar = sbar
  return sbar, state
end

package.loaded.colors = {
  black = "black",
  bg1 = "bg1",
  bg2 = "bg2",
  grey = "grey",
  red = "red",
  blue = "blue",
  green = "green",
  orange = "orange",
  yellow = "yellow",
  white = "white",
  transparent = "transparent",
  with_alpha = function(value) return value end,
}
package.loaded.icons = {
  switch = { on = "ON", off = "OFF" },
  media = { back = "BACK", play_pause = "PLAY", forward = "NEXT" },
  wifi = {
    upload = "UP",
    download = "DOWN",
    router = "ROUTER",
    connected = "CONNECTED",
    disconnected = "DISCONNECTED",
  },
  clipboard = "CLIPBOARD",
  cpu = "CPU",
  battery = { _100 = "B100", _75 = "B75", _50 = "B50", _25 = "B25", _0 = "B0", charging = "CHARGING" },
  volume = { _100 = "V100", _66 = "V66", _33 = "V33", _10 = "V10", _0 = "V0" },
}
package.loaded.settings = {
  font = {
    numbers = "Numbers",
  },
  group_paddings = 5,
  paddings = 5,
  config_dir = "/fake/sketchybar",
}
package.loaded["helpers.app_icons"] = { Arc = "A", kitty = "K", Safari = "S", Default = "D" }
package.loaded["helpers.shell"] = { quote = function(value) return string.format("%q", value) end }
-- layout.lua requires colors and settings when it loads.
package.loaded["helpers.layout"] = dofile(sketchybar_root .. "/helpers/layout.lua")

local function workspace_rows(single_display, focused)
  local rows = {}
  for index = 1, 10 do
    rows[index] = {
      workspace = tostring(index),
      ["workspace-is-focused"] = tostring(index) == focused,
      ["monitor-appkit-nsscreen-screens-id"] = single_display and 1 or (index <= 6 and 2 or 1),
    }
  end
  return rows
end

local function find_object(state, predicate)
  for _, object in pairs(state.objects) do
    if predicate(object) then return object end
  end
  return nil
end

local function complete_full(state, workspaces, windows, workspace_exit, windows_exit)
  local workspace_call = state.execs[#state.execs - 1]
  local window_call = state.execs[#state.execs]
  expect(workspace_call.command:find("list%-workspaces") ~= nil, "expected workspace query")
  expect(window_call.command:find("list%-windows") ~= nil, "expected window query")
  workspace_call.callback(workspaces, workspace_exit or 0)
  window_call.callback(windows, windows_exit or 0)
end

local function test_spaces()
  local sbar, state = fake_sbar()
  sbar.add("item", "front_app", { drawing = true })
  dofile(sketchybar_root .. "/items/spaces.lua")
  dofile(sketchybar_root .. "/items/menus.lua")

  expect(#state.execs == 0, "spaces queried during module load")
  expect(state.objects["space.7"].properties.drawing == false, "workspace 7 bootstrap is unsafe")

  state.emit("forced")
  expect(#state.execs == 2, "forced did not start two parallel queries")
  expect(state.execs[1].command:find("%-%-json") ~= nil, "workspace query is not JSON")
  expect(
    state.execs[1].command:find("monitor%-appkit%-nsscreen%-screens%-id") ~= nil,
    "workspace query omitted AppKit ID"
  )
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "1", ["app-name"] = "Safari" },
    { workspace = "1", ["app-name"] = "Safari" },
    { workspace = "2", ["app-name"] = "Arc" },
  })
  expect(state.objects["space.1"].properties.label.string == "S", "duplicate apps were not collapsed")
  expect(state.objects["space.2"].properties.label.string == "A", "initial Arc icon is missing")
  expect(state.objects["space.7"].properties.display == 1, "single-screen AppKit ID was not applied")

  local before_create = #state.execs
  state.emit("space_windows_change")
  expect(#state.execs == before_create + 2, "window create event did not refresh immediately")
  expect(state.delay_seconds[#state.delay_seconds] == 0.2, "window retry delay is not 0.2 seconds")
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
  })
  expect(state.objects["space.2"].properties.label.string == "A", "early create query changed last-good state")
  state.delays[#state.delays]()
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
    { workspace = "2", ["app-name"] = "kitty" },
  })
  expect(state.objects["space.2"].properties.label.string == "AK", "create retry missed Kitty")

  local before_close = #state.execs
  state.emit("space_windows_change")
  expect(#state.execs == before_close + 2, "window close event did not refresh immediately")
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
    { workspace = "2", ["app-name"] = "kitty" },
  })
  expect(state.objects["space.2"].properties.label.string == "AK", "early close query changed last-good state")
  state.delays[#state.delays]()
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
  })
  expect(state.objects["space.2"].properties.label.string == "A", "close retry left a stale Kitty icon")

  local before_retry_revision = #state.execs
  state.emit("space_windows_change")
  local stale_window_delay = state.delays[#state.delays]
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
  })
  state.emit("space_windows_change")
  local latest_window_delay = state.delays[#state.delays]
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
  })
  expect(#state.execs == before_retry_revision + 4, "window events started an unexpected query count")
  stale_window_delay()
  expect(#state.execs == before_retry_revision + 4, "stale window retry started a refresh")
  latest_window_delay()
  expect(#state.execs == before_retry_revision + 6, "latest window retry did not start one refresh")
  complete_full(state, workspace_rows(true, "3"), {
    { workspace = "2", ["app-name"] = "Arc" },
  })

  local before_front_app = #state.execs
  local before_front_app_delays = #state.delays
  state.emit("front_app_switched")
  expect(#state.execs == before_front_app, "front-app event queried hidden menus or spaces")
  expect(#state.delays == before_front_app_delays, "front-app event scheduled a redundant retry")

  local before_focus = #state.execs
  state.emit("aerospace_workspace_change", { FOCUSED = "4", PREV = "3" })
  expect(#state.execs == before_focus, "focus event ran a full query")
  expect(state.objects["space.3"].properties.icon.highlight == false, "previous focus stayed selected")
  expect(state.objects["space.4"].properties.icon.highlight == true, "new focus was not selected")

  state.emit("display_change")
  complete_full(state, workspace_rows(false, "4"), {})
  expect(state.objects["space.1"].properties.display == 2, "dual-screen workspace 1 mapping failed")
  expect(state.objects["space.7"].properties.display == 1, "dual-screen workspace 7 mapping failed")

  state.emit("swap_menus_and_spaces")
  expect(state.objects["space.1"].properties.drawing == false, "menu mode did not hide spaces")
  state.execs[#state.execs].callback("File\nEdit", 0)
  state.emit("swap_menus_and_spaces")
  expect(state.objects["space.7"].properties.drawing == true, "menu roundtrip lost availability")

  state.emit("space_windows_change")
  local in_flight_count = #state.execs
  state.emit("system_woke")
  state.emit("aerospace_windows_change")
  expect(#state.execs == in_flight_count, "full refreshes did not coalesce")
  complete_full(state, workspace_rows(true, "4"), {})
  expect(#state.execs == in_flight_count + 2, "coalesced rerun count is incorrect")
  complete_full(state, workspace_rows(true, "4"), {})

  local last_good_display = state.objects["space.1"].properties.display
  state.emit("forced")
  complete_full(state, workspace_rows(false, "4"), {}, 0, 1)
  expect(state.objects["space.1"].properties.display == last_good_display, "failed full replaced last-good")

  state.emit("forced")
  state.emit("aerospace_workspace_change", { FOCUSED = "5", PREV = "4" })
  complete_full(state, workspace_rows(true, "4"), {})
  expect(state.objects["space.5"].properties.icon.highlight == true, "focus race lost")
  expect(state.objects["space.4"].properties.icon.highlight == false, "stale full focus won")

  local trigger_count = #state.triggers
  state.emit_object("space.4", "mouse.clicked", { BUTTON = "left" })
  expect(#state.triggers == trigger_count, "left click emitted a duplicate trigger")
  state.emit_object("space.4", "mouse.clicked", { BUTTON = "right" })
  expect(#state.triggers == trigger_count, "right click emitted a duplicate trigger")
  expect(
    state.execs[#state.execs].command == "/opt/homebrew/bin/aerospace move-node-to-workspace --focus-follows-window 4",
    "right-click move command is incorrect"
  )
end

local function test_space_visibility()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/spaces.lua")

  local function expect_visible(workspace, visible, message)
    for _, object in ipairs({
      state.objects["space." .. workspace],
      state.brackets["space." .. workspace],
      state.objects["space.padding." .. workspace],
    }) do
      expect(object.properties.drawing == visible, message .. " (" .. object.name .. ")")
    end
  end

  state.emit("forced")
  complete_full(state, workspace_rows(true, "1"), { { workspace = "7", ["app-name"] = "kitty" } })
  for workspace = 1, 6 do expect_visible(workspace, true, "default workspace is hidden") end
  expect_visible(7, true, "nonempty single-screen workspace is hidden")
  expect_visible(8, false, "unused single-screen workspace is visible")

  local before_focus = #state.execs
  state.emit("aerospace_workspace_change", { FOCUSED = "8", PREV = "1" })
  expect_visible(8, true, "focus did not reveal an empty workspace immediately")
  expect_visible(7, true, "focus change hid a nonempty workspace")
  state.emit("aerospace_workspace_change", { FOCUSED = "9", PREV = "8" })
  expect_visible(8, false, "previous empty workspace stayed visible")
  expect_visible(9, true, "next focused workspace is hidden")
  expect(#state.execs == before_focus, "visibility-only focus change queried AeroSpace")

  state.emit("forced")
  complete_full(state, workspace_rows(true, "9"), {})
  expect_visible(7, false, "closing the last window did not hide an unused workspace")
  expect_visible(9, true, "empty focused workspace was hidden by refresh")

  state.emit("swap_menus_and_spaces")
  expect_visible(9, false, "menu mode did not hide the focused workspace")
  state.emit("aerospace_workspace_change", { FOCUSED = "10", PREV = "9" })
  expect_visible(10, false, "focus change resurrected spaces in menu mode")
  state.emit("forced")
  complete_full(state, workspace_rows(true, "10"), { { workspace = "8", ["app-name"] = "Safari" } })
  expect_visible(8, false, "window refresh resurrected spaces in menu mode")
  state.emit("swap_menus_and_spaces")
  expect_visible(8, true, "leaving menu mode lost a nonempty workspace")
  expect_visible(9, false, "leaving menu mode revealed an unused workspace")
  expect_visible(10, true, "leaving menu mode lost the focused workspace")

  state.emit("display_change")
  complete_full(state, workspace_rows(false, "10"), {})
  for workspace = 1, 10 do expect_visible(workspace, true, "dual-screen workspace is hidden") end
  state.emit("display_change")
  complete_full(state, workspace_rows(true, "10"), { { workspace = "7", ["app-name"] = "kitty" } })
  expect_visible(7, true, "disconnecting a display hid a nonempty workspace")
  expect_visible(8, false, "disconnecting a display retained an unused workspace")
  expect_visible(10, true, "disconnecting a display hid the focused workspace")
end

local function test_menus()
  local sbar, state = fake_sbar()
  sbar.add("item", "front_app", { drawing = true })
  dofile(sketchybar_root .. "/items/menus.lua")

  -- A second toggle must exit menu mode even before the first query completes.
  state.emit("swap_menus_and_spaces")
  local initial_query = state.execs[#state.execs]
  state.emit("swap_menus_and_spaces")
  initial_query.callback("Old App\nFile\nEdit", 0)
  expect(state.objects["menu.1"].properties.drawing == false, "late query reopened hidden menus")
  expect(state.objects["menu.padding"].properties.drawing == false, "late query reopened menu padding")
  expect(state.objects["front_app"].properties.drawing == true, "rapid toggle did not restore the front app")

  state.emit("swap_menus_and_spaces")
  state.execs[#state.execs].callback("Initial App\nFile", 0)
  state.emit("front_app_switched")
  local stale_query = state.execs[#state.execs]
  state.emit("front_app_switched")
  state.execs[#state.execs].callback("Latest App\nFile", 0)
  stale_query.callback("Stale App\nEdit", 0)
  expect(state.objects["menu.1"].properties.label == "Latest App", "stale app query replaced current menus")

  -- A pending refresh cannot restore menus after switching back to spaces.
  state.emit("front_app_switched")
  local closed_mode_query = state.execs[#state.execs]
  state.emit("swap_menus_and_spaces")
  closed_mode_query.callback("Closed App\nFile", 0)
  expect(state.objects["menu.1"].properties.drawing == false, "query resurrected menus after leaving menu mode")

  -- Reopening must also invalidate queries from the previous menu session.
  state.emit("swap_menus_and_spaces")
  local previous_mode_query = state.execs[#state.execs]
  state.emit("swap_menus_and_spaces")
  state.emit("swap_menus_and_spaces")
  previous_mode_query.callback("Closed App\nFile", 0)
  expect(state.objects["menu.1"].properties.drawing == false, "reopening accepted a query from the previous mode")
  state.execs[#state.execs].callback("Reopened App\nFile", 0)
  expect(state.objects["menu.1"].properties.label == "Reopened App", "current mode query was not applied")
  expect(state.objects["menu.1"].properties.drawing == true, "current menus stayed hidden")
end

local function test_focus_refresh()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/spaces.lua")
  local windows = { { workspace = "1", ["app-name"] = "kitty" } }
  state.emit("forced")
  complete_full(state, workspace_rows(true, "1"), windows)
  local initial_count = state.objects["space.1"].set_count
  for _ = 1, 20 do state.emit("aerospace_windows_change") end
  expect(#state.execs == 2, "focus burst queried before its debounce")
  expect(#state.delays == 1, "focus burst created duplicate timers")
  state.delays[1]()
  expect(#state.execs == 3, "focus refresh queried workspace topology again")
  state.execs[3].callback(windows, 0)
  expect(state.objects["space.1"].set_count == initial_count, "unchanged state was redrawn")

  state.emit("aerospace_workspace_change", { FOCUSED = "2", PREV = "1" })
  state.emit("aerospace_windows_change")
  state.delays[2]()
  state.execs[4].callback({ { workspace = "2", ["app-name"] = "kitty" } }, 0)
  expect(state.objects["space.1"].properties.label.string == " —", "move left a stale source icon")
  expect(state.objects["space.2"].properties.label.string == "K", "move missed the destination icon")
  expect(state.objects["space.2"].properties.icon.highlight, "cached topology overwrote current focus")
end

-- At login AeroSpace may not be listening yet; the bar retries its first
-- topology query until it succeeds and never retries after that.
local function test_spaces_startup_retry()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/spaces.lua")

  state.emit("forced")
  complete_full(state, nil, nil, 1, 1)
  expect(#state.delays == 1 and state.delay_seconds[1] == 1, "failed startup query did not schedule a retry")
  state.emit("forced")
  complete_full(state, nil, nil, 1, 1)
  expect(#state.delays == 1, "overlapping failures scheduled duplicate retries")
  state.delays[1]()
  expect(#state.execs == 6, "startup retry did not query AeroSpace")
  complete_full(state, {}, {})
  expect(#state.delays == 2, "unparseable startup output did not schedule a retry")
  state.delays[2]()
  complete_full(state, workspace_rows(true, "3"), { { workspace = "2", ["app-name"] = "Arc" } })
  expect(state.objects["space.3"].properties.icon.highlight == true, "startup retry did not apply the topology")
  expect(state.objects["space.2"].properties.label.string == "A", "startup retry did not apply the windows")

  state.emit("forced")
  complete_full(state, nil, nil, 1, 1)
  expect(#state.delays == 2, "failure after the first success scheduled a retry")
  state.emit("aerospace_windows_change")
  expect(#state.delays == 3, "window event after startup did not use its own debounce")
  state.delays[3]()
  state.execs[#state.execs].callback(nil, 1)
  expect(#state.delays == 3, "failed cached refresh scheduled a startup retry")

  _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/spaces.lua")
  state.emit("forced")
  for attempt = 1, 30 do
    complete_full(state, nil, nil, 1, 1)
    expect(#state.delays == attempt, "startup retry " .. attempt .. " was not scheduled")
    state.delays[attempt]()
  end
  complete_full(state, nil, nil, 1, 1)
  expect(#state.delays == 30, "startup retries did not stop at the cap")
end

local function test_media()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/media.lua")

  expect(
    state.events.spotify_media_change == "com.spotify.client.PlaybackStateChanged",
    "Spotify event mapping failed"
  )
  expect(state.events.music_media_change == "com.apple.Music.playerInfo", "Music event mapping failed")
  expect(#state.execs == 0, "media queried during module load")

  local cover
  local artist
  for _, object in pairs(state.objects) do
    if type(object.properties.background) == "table"
      and type(object.properties.background.image) == "table"
      and object.properties.background.image.scale == 0.85
    then
      cover = object
    elseif type(object.properties.label) == "table" and object.properties.label.max_chars == 18 then
      artist = object
    end
  end
  expect(cover and artist, "media objects are missing")

  state.emit("forced")
  expect(#state.execs == 1, "forced media query count is incorrect")
  state.execs[1].callback({ playing = true, artist = "A", title = "T", artwork = "/tmp/art" }, 0)
  expect(cover.properties.drawing == true, "playing media is hidden")
  expect(cover.properties.background.image.string == "/tmp/art", "artwork path was not applied")

  state.emit("spotify_media_change", { INFO = { ["Player State"] = "Paused" } })
  expect(cover.properties.drawing == true, "notification hid media before checking global state")
  state.execs[#state.execs].callback({
    playing = true,
    artist = "Other player",
    title = "Still playing",
    artwork = "",
  }, 0)
  expect(cover.properties.drawing == true, "another active player was hidden")
  expect(artist.properties.label.string == "Other player", "global media state was not applied")

  state.emit("spotify_media_change", { INFO = { ["Player State"] = "Stopped" } })
  state.execs[#state.execs].callback({ playing = false }, 0)
  expect(cover.properties.drawing == false, "stopped global media state stayed visible")

  state.emit("music_media_change", { INFO = { ["Player State"] = "Playing" } })
  local first_refresh_count = #state.execs
  state.emit("music_media_change", { INFO = { ["Player State"] = "Playing" } })
  expect(#state.execs == first_refresh_count, "media refreshes did not coalesce")
  state.execs[#state.execs].callback({ playing = true, artist = "stale", title = "stale", artwork = "" }, 0)
  expect(#state.execs == first_refresh_count + 1, "coalesced media rerun is missing")
  state.execs[#state.execs].callback({ playing = true, artist = "new", title = "new", artwork = "" }, 0)
  expect(artist.properties.label.string == "new", "latest media state did not win")
  expect(cover.properties.background.image.drawing == false, "missing artwork left a stale image")

  state.emit_object(cover.name, "mouse.entered", {})
  state.emit("music_media_change", { INFO = { ["Player State"] = "Playing" } })
  state.execs[#state.execs].callback({ playing = true, artist = "hovered", title = "hovered", artwork = "" }, 0)
  state.delays[#state.delays]()
  expect(artist.properties.label.width == "dynamic", "refresh timer collapsed hovered media details")
  state.emit_object(cover.name, "mouse.exited", {})
  expect(artist.properties.label.width == 0, "mouse exit did not collapse media details")

  state.emit("system_woke")
  state.execs[#state.execs].callback("failed", 1)
  expect(cover.properties.drawing == false, "media command failure left stale UI")
end

local function test_wifi()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/widgets/wifi.lua")

  expect(#state.execs == 1, "wifi module did not resolve the Wi-Fi interface first")
  expect(state.execs[1].command:find("listallhardwareports") ~= nil, "Wi-Fi interface lookup is missing")
  state.execs[1].callback("en1\n", 0)
  expect(#state.execs == 2, "interface lookup did not start the network provider")
  expect(
    state.execs[2].command:find("network_load en1 network_update", 1, true) ~= nil,
    "network provider does not use the resolved interface"
  )

  expect(state.subscriptions.system_woke == nil, "wake-time ipconfig path is still subscribed")
  local wifi = state.objects["widgets.wifi.padding"]
  state.emit_object("widgets.wifi1", "network_update", {
    upload = "100 Bps",
    download = "000 Bps",
    connected = "on",
  })
  expect(wifi.properties.icon.string == "CONNECTED", "connected=on failed")
  state.emit_object("widgets.wifi1", "network_update", {
    upload = "000 Bps",
    download = "000 Bps",
    connected = "off",
  })
  expect(wifi.properties.icon.string == "DISCONNECTED", "connected=off failed")

  state.emit_object("widgets.wifi1", "mouse.clicked", {})
  local popup_ip_lookup = false
  local info_lookups = 0
  local lookups = {}
  for _, exec in ipairs(state.execs) do
    if exec.command == "ipconfig getifaddr en1" then popup_ip_lookup = true end
    if exec.command:find("getinfo Wi-Fi", 1, true) then info_lookups = info_lookups + 1 end
    for _, key in ipairs({ "getcomputername", "getsummary", "getinfo Wi-Fi" }) do
      if exec.command:find(key, 1, true) then lookups[key] = exec end
    end
  end
  expect(popup_ip_lookup, "popup IP lookup does not use the resolved interface")
  expect(info_lookups == 1 and lookups["getinfo Wi-Fi"].command == "networksetup -getinfo Wi-Fi", "mask and router are not read from one networksetup call")

  local function row(title)
    return find_object(state, function(object)
      return type(object.properties.icon) == "table" and object.properties.icon.string == title
    end)
  end
  local hostname, mask, router, ssid = row("Hostname:"), row("Subnet mask:"), row("Router:"), row("ROUTER")
  expect(hostname and mask and router and ssid, "wifi popup rows are missing")
  lookups["getinfo Wi-Fi"].callback("DHCP Configuration\nIP address: 10.0.0.2\nSubnet mask: 255.255.255.0\nRouter: 10.0.0.1\nClient ID: \nIPv6: Automatic\nIPv6 Router: fe80::1\nWi-Fi ID: aa:bb\n", 0)
  expect(mask.properties.label.string == "255.255.255.0", "subnet mask was not parsed")
  expect(router.properties.label.string == "10.0.0.1", "router was not parsed from its own line")
  lookups["getcomputername"].callback("host\n", 0)
  expect(hostname.properties.label.string == "host", "hostname was not trimmed")
  lookups["getsummary"].callback("<redacted>\n", 0)
  expect(ssid.properties.label.string == "Unavailable", "redacted SSID is shown")
  local before_ssid_click = #state.execs
  state.emit_object(ssid.name, "mouse.clicked", { NAME = ssid.name })
  expect(#state.execs == before_ssid_click, "unavailable SSID was copied")

  -- A second click within the restore second copies the real value, not the
  -- glyph, and only the latest restore applies.
  local delays_before = #state.delays
  state.emit_object(hostname.name, "mouse.clicked", { NAME = hostname.name })
  expect(hostname.properties.label.string == "CLIPBOARD", "copy did not show the clipboard glyph")
  expect(state.execs[#state.execs].command == 'printf %s "host" | pbcopy', "copied value is wrong")
  state.emit_object(hostname.name, "mouse.clicked", { NAME = hostname.name })
  expect(state.execs[#state.execs].command == 'printf %s "host" | pbcopy', "second click copied the glyph")
  expect(#state.delays == delays_before + 2, "copy restores are missing")
  state.delays[delays_before + 1]()
  expect(hostname.properties.label.string == "CLIPBOARD", "stale restore replaced the glyph early")
  state.delays[delays_before + 2]()
  expect(hostname.properties.label.string == "host" and hostname.properties.label.align == "right", "label was not restored")
end

local function test_battery()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/widgets/battery.lua")
  local battery = state.objects["widgets.battery"]
  local bracket = state.brackets["widgets.battery"]
  local padding = state.objects["widgets.battery.padding"]
  expect(battery and bracket and padding, "battery objects are missing")
  expect(#state.execs == 0, "battery queried during module load")

  local function report(text)
    state.execs[#state.execs].callback(text)
  end

  state.emit("forced")
  expect(#state.execs == 1, "forced did not query the battery")
  expect(state.execs[1].command == "pmset -g batt", "battery query command is wrong")
  report("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t15%; discharging; 1:05 remaining present: true\n")
  expect(battery.properties.icon.string == "B0", "low charge icon is wrong")
  expect(battery.properties.icon.color == "red", "low charge color is wrong")
  expect(battery.properties.label.string == "15%", "charge label is wrong")
  expect(battery.properties.drawing == true, "battery is hidden with a battery present")
  expect(bracket.properties.drawing == true and padding.properties.drawing == true, "battery group is hidden")

  state.emit("routine")
  report("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t85%; charging; 0:30 remaining present: true\n")
  expect(battery.properties.icon.string == "CHARGING", "charging icon is wrong")
  expect(battery.properties.icon.color == "green", "charging color is wrong")
  expect(battery.properties.label.string == "85%", "charging label is wrong")

  state.emit("system_woke")
  report("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t7%; discharging; 0:10 remaining present: true\n")
  expect(battery.properties.label.string == "07%", "single-digit charge is not zero-padded")

  -- The bolt means the battery is charging, not that the adapter is plugged in.
  state.emit("routine")
  report("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t80%; AC attached; not charging present: true\n")
  expect(battery.properties.icon.string == "B75", "plugged-in but not charging shows the bolt")
  expect(battery.properties.icon.color == "green", "plugged-in colour is wrong")
  state.emit("routine")
  report("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t100%; charged; 0:00 remaining present: true\n")
  expect(battery.properties.icon.string == "B100", "a charged battery shows the bolt")
  state.emit("routine")
  report("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t15%; AC attached; not charging present: true\n")
  expect(battery.properties.icon.string == "B0" and battery.properties.icon.color == "red", "low charge on AC is not flagged")
  state.emit("routine")
  report("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t96%; finishing charge; 0:05 remaining present: true\n")
  expect(battery.properties.icon.string == "CHARGING", "finishing charge does not show the bolt")

  -- The popup fetches a fresh estimate when it opens, the routine keeps it
  -- current, and leaving the bar closes it.
  local remaining = find_object(state, function(object) return object.properties.position == "popup.widgets.battery" end)
  expect(remaining, "remaining-time popup row is missing")
  expect(remaining.properties.icon.string == "Time to full:", "charging popup row is not labelled as time to full")
  expect(remaining.properties.label.string == "0:05h", "routine did not refresh the remaining time")
  local before_click = #state.execs
  state.emit_object("widgets.battery", "mouse.clicked", {})
  expect(battery.properties.popup.drawing == true, "click did not open the popup")
  expect(#state.execs == before_click + 1 and state.execs[#state.execs].command == "pmset -g batt", "opening the popup did not query pmset")
  report("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t60%; discharging; 3:20 remaining present: true\n")
  expect(remaining.properties.icon.string == "Time remaining:" and remaining.properties.label.string == "3:20h", "popup estimate is wrong")
  state.emit_object("widgets.battery", "mouse.exited.global", {})
  expect(battery.properties.popup.drawing == false, "leaving the bar did not close the popup")
  state.emit_object("widgets.battery", "mouse.clicked", {})
  state.emit_object("widgets.battery", "mouse.clicked", {})
  expect(battery.properties.popup.drawing == false, "second click did not close the popup")
  expect(#state.execs == before_click + 2, "closing the popup queried pmset")
  report("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t60%; discharging; (no estimate) present: true\n")
  expect(remaining.properties.label.string == "No estimate", "missing estimate is not reported")

  state.emit("power_source_change")
  report("Now drawing from 'AC Power'\n")
  expect(battery.properties.drawing == false, "battery stays visible without a battery")
  expect(bracket.properties.drawing == false and padding.properties.drawing == false, "battery group stays visible without a battery")
end

local function test_cpu()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/widgets/cpu.lua")
  expect(#state.execs == 1, "cpu module did not start its event provider")
  expect(state.execs[1].command:find("cpu_load cpu_update 2.0", 1, true) ~= nil, "cpu provider command is wrong")
  local cpu = state.objects["widgets.cpu"]
  expect(cpu and cpu.properties.graph.color == "blue", "cpu graph is missing")

  local cases = {
    { load = "10", color = "blue" },
    { load = "45", color = "yellow" },
    { load = "70", color = "orange" },
    { load = "90", color = "red" },
  }
  for index, case in ipairs(cases) do
    state.emit_object("widgets.cpu", "cpu_update", { total_load = case.load })
    expect(cpu.properties.graph.color == case.color, "cpu color for " .. case.load .. "% is wrong")
    expect(cpu.properties.label == "cpu " .. case.load .. "%", "cpu label for " .. case.load .. "% is wrong")
    expect(#state.pushes == index, "cpu graph push count is wrong")
    expect(state.pushes[index].values[1] == tonumber(case.load) / 100, "cpu graph push value is wrong")
  end
end

local function test_volume()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/widgets/volume.lua")
  local percent = state.objects["widgets.volume1"]
  local icon = state.objects["widgets.volume2"]
  local slider = find_object(state, function(object) return type(object.properties.slider) == "table" end)
  expect(percent and icon and slider, "volume objects are missing")

  local cases = {
    { volume = "0", label = "00%", icon = "V0" },
    { volume = "5", label = "05%", icon = "V10" },
    { volume = "20", label = "20%", icon = "V33" },
    { volume = "50", label = "50%", icon = "V66" },
    { volume = "75", label = "75%", icon = "V100" },
  }
  for _, case in ipairs(cases) do
    state.emit_object("widgets.volume1", "volume_change", { INFO = case.volume })
    expect(percent.properties.label == case.label, "volume label for " .. case.volume .. " is wrong")
    expect(icon.properties.label == case.icon, "volume icon for " .. case.volume .. " is wrong")
    expect(slider.properties.slider.percentage == tonumber(case.volume), "volume slider for " .. case.volume .. " is wrong")
  end

  state.emit_object("widgets.volume2", "mouse.clicked", { BUTTON = "right" })
  expect(state.execs[#state.execs].command:find("Sound", 1, true) ~= nil, "right click did not open sound settings")

  local function open_devices()
    state.emit_object("widgets.volume2", "mouse.clicked", { BUTTON = "left" })
    return state.execs[#state.execs]
  end

  local function close_devices()
    state.emit_object("widgets.volume1", "mouse.exited.global", {})
  end

  -- Leaving the bar with nothing open sends no hide or remove commands.
  local removed_before = #state.removed
  close_devices()
  expect(#state.removed == removed_before, "closing an already closed popup sent a remove")

  local closed_query = open_devices()
  close_devices()
  local after_close = #state.execs
  closed_query.callback("Old Speakers\n", 0)
  expect(#state.execs == after_close, "closed popup continued its device query")
  expect(state.objects["volume.device.0"] == nil, "closed popup contains a device")

  local old_query = open_devices()
  close_devices()
  local current_query = open_devices()
  local after_reopen = #state.execs
  old_query.callback("Old Speakers\n", 0)
  expect(#state.execs == after_reopen, "reopening accepted an old current-device query")
  current_query.callback("Speakers\n", 0)
  local old_list_query = state.execs[#state.execs]
  close_devices()
  current_query = open_devices()
  current_query.callback("Headphones\n", 0)
  state.execs[#state.execs].callback("Speakers\nHeadphones\n", 0)
  expect(state.objects["volume.device.1"].properties.label.color == "white", "current device is not highlighted")
  old_list_query.callback("Detached Device\n", 0)
  expect(state.objects["volume.device.0"].properties.label.string == "Speakers", "old device list replaced the current session")
  expect(state.objects["volume.device.1"].properties.label.string == "Headphones", "old list removed the current device")

  close_devices()
  expect(state.objects["volume.device.0"] == nil and state.objects["volume.device.1"] == nil, "closing did not remove device items")
  removed_before = #state.removed
  close_devices()
  expect(#state.removed == removed_before, "a second bar exit removed again")
  current_query = open_devices()
  current_query.callback("Speakers", 0)
  state.execs[#state.execs].callback("Speakers\n", 0)
  expect(state.objects["volume.device.0"].properties.label.color == "white", "current device without trailing newline is not highlighted")
  expect(state.objects["volume.device.1"] == nil, "shorter list retained a disconnected device")

  close_devices()
  current_query = open_devices()
  current_query.callback("Speakers\n", 0)
  local closed_list_query = state.execs[#state.execs]
  close_devices()
  closed_list_query.callback("Speakers\nDetached Device\n", 0)
  expect(state.objects["volume.device.0"] == nil, "late list callback populated a closed popup")

  current_query = open_devices()
  local before_failure = #state.execs
  current_query.callback("Error finding device\n", 1)
  expect(#state.execs == before_failure, "failed current-device query started another command")
  close_devices()
  current_query = open_devices()
  current_query.callback("Speakers\n", 0)
  state.execs[#state.execs].callback("Error listing devices\n", 1)
  expect(state.objects["volume.device.0"] == nil, "failed device query rendered its error as a device")

  -- Scroll steps keep one osascript in flight; later steps coalesce into the
  -- latest absolute target, clamped to 0-100.
  state.emit_object("widgets.volume1", "volume_change", { INFO = "50" })
  local before_scroll = #state.execs
  state.emit_object("widgets.volume2", "mouse.scrolled", { INFO = { delta = "1" } })
  expect(#state.execs == before_scroll + 1, "scroll did not start a volume update")
  local first_step = state.execs[#state.execs]
  expect(first_step.command == 'osascript -e "set volume output volume 60"', "scroll target is wrong: " .. first_step.command)
  state.emit_object("widgets.volume2", "mouse.scrolled", { INFO = { delta = "1" } })
  state.emit_object("widgets.volume1", "mouse.scrolled", { INFO = { delta = "-1", modifier = "ctrl" } })
  expect(#state.execs == before_scroll + 1, "scroll steps ran concurrently")
  first_step.callback("", 0)
  expect(#state.execs == before_scroll + 2, "coalesced scroll steps were not applied")
  expect(state.execs[#state.execs].command == 'osascript -e "set volume output volume 69"', "coalesced target is wrong: " .. state.execs[#state.execs].command)
  state.execs[#state.execs].callback("", 0)
  expect(#state.execs == before_scroll + 2, "idle scroll chain ran another command")
  state.emit_object("widgets.volume1", "volume_change", { INFO = "95" })
  state.emit_object("widgets.volume2", "mouse.scrolled", { INFO = { delta = "3" } })
  expect(state.execs[#state.execs].command == 'osascript -e "set volume output volume 100"', "scroll target is not clamped")
  state.execs[#state.execs].callback("", 0)
  state.emit_object("widgets.volume2", "mouse.scrolled", { INFO = { delta = "-1", modifier = "ctrl" } })
  expect(state.execs[#state.execs].command == 'osascript -e "set volume output volume 99"', "scroll after a clamp did not continue from the applied level")
end

local function test_calendar()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/calendar.lua")
  local calendar = find_object(state, function(object) return object.properties.click_script == "open -a 'Calendar'" end)
  expect(calendar, "calendar item is missing")
  expect(calendar.properties.icon.string == nil, "calendar rendered before its first update")

  expect(calendar.properties.update_freq == nil and state.subscriptions.routine == nil, "calendar still polls on routine")

  state.emit("forced")
  expect(tostring(calendar.properties.icon):match("^%a+%. %d%d %a+%.$") ~= nil, "calendar date format is wrong")
  expect(tostring(calendar.properties.label):match("^%d%d:%d%d$") ~= nil, "calendar time format is wrong")

  -- The clock re-arms itself for the next minute boundary; a restart on wake
  -- ends the previous chain so a late timer cannot start a second one.
  expect(#state.delays == 1, "forced did not arm the minute timer")
  local seconds = state.delay_seconds[1]
  expect(math.type(seconds) == "integer" and seconds >= 1 and seconds <= 60, "minute timer is not aligned to the boundary")
  state.delays[1]()
  expect(#state.delays == 2, "minute tick did not re-arm the timer")
  state.emit("system_woke")
  expect(#state.delays == 3, "wake did not restart the clock")
  local sets = calendar.set_count
  state.delays[2]()
  expect(#state.delays == 3 and calendar.set_count == sets, "stale minute timer kept ticking")
  state.delays[3]()
  expect(#state.delays == 4 and calendar.set_count == sets + 1, "current minute timer stopped ticking")
end

local function load_ai_usage()
  local _, state = fake_sbar()
  dofile(sketchybar_root .. "/items/ai_usage.lua")
  return state
end

local function usage_output(codex_status, claude_status, codex_session, codex_weekly, claude_session, claude_weekly)
  return table.concat({
    "codex_status=" .. codex_status,
    "codex_session=" .. (codex_session or "--"),
    "codex_weekly=" .. (codex_weekly or "--"),
    "codex_bar=/tmp/codex-" .. (codex_session or "--") .. ".png",
    "claude_status=" .. claude_status,
    "claude_session=" .. (claude_session or "--"),
    "claude_weekly=" .. (claude_weekly or "--"),
    "claude_bar=/tmp/claude.png",
  }, "\n")
end

local function test_ai_usage()
  local state = load_ai_usage()
  expect(#state.execs == 0, "usage queried during module load")
  local session = state.objects["ai_usage.codex.session_percent"]
  local weekly = state.objects["ai_usage.codex.weekly_percent"]
  local bar = state.objects["ai_usage.codex.bar"]
  local popup_claude_session = state.objects["ai_usage.popup.claude.session_percent"]
  local popup_claude_weekly = state.objects["ai_usage.popup.claude.weekly_percent"]
  expect(session and weekly and bar and popup_claude_session and popup_claude_weekly, "usage objects are missing")

  state.emit("forced")
  expect(#state.execs == 1, "forced did not query usage")
  expect(state.execs[1].command:find("scripts/ai_usage.sh", 1, true) ~= nil, "usage script path is wrong")
  state.execs[1].callback(usage_output("ok", "ok", "75", "30", "15", "--"))
  expect(session.properties.label.string == "75%", "session percentage is wrong")
  expect(session.properties.label.color == "white", "healthy session color is wrong")
  expect(weekly.properties.label.string == "30%", "weekly percentage is wrong")
  expect(weekly.properties.label.color == "yellow", "low weekly color is wrong")
  expect(bar.properties.background.image.string == "/tmp/codex-75.png", "bar image was not applied")
  expect(popup_claude_session.properties.label.string == "15%", "popup session percentage is wrong")
  expect(popup_claude_session.properties.label.color == "red", "critical session color is wrong")
  expect(popup_claude_session.properties.width == 34, "single-scope session width is wrong")
  expect(popup_claude_weekly.properties.label.drawing == false, "missing weekly quota is drawn")

  state.emit("routine")
  state.emit("system_woke")
  expect(#state.execs == 3, "overlapping refreshes were not started")
  state.execs[3].callback(usage_output("ok", "ok", "50", "50", "50", "50"))
  state.execs[2].callback(usage_output("ok", "ok", "99", "99", "99", "99"))
  expect(session.properties.label.string == "50%", "stale usage response overwrote the latest one")
  expect(bar.properties.background.image.string == "/tmp/codex-50.png", "stale bar overwrote the latest one")

  -- Opening the popup refreshes usage; closing it does not, and leaving the
  -- bar closes it through a single mouse.exited.global subscription.
  local bracket = state.brackets["ai_usage.codex.logo"]
  local before_toggle = #state.execs
  state.emit_object("ai_usage.codex.logo", "mouse.clicked", {})
  expect(#state.execs == before_toggle + 1, "opening the popup did not refresh usage")
  expect(bracket.properties.popup.drawing == true, "click did not open the popup")
  state.emit_object("ai_usage.codex.bar", "mouse.clicked", {})
  expect(#state.execs == before_toggle + 1, "closing the popup refreshed usage")
  expect(bracket.properties.popup.drawing == false, "second click did not close the popup")
  state.emit_object("ai_usage.codex.weekly_percent", "mouse.clicked", {})
  expect(bracket.properties.popup.drawing == true, "third click did not reopen the popup")
  expect(#state.subscriptions["mouse.exited.global"] == 1, "more than one usage item subscribes to mouse.exited.global")
  state.emit("mouse.exited.global")
  expect(bracket.properties.popup.drawing == false, "leaving the bar did not close the popup")
end

-- At login the first fetch can run before OpenUsage listens; the item retries
-- a refused connection until one fetch reaches both providers.
local function test_ai_usage_startup_retry()
  local state = load_ai_usage()
  local session = state.objects["ai_usage.codex.session_percent"]
  state.emit("forced")
  state.execs[1].callback(usage_output("unavailable", "unavailable"))
  expect(#state.delays == 1 and state.delay_seconds[1] == 5, "refused first fetch did not schedule a retry")
  expect(session.properties.label.drawing == false, "unavailable usage kept a session value")
  state.delays[1]()
  expect(#state.execs == 2, "startup retry did not run the usage script")
  state.emit("routine")
  state.execs[2].callback(usage_output("unavailable", "unavailable"))
  expect(#state.delays == 1, "stale response scheduled a retry")
  state.execs[3].callback(usage_output("ok", "unavailable", "75"))
  expect(#state.delays == 2, "half-available response did not retry")
  expect(session.properties.label.string == "75%", "partial response was not rendered")
  state.delays[2]()
  state.execs[4].callback(usage_output("ok", "empty", "60"))
  expect(#state.delays == 2, "response reaching both providers scheduled a retry")
  state.emit("routine")
  state.execs[5].callback(usage_output("unavailable", "unavailable"))
  expect(#state.delays == 2, "outage after the first full response scheduled a retry")

  -- A provider that is down for another reason is not a startup race.
  state = load_ai_usage()
  state.emit("forced")
  state.execs[1].callback(usage_output("empty", "parse_error"))
  expect(#state.delays == 0, "empty or unparseable usage scheduled a retry")
  state.emit("routine")
  state.execs[2].callback(usage_output("unavailable", "unavailable"))
  expect(#state.delays == 0, "retry started after a response had already arrived")

  -- A provider that never answers stops costing script runs after 12 retries.
  state = load_ai_usage()
  state.emit("forced")
  for attempt = 1, 12 do
    state.execs[#state.execs].callback(usage_output("unavailable", "empty"))
    expect(#state.delays == attempt, "startup retry " .. attempt .. " was not scheduled")
    state.delays[attempt]()
  end
  state.execs[#state.execs].callback(usage_output("unavailable", "empty"))
  expect(#state.delays == 12, "startup retries did not stop at the cap")
  expect(#state.execs == 13, "capped retries ran an unexpected number of fetches")
end

test_spaces()
test_space_visibility()
test_spaces_startup_retry()
test_menus()
test_focus_refresh()
test_media()
test_wifi()
test_battery()
test_cpu()
test_volume()
test_calendar()
test_ai_usage()
test_ai_usage_startup_retry()
print("SketchyBar runtime fixtures passed.")
