local settings = require("settings")
local colors = require("colors")
local layout = require("helpers.layout")

layout.group_padding()

local cal = sbar.add("item", {
  icon = {
    color = colors.white,
    padding_left = 8,
    font = {
      style = settings.font.style_map["Black"],
      size = 12.0,
    },
  },
  label = {
    color = colors.white,
    padding_right = 8,
    width = 49,
    align = "right",
    font = { family = settings.font.numbers },
  },
  position = "right",
  padding_left = 1,
  padding_right = 1,
  background = {
    color = colors.bg2,
    border_color = colors.black,
    border_width = 1
  },
  click_script = "open -a 'Calendar'"
})

layout.double_border(cal.name)
layout.group_padding()

-- Tick on the minute boundary instead of polling every 30 s, so the time
-- never lags behind the clock. A restart on forced/system_woke bumps the
-- revision so a timer that fires late after sleep ends its own chain.
local clock_revision = 0

local function tick(revision)
  if revision ~= clock_revision then return end
  cal:set({ icon = os.date("%a. %d %b."), label = os.date("%H:%M") })
  sbar.delay(60 - tonumber(os.date("%S")), function() tick(revision) end)
end

cal:subscribe({ "forced", "system_woke" }, function()
  clock_revision = clock_revision + 1
  tick(clock_revision)
end)
