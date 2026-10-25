local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local layout = require("helpers.layout")

local battery = sbar.add("item", "widgets.battery", {
  position = "right",
  icon = {
    font = {
      style = "Regular",
      size = 19.0,
    }
  },
  label = { font = { family = settings.font.numbers } },
  update_freq = 180,
  popup = { align = "center" }
})

local remaining_time = sbar.add("item", {
  position = "popup." .. battery.name,
  icon = {
    string = "Time remaining:",
    width = 100,
    align = "left"
  },
  label = {
    string = "??:??h",
    width = 100,
    align = "right"
  },
})

local battery_bracket = sbar.add("bracket", "widgets.battery.bracket", { battery.name }, {
  background = { color = colors.bg1 }
})

local battery_padding = layout.group_padding("widgets.battery.padding")

local function set_battery_visible(visible)
  battery:set({ drawing = visible })
  battery_bracket:set({ drawing = visible })
  battery_padding:set({ drawing = visible })
end

-- pmset prints "NN%; <state>; ..." where the state is charging, discharging,
-- charged, finishing charge or AC attached. "AC Power" in the header only
-- says the adapter is connected, which also holds while a charge limit or
-- Optimized Battery Charging keeps the battery from charging.
local function parse_battery(batt_info)
  local charge = batt_info:match("(%d+)%%")
  if not charge then return nil end
  local status = batt_info:match("%d+%%; ([^;]+);")
  return {
    charge = tonumber(charge),
    charging = status == "charging" or status == "finishing charge",
    remaining = batt_info:match(" (%d+:%d+) remaining"),
  }
end

local function set_remaining_time(info)
  remaining_time:set({
    icon = { string = info.charging and "Time to full:" or "Time remaining:" },
    label = { string = info.remaining and info.remaining .. "h" or "No estimate" },
  })
end

battery:subscribe({"forced", "routine", "power_source_change", "system_woke"}, function()
  sbar.exec("pmset -g batt", function(batt_info)
    local info = parse_battery(batt_info)
    if not info then
      -- Desktop Macs report no battery; keep the widget out of the bar.
      set_battery_visible(false)
      return
    end

    local charge = info.charge
    local icon
    local color = colors.green

    if info.charging then
      icon = icons.battery.charging
    elseif charge > 80 then
      icon = icons.battery._100
    elseif charge > 60 then
      icon = icons.battery._75
    elseif charge > 40 then
      icon = icons.battery._50
    elseif charge > 20 then
      icon = icons.battery._25
      color = colors.orange
    else
      icon = icons.battery._0
      color = colors.red
    end

    set_battery_visible(true)
    battery:set({
      icon = {
        string = icon,
        color = color
      },
      label = { string = string.format("%02d%%", charge) },
    })
    set_remaining_time(info)
  end)
end)

battery:subscribe("mouse.clicked", function(env)
  local opening = battery:query().popup.drawing == "off"
  battery:set({ popup = { drawing = opening } })
  if not opening then return end

  sbar.exec("pmset -g batt", function(batt_info)
    local info = parse_battery(batt_info)
    if info then set_remaining_time(info) end
  end)
end)

battery:subscribe("mouse.exited.global", function()
  battery:set({ popup = { drawing = false } })
end)
