local sketchybar_root = (arg[1] or ".") .. "/home/.config/sketchybar"

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
    set_targets = {},
    delays = {},
    delay_seconds = {},
    pushes = {},
    removed = {},
    generated = 0,
  }

  local function new_object(name, properties, members)
    local object = {
      name = name,
      properties = properties or {},
      members = members,
      callbacks = {},
    }

    function object:set(update)
      merge(self.properties, update)
    end

    function object:push(values)
      table.insert(state.pushes, { name = self.name, values = values })
    end

    function object:subscribe(events, callback)
      if type(events) == "string" then events = { events } end
      for _, event in ipairs(events) do
        self.callbacks[event] = callback
        state.subscriptions[event] = state.subscriptions[event] or {}
        table.insert(state.subscriptions[event], { object = self, callback = callback })
      end
    end

    function object:query()
      local icon = type(self.properties.icon) == "table" and self.properties.icon.string or nil
      local popup = type(self.properties.popup) == "table" and self.properties.popup.drawing or false
      return {
        icon = { value = icon },
        popup = { drawing = popup == true and "on" or "off" },
        geometry = { drawing = self.properties.drawing == false and "off" or "on" },
      }
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

    local object = new_object(name, properties, members)
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
    table.insert(state.removed, target)
  end

  function sbar.animate(_, _, callback)
    callback()
  end

  function sbar.delay(seconds, callback)
    table.insert(state.delay_seconds, seconds)
    table.insert(state.delays, callback)
  end

  function sbar.set(target, update)
    table.insert(state.set_targets, target)
    if target == "/menu\\..*/" then
      for name, object in pairs(state.objects) do
        if name:match("^menu%.") then object:set(update) end
      end
    else
      state.objects[target]:set(update)
    end
  end

  function sbar.query(name)
    return state.objects[name]:query()
  end

  function state.emit(event, env)
    for _, subscription in ipairs(state.subscriptions[event] or {}) do
      subscription.callback(env or {})
    end
  end

  function state.emit_object(name, event, env)
    state.objects[name].callbacks[event](env or {})
  end

  return sbar, state
end

local function load_modules()
  for _, name in ipairs({ "colors", "icons", "settings", "helpers.app_icons", "helpers.shell" }) do
    package.loaded[name] = nil
  end

  package.preload.colors = function()
    return {
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
  end
  package.preload.icons = function()
    return {
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
  end
  package.preload.settings = function()
    return {
      font = {
        text = "Text",
        numbers = "Numbers",
        style_map = { Regular = "Regular", Bold = "Bold", Heavy = "Heavy", Semibold = "Semibold", Black = "Black" },
      },
      group_paddings = 5,
      paddings = 5,
    }
  end
  package.preload["helpers.app_icons"] = function()
    return { Arc = "A", kitty = "K", Safari = "S", Music = "M", Default = "D" }
  end
  package.preload["helpers.shell"] = function()
    return { quote = function(value) return string.format("%q", value) end }
  end
end

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

local function test_app_icons()
  local app_icons = dofile(sketchybar_root .. "/helpers/app_icons.lua")
  expect(app_icons.Preview == ":preview:", "Preview does not use its dedicated icon")
  expect(app_icons.Skim == ":pdf_old:", "Skim does not use an existing PDF glyph")
  expect(app_icons.superProductivity == ":super_productivity:", "superProductivity glyph name is wrong")
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
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
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
  expect(state.objects["space.7"].properties.drawing == false, "single-screen workspace 7 is visible")
  expect(state.brackets["space.7"].properties.drawing == false, "single-screen bracket 7 is visible")
  expect(state.objects["space.padding.7"].properties.drawing == false, "single-screen padding 7 is visible")

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
  expect(#state.execs == before_front_app + 1, "front-app event started a redundant spaces query")
  expect(state.execs[#state.execs].command:find("menus") ~= nil, "front-app menu refresh is missing")
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
  expect(state.objects["space.7"].properties.drawing == true, "dual-screen workspace 7 is hidden")

  state.emit("swap_menus_and_spaces")
  expect(state.objects["space.1"].properties.drawing == false, "menu mode did not hide spaces")
  state.execs[#state.execs].callback("File\nEdit", 0)
  state.emit("swap_menus_and_spaces")
  expect(state.objects["space.7"].properties.drawing == true, "menu roundtrip lost availability")
  for _, target in ipairs(state.set_targets) do
    expect(target ~= "/space\\..*/", "menus.lua overwrote workspace drawing")
  end

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

local function test_media()
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
  dofile(sketchybar_root .. "/items/media.lua")

  expect(
    state.events.spotify_media_change == "com.spotify.client.PlaybackStateChanged",
    "Spotify event mapping failed"
  )
  expect(state.events.music_media_change == "com.apple.Music.playerInfo", "Music event mapping failed")
  expect(state.subscriptions.media_change == nil, "deprecated media_change is subscribed")
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
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
  dofile(sketchybar_root .. "/items/widgets/wifi.lua")

  expect(#state.execs == 1, "wifi module did not resolve the Wi-Fi interface first")
  expect(state.execs[1].command:find("listallhardwareports") ~= nil, "Wi-Fi interface lookup is missing")
  state.execs[1].callback("en1\n", 0)
  expect(#state.execs == 2, "interface lookup did not start the network provider")
  expect(
    state.execs[2].command:find("network_load en1 network_update", 1, true) ~= nil,
    "network provider does not use the resolved interface"
  )

  expect(state.subscriptions.wifi_change == nil, "deprecated wifi_change is subscribed")
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
  state.emit_object("widgets.wifi1", "network_update", {
    upload = "000 Bps",
    download = "000 Bps",
    connected = "unknown",
  })
  expect(wifi.properties.icon.string == "DISCONNECTED", "unknown did not preserve last-good")

  state.emit_object("widgets.wifi1", "mouse.clicked", {})
  local popup_ip_lookup = false
  for _, exec in ipairs(state.execs) do
    if exec.command == "ipconfig getifaddr en1" then popup_ip_lookup = true end
  end
  expect(popup_ip_lookup, "popup IP lookup does not use the resolved interface")
end

local function find_object(state, predicate)
  for _, object in pairs(state.objects) do
    if predicate(object) then return object end
  end
  return nil
end

local function test_battery()
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
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

  state.emit("power_source_change")
  report("Now drawing from 'AC Power'\n")
  expect(battery.properties.drawing == false, "battery stays visible without a battery")
  expect(bracket.properties.drawing == false and padding.properties.drawing == false, "battery group stays visible without a battery")
end

local function test_cpu()
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
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
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
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
end

local function test_calendar()
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
  dofile(sketchybar_root .. "/items/calendar.lua")
  local calendar = find_object(state, function(object) return object.properties.click_script == "open -a 'Calendar'" end)
  expect(calendar, "calendar item is missing")
  expect(calendar.properties.icon.string == nil, "calendar rendered before its first update")

  state.emit("forced")
  expect(tostring(calendar.properties.icon):match("^%a+%. %d%d %a+%.$") ~= nil, "calendar date format is wrong")
  expect(tostring(calendar.properties.label):match("^%d%d:%d%d$") ~= nil, "calendar time format is wrong")
end

local function test_ai_usage()
  load_modules()
  local sbar, state = fake_sbar()
  _G.sbar = sbar
  dofile(sketchybar_root .. "/items/ai_usage.lua")
  expect(#state.execs == 0, "usage queried during module load")
  local session = state.objects["ai_usage.codex.session_percent"]
  local weekly = state.objects["ai_usage.codex.weekly_percent"]
  local bar = state.objects["ai_usage.codex.bar"]
  local popup_claude_session = state.objects["ai_usage.popup.claude.session_percent"]
  local popup_claude_weekly = state.objects["ai_usage.popup.claude.weekly_percent"]
  expect(session and weekly and bar and popup_claude_session and popup_claude_weekly, "usage objects are missing")

  local function usage(codex_session, codex_weekly, claude_session, claude_weekly)
    return table.concat({
      "codex_status=ok",
      "codex_session=" .. codex_session,
      "codex_weekly=" .. codex_weekly,
      "codex_bar=/tmp/codex-" .. codex_session .. ".png",
      "claude_status=ok",
      "claude_session=" .. claude_session,
      "claude_weekly=" .. claude_weekly,
      "claude_bar=/tmp/claude.png",
    }, "\n")
  end

  state.emit("forced")
  expect(#state.execs == 1, "forced did not query usage")
  expect(state.execs[1].command:find("scripts/ai_usage.sh", 1, true) ~= nil, "usage script path is wrong")
  state.execs[1].callback(usage("75", "30", "15", "--"))
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
  state.execs[3].callback(usage("50", "50", "50", "50"))
  state.execs[2].callback(usage("99", "99", "99", "99"))
  expect(session.properties.label.string == "50%", "stale usage response overwrote the latest one")
  expect(bar.properties.background.image.string == "/tmp/codex-50.png", "stale bar overwrote the latest one")
end

test_app_icons()
test_spaces()
test_media()
test_wifi()
test_battery()
test_cpu()
test_volume()
test_calendar()
test_ai_usage()
print("SketchyBar runtime fixtures passed.")
