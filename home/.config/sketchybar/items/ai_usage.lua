local colors = require("colors")
local settings = require("settings")
local layout = require("helpers.layout")

local script = "zsh " .. settings.config_dir .. "/scripts/ai_usage.sh"
local assets = settings.config_dir .. "/assets"

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

local function add_scope(name, position, y_offset, width, letter)
  return sbar.add("item", name, {
    position = position,
    width = width,
    padding_left = 0,
    padding_right = 0,
    y_offset = y_offset,
    icon = { drawing = false },
    label = {
      drawing = false,
      string = letter,
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

-- The parts of one usage view as left-to-right groups. A zero-width "session"
-- part overlays the "weekly" partner that follows it, so a pair keeps its
-- order; right-side bar items are laid out right to left, so the bar view
-- adds the groups in reverse.
local usage_groups = {
  { { key = "logo", add = add_logo } },
  {
    { key = "session_scope", add = function(name, position) return add_scope(name, position, 5, 0, "S") end },
    { key = "weekly_scope", add = function(name, position) return add_scope(name, position, -5, scope_width, "W") end },
  },
  { { key = "bar", add = function(name, position) return sbar.add("item", name, bar_opts(position)) end } },
  {
    { key = "session_percent", add = function(name, position) return add_percent(name, position, 5, 0) end },
    { key = "weekly_percent", add = function(name, position) return add_percent(name, position, -5, percent_width) end },
  },
}

local function add_usage_view(prefix, position, logo_path, main)
  local view = { parts = {}, items = {} }
  local count = #usage_groups
  for step = 1, count do
    for _, part in ipairs(usage_groups[main and count + 1 - step or step]) do
      view[part.key] = part.add(prefix .. "." .. part.key, position, logo_path)
    end
  end
  for _, group in ipairs(usage_groups) do
    for _, part in ipairs(group) do
      table.insert(view.parts, view[part.key])
      table.insert(view.items, view[part.key].name)
    end
  end
  return view
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
    label = { drawing = has_session },
  })
  view.weekly_scope:set({
    width = has_weekly and scope_width or 0,
    y_offset = has_session and -5 or 0,
    label = { drawing = has_weekly },
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

layout.group_padding("ai_usage.right_padding")

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

layout.group_padding("ai_usage.left_padding")

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

local usage_revision = 0
local usage_received = false
local startup_retries = 0
local update_usage

-- At login OpenUsage starts alongside the bar and answers a few seconds
-- later, so the first fetch sees a refused connection and the bar would show
-- "--" until the next routine. Retry while no fetch has ever reached both
-- providers, bounded so a provider that stays down costs nothing after that.
local function schedule_startup_retry(usage)
  if usage_received or startup_retries >= 12 then return end
  if usage.codex.status ~= "unavailable" and usage.claude.status ~= "unavailable" then
    usage_received = true
    return
  end
  startup_retries = startup_retries + 1
  sbar.delay(5, update_usage)
end

update_usage = function()
  usage_revision = usage_revision + 1
  local revision = usage_revision
  sbar.exec(script, function(output)
    if revision ~= usage_revision then return end
    local usage = parse_usage(output)
    set_usage(codex, usage.codex)
    set_usage(popup_codex, usage.codex)
    set_usage(popup_claude, usage.claude)
    schedule_startup_retry(usage)
  end)
end

local function hide_popup()
  bracket:set({ popup = { drawing = false } })
end

local function toggle_popup()
  local opening = bracket:query().popup.drawing == "off"
  if opening then update_usage() end
  bracket:set({ popup = { drawing = opening } })
end

for _, item in ipairs(codex.parts) do
  item:subscribe("mouse.clicked", toggle_popup)
end
codex.logo:subscribe("mouse.exited.global", hide_popup)

codex.logo:set({ update_freq = 300 })
codex.logo:subscribe({ "forced", "routine", "system_woke" }, update_usage)
