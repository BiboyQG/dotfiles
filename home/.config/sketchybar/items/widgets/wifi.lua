local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local shell = require("helpers.shell")
local layout = require("helpers.layout")

-- The Wi-Fi device is not always en0 (desktop Macs expose Ethernet there), so
-- resolve it before starting the event provider binary, which fires the
-- "network_update" event for that interface every 2.0 seconds.
local wifi_interface = "en0"

sbar.exec(
  "networksetup -listallhardwareports | awk '/^Hardware Port: Wi-Fi$/ { getline; print $2; exit }'",
  function(result)
    local interface = result:match("^%s*(en%d+)%s*$")
    if interface then wifi_interface = interface end
    sbar.exec(
      "killall network_load >/dev/null 2>&1; $HOME/.local/libexec/sketchybar/network_load "
        .. wifi_interface
        .. " network_update 2.0"
    )
  end
)

local popup_width = 250

local function rate_item(name, icon, color, y_offset, width)
  return sbar.add("item", name, {
    position = "right",
    padding_left = -5,
    width = width,
    icon = {
      padding_right = 0,
      font = {
        style = "Bold",
        size = 9.0,
      },
      string = icon,
    },
    label = {
      font = {
        family = settings.font.numbers,
        style = "Bold",
        size = 9.0,
      },
      color = color,
      string = "??? Bps",
    },
    y_offset = y_offset,
  })
end

local wifi_up = rate_item("widgets.wifi1", icons.wifi.upload, colors.red, 4, 0)
local wifi_down = rate_item("widgets.wifi2", icons.wifi.download, colors.blue, -4)

local wifi = sbar.add("item", "widgets.wifi.padding", {
  position = "right",
  label = { drawing = false },
})

local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name
}, {
  background = { color = colors.bg1 },
  popup = { align = "center", height = 30 }
})

local ssid = sbar.add("item", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    font = {
      style = "Bold"
    },
    string = icons.wifi.router,
  },
  width = popup_width,
  align = "center",
  label = {
    font = {
      size = 15,
      style = "Bold"
    },
    max_chars = 18,
    string = "????????????",
  },
  background = {
    height = 2,
    color = colors.grey,
    y_offset = -15
  }
})

local function info_row(title, placeholder, max_chars)
  return sbar.add("item", {
    position = "popup." .. wifi_bracket.name,
    icon = {
      align = "left",
      string = title,
      width = popup_width / 2,
    },
    label = {
      max_chars = max_chars,
      string = placeholder,
      width = popup_width / 2,
      align = "right",
    },
  })
end

local hostname = info_row("Hostname:", "????????????", 20)
local ip = info_row("IP:", "???.???.???.???")
local mask = info_row("Subnet mask:", "???.???.???.???")
local router = info_row("Router:", "???.???.???.???")

layout.group_padding()

wifi_up:subscribe("network_update", function(env)
  local up_color = (env.upload == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up:set({
    icon = { color = up_color },
    label = {
      string = env.upload,
      color = up_color
    }
  })
  wifi_down:set({
    icon = { color = down_color },
    label = {
      string = env.download,
      color = down_color
    }
  })
  local connected = env.connected == "on"
  wifi:set({
    icon = {
      string = connected and icons.wifi.connected or icons.wifi.disconnected,
      color = connected and colors.white or colors.red,
    },
  })
end)

local function trim(value)
  return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

-- Real text of each popup row, kept in Lua so a click copies the value even
-- while the row shows the clipboard glyph; nil marks a row with nothing to
-- copy. The revision drops a stale restore from an earlier click.
local rows = {}

local function set_row(row, value, fallback)
  value = trim(value)
  if value == "" then value = nil end
  local entry = rows[row.name] or { revision = 0 }
  entry.value = value
  entry.revision = entry.revision + 1
  rows[row.name] = entry
  row:set({ label = { string = value or fallback or "", align = "right" } })
end

local function copy_row(row)
  local entry = rows[row.name]
  if not entry or not entry.value then return end
  entry.revision = entry.revision + 1
  local revision = entry.revision
  local value = entry.value
  sbar.exec("printf %s " .. shell.quote(value) .. " | pbcopy")
  row:set({ label = { string = icons.clipboard, align = "center" } })
  sbar.delay(1, function()
    if revision ~= entry.revision then return end
    row:set({ label = { string = value, align = "right" } })
  end)
end

local function hide_details()
  wifi_bracket:set({ popup = { drawing = false } })
end

local function toggle_details()
  local should_draw = wifi_bracket:query().popup.drawing == "off"
  if not should_draw then
    hide_details()
    return
  end

  wifi_bracket:set({ popup = { drawing = true }})
  sbar.exec("networksetup -getcomputername", function(result)
    set_row(hostname, result)
  end)
  sbar.exec("ipconfig getifaddr " .. wifi_interface, function(result)
    set_row(ip, result)
  end)
  sbar.exec("ipconfig getsummary " .. wifi_interface .. " | awk -F ' SSID : ' '/ SSID : / {print $2}'", function(result)
    -- Recent macOS releases redact the SSID unless `ipconfig setverbose 1` is set.
    local value = trim(result)
    set_row(ssid, value ~= "<redacted>" and value or nil, "Unavailable")
  end)
  -- The subnet mask and router come from the same networksetup output; the
  -- leading newline keeps "IPv6 Router:" from matching.
  sbar.exec("networksetup -getinfo Wi-Fi", function(result)
    local info = "\n" .. trim(result)
    set_row(mask, info:match("\nSubnet mask: ([^\n]*)"))
    set_row(router, info:match("\nRouter: ([^\n]*)"))
  end)
end

wifi_up:subscribe("mouse.clicked", toggle_details)
wifi_down:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.exited.global", hide_details)

for _, row in ipairs({ ssid, hostname, ip, mask, router }) do
  row:subscribe("mouse.clicked", function() copy_row(row) end)
end
