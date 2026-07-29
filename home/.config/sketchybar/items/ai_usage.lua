local colors = require("colors")
local settings = require("settings")

local config_dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
local script = "zsh " .. config_dir .. "/scripts/ai_usage.sh"
local assets = config_dir .. "/assets"

local bar_width = 52
local scope_width = 14
local percent_width = 34

local function percent_label(value)
  if not value or value == "" or value == "--" then
    return "--"
  end
  return value .. "%"
end

local function parse_usage(output)
  local usage = {
    codex = {},
    claude = {},
  }

  for line in output:gmatch("[^\r\n]+") do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key then
      local provider, field = key:match("^(%w+)_(.+)$")
      if provider and usage[provider] then
        usage[provider][field] = value
      end
    end
  end

  return usage
end

local function add_logo(name, position, image)
  return sbar.add("item", name, {
    position = position,
    width = 22,
    padding_left = 6,
    padding_right = 4,
    icon = { drawing = false },
    label = { drawing = false },
    background = {
      color = colors.transparent,
      border_color = colors.transparent,
      border_width = 0,
      image = {
        string = image,
        scale = 0.31,
      },
    },
  })
end

local function bar_opts(position)
  return {
    position = position,
    width = bar_width,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
    background = {
      color = colors.transparent,
      border_color = colors.transparent,
      border_width = 0,
      image = {
        scale = 1,
      },
    },
  }
end

local function add_percent(name, position, y_offset, width)
  return sbar.add("item", name, {
    position = position,
    width = width,
    padding_left = 0,
    padding_right = 0,
    y_offset = y_offset,
    icon = { drawing = false },
    label = {
      string = "--",
      width = percent_width,
      align = "right",
      color = colors.white,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
    },
  })
end

local function add_scope(name, position, y_offset, width)
  return sbar.add("item", name, {
    position = position,
    width = width,
    padding_left = 0,
    padding_right = 0,
    y_offset = y_offset,
    icon = { drawing = false },
    label = {
      string = "",
      width = scope_width,
      align = "center",
      color = colors.grey,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 8.0,
      },
    },
  })
end

local function add_usage_view(prefix, position, logo_path, main)
  local logo
  local bar
  local session_scope
  local weekly_scope
  local session_percent
  local weekly_percent

  if main then
    session_percent = add_percent(prefix .. ".session_percent", position, 5, 0)
    weekly_percent = add_percent(prefix .. ".weekly_percent", position, -5, percent_width)
    bar = sbar.add("item", prefix .. ".bar", bar_opts(position))
    session_scope = add_scope(prefix .. ".session_scope", position, 5, 0)
    weekly_scope = add_scope(prefix .. ".weekly_scope", position, -5, scope_width)
    logo = add_logo(prefix .. ".logo", position, logo_path)
  else
    logo = add_logo(prefix .. ".logo", position, logo_path)
    session_scope = add_scope(prefix .. ".session_scope", position, 5, 0)
    weekly_scope = add_scope(prefix .. ".weekly_scope", position, -5, scope_width)
    bar = sbar.add("item", prefix .. ".bar", bar_opts(position))
    session_percent = add_percent(prefix .. ".session_percent", position, 5, 0)
    weekly_percent = add_percent(prefix .. ".weekly_percent", position, -5, percent_width)
  end

  return {
    logo = logo,
    bar = bar,
    session_scope = session_scope,
    weekly_scope = weekly_scope,
    session_percent = session_percent,
    weekly_percent = weekly_percent,
    items = {
      logo.name,
      session_scope.name,
      weekly_scope.name,
      bar.name,
      session_percent.name,
      weekly_percent.name,
    },
  }
end

local function has_value(value)
  return value and value ~= "" and value ~= "--"
end

local function quota_color(value)
  local percent = tonumber(value)
  if not percent then
    return colors.grey
  elseif percent <= 20 then
    return colors.red
  elseif percent <= 40 then
    return colors.yellow
  end
  return colors.white
end

local function set_usage(view, usage)
  local session = usage and usage.session or "--"
  local weekly = usage and usage.weekly or "--"
  local has_session = has_value(session)
  local has_weekly = has_value(weekly)
  local show_unavailable = not has_session and not has_weekly

  view.bar:set({ background = { image = { string = usage and usage.bar or "" } } })
  view.session_scope:set({
    width = has_session and not has_weekly and scope_width or 0,
    y_offset = has_weekly and 5 or 0,
    label = {
      drawing = has_session,
      string = "S",
    },
  })
  view.weekly_scope:set({
    width = has_weekly and scope_width or 0,
    y_offset = has_session and -5 or 0,
    label = {
      drawing = has_weekly,
      string = "W",
    },
  })
  view.session_percent:set({
    width = has_session and not has_weekly and percent_width or 0,
    y_offset = has_weekly and 5 or 0,
    label = {
      drawing = has_session,
      string = percent_label(session),
      color = quota_color(session),
    },
  })
  view.weekly_percent:set({
    width = (has_weekly or show_unavailable) and percent_width or 0,
    y_offset = has_session and -5 or 0,
    label = {
      drawing = has_weekly or show_unavailable,
      string = has_weekly and percent_label(weekly) or "--",
      color = quota_color(weekly),
    },
  })
end

sbar.add("item", "ai_usage.right_padding", {
  position = "right",
  width = settings.group_paddings,
})

local codex = add_usage_view("ai_usage.codex", "right", assets .. "/openai.png", true)

local bracket = sbar.add("bracket", "ai_usage.bracket", codex.items, {
  background = {
    color = colors.bg1,
    border_color = colors.bg2,
  },
  popup = {
    align = "right",
    horizontal = true,
    height = 46,
  },
})

sbar.add("item", "ai_usage.left_padding", {
  position = "right",
  width = settings.group_paddings,
})

local popup_codex = add_usage_view("ai_usage.popup.codex", "popup." .. bracket.name, assets .. "/openai.png")
sbar.add("item", "ai_usage.popup.spacer", {
  position = "popup." .. bracket.name,
  width = 13,
  icon = { drawing = false },
  label = {
    string = "│",
    align = "center",
    color = colors.bg2,
    font = { size = 16.0 },
  },
})
local popup_claude = add_usage_view("ai_usage.popup.claude", "popup." .. bracket.name, assets .. "/claude.png")

local function update_usage()
  sbar.exec(script, function(output)
    local usage = parse_usage(output)
    set_usage(codex, usage.codex)
    set_usage(popup_codex, usage.codex)
    set_usage(popup_claude, usage.claude)
  end)
end

local function hide_popup()
  bracket:set({ popup = { drawing = false } })
end

local function toggle_popup()
  update_usage()
  bracket:set({ popup = { drawing = "toggle" } })
end

for _, item in ipairs({
  codex.logo,
  codex.session_scope,
  codex.weekly_scope,
  codex.bar,
  codex.session_percent,
  codex.weekly_percent,
}) do
  item:subscribe("mouse.clicked", toggle_popup)
  item:subscribe("mouse.exited.global", hide_popup)
end

codex.logo:set({ update_freq = 300 })
codex.logo:subscribe({ "forced", "routine", "system_woke" }, update_usage)
