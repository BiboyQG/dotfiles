local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local shell = require("helpers.shell")
local layout = require("helpers.layout")

local popup_width = 250

local volume_percent = sbar.add("item", "widgets.volume1", {
  position = "right",
  icon = { drawing = false },
  label = {
    string = "??%",
    padding_left = -1,
    font = { family = settings.font.numbers }
  },
})

local volume_icon = sbar.add("item", "widgets.volume2", {
  position = "right",
  padding_right = -1,
  icon = {
    string = icons.volume._100,
    width = 0,
    align = "left",
    color = colors.grey,
    font = {
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
  label = {
    width = 25,
    align = "left",
    font = {
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
})

local volume_bracket = sbar.add("bracket", "widgets.volume.bracket", {
  volume_icon.name,
  volume_percent.name
}, {
  background = { color = colors.bg1 },
  popup = { align = "center" }
})

layout.group_padding("widgets.volume.padding")

local volume_slider = sbar.add("slider", popup_width, {
  position = "popup." .. volume_bracket.name,
  slider = {
    highlight_color = colors.blue,
    background = {
      height = 6,
      corner_radius = 3,
      color = colors.bg2,
    },
    knob= {
      string = "􀀁",
      drawing = true,
    },
  },
  background = { color = colors.bg1, height = 2, y_offset = -20 },
  click_script = 'osascript -e "set volume output volume $PERCENTAGE"'
})

local current_volume

volume_percent:subscribe("volume_change", function(env)
  local volume = tonumber(env.INFO)
  current_volume = volume
  local icon = icons.volume._0
  if volume > 60 then
    icon = icons.volume._100
  elseif volume > 30 then
    icon = icons.volume._66
  elseif volume > 10 then
    icon = icons.volume._33
  elseif volume > 0 then
    icon = icons.volume._10
  end

  local lead = ""
  if volume < 10 then
    lead = "0"
  end

  volume_icon:set({ label = icon })
  volume_percent:set({ label = lead .. volume .. "%" })
  volume_slider:set({ slider = { percentage = volume } })
end)

local device_revision = 0
local device_count = 0
local popup_open = false

local function remove_device_items()
  if device_count == 0 then return end
  sbar.remove('/volume.device\\.*/')
  device_count = 0
end

local function volume_collapse_details()
  device_revision = device_revision + 1
  popup_open = false
  volume_bracket:set({ popup = { drawing = false } })
  remove_device_items()
end

-- mouse.exited.global fires on every bar exit; skip the two IPC calls (and
-- the "Regex: No match found" log line the remove produces) when nothing is
-- open.
local function volume_hide_details()
  if popup_open or device_count > 0 then volume_collapse_details() end
end

local function volume_toggle_details(env)
  if env.BUTTON == "right" then
    sbar.exec("open /System/Library/PreferencePanes/Sound.prefpane")
    return
  end

  local should_draw = volume_bracket:query().popup.drawing == "off"
  if not should_draw then
    volume_collapse_details()
    return
  end

  device_revision = device_revision + 1
  local revision = device_revision
  local function is_current()
    return revision == device_revision and volume_bracket:query().popup.drawing == "on"
  end

  remove_device_items()
  popup_open = true
  volume_bracket:set({ popup = { drawing = true } })
  sbar.exec("SwitchAudioSource -t output -c", function(result, exit_code)
    if not is_current() or exit_code ~= 0 or type(result) ~= "string" then return end
    local current = result:gsub("[\r\n]+$", "")
    sbar.exec("SwitchAudioSource -a -t output", function(available, list_exit_code)
      if not is_current() or list_exit_code ~= 0 or type(available) ~= "string" then return end
      remove_device_items()

      for device in string.gmatch(available, '[^\r\n]+') do
        local color = colors.grey
        if current == device then
          color = colors.white
        end
        sbar.add("item", "volume.device." .. device_count, {
          position = "popup." .. volume_bracket.name,
          width = popup_width,
          align = "center",
          label = { string = device, color = color },
          click_script = "SwitchAudioSource -s " .. shell.quote(device) .. " && sketchybar --set /volume.device\\.*/ label.color=" .. colors.grey .. " --set $NAME label.color=" .. colors.white

        })
        device_count = device_count + 1
      end
    end)
  end)
end

-- A swipe fires many scroll events and each osascript takes about 0.15 s, so
-- concurrent read-modify-writes lost steps. volume_change (sent with the
-- forced update at startup) tracks the current level; scrolling accumulates
-- an absolute target and one osascript at a time applies the latest one.
local target_volume
local in_flight_volume

local function apply_target_volume()
  if in_flight_volume or target_volume == nil then return end
  in_flight_volume = target_volume
  target_volume = nil
  sbar.exec(string.format('osascript -e "set volume output volume %g"', in_flight_volume), function()
    current_volume = in_flight_volume
    in_flight_volume = nil
    apply_target_volume()
  end)
end

local function volume_scroll(env)
  local delta = tonumber(env.INFO.delta)
  if not delta or not current_volume then return end
  if not (env.INFO.modifier == "ctrl") then delta = delta * 10.0 end

  local base = target_volume or in_flight_volume or current_volume
  target_volume = math.max(0, math.min(100, base + delta))
  apply_target_volume()
end

volume_icon:subscribe("mouse.clicked", volume_toggle_details)
volume_icon:subscribe("mouse.scrolled", volume_scroll)
volume_percent:subscribe("mouse.clicked", volume_toggle_details)
volume_percent:subscribe("mouse.exited.global", volume_hide_details)
volume_percent:subscribe("mouse.scrolled", volume_scroll)
