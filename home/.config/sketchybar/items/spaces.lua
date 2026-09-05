local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local spaces = {}
local space_brackets = {}
local space_paddings = {}
local workspace_names = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }
local known_workspaces = {}
local workspace_available = {}
local focus_revision = 0
local focused_workspace
local spaces_mode_visible = true
local full_refresh_running = false
local full_refresh_pending = false
local pending_windows_only = true
local window_refresh_revision = 0
local focus_refresh_scheduled = false
local cached_workspaces
local rendered = {}

for index, workspace in ipairs(workspace_names) do
  known_workspaces[workspace] = true
  workspace_available[workspace] = index <= 6
end

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_windows_change")

local function app_icon(app)
  return app_icons[app] or app_icons["Default"]
end

local function update_workspace_drawing(workspace)
  local drawing = spaces_mode_visible
    and (workspace_available[workspace] or workspace == focused_workspace)
  if rendered[workspace] then
    if rendered[workspace].drawing == drawing then return end
    rendered[workspace].drawing = drawing
  end
  spaces[workspace]:set({ drawing = drawing })
  space_brackets[workspace]:set({ drawing = drawing })
  space_paddings[workspace]:set({ drawing = drawing })
end

local function set_selected(workspace, selected)
  if rendered[workspace] then rendered[workspace].selected = selected end
  spaces[workspace]:set({
    icon = { highlight = selected },
    label = { highlight = selected },
    background = { border_color = selected and colors.black or colors.bg2 },
  })
  space_brackets[workspace]:set({
    background = { border_color = selected and colors.grey or colors.bg2 },
  })
  update_workspace_drawing(workspace)
end

local function apply_drawing()
  for _, workspace in ipairs(workspace_names) do
    update_workspace_drawing(workspace)
  end
end

local function parse_workspaces(rows)
  if type(rows) ~= "table" then return nil end

  local displays = {}
  local display_ids = {}
  local found = 0
  local focused

  for _, row in ipairs(rows) do
    local workspace = type(row) == "table" and tostring(row.workspace or "") or ""
    local is_focused = type(row) == "table" and row["workspace-is-focused"] or false
    local display = type(row) == "table" and tonumber(row["monitor-appkit-nsscreen-screens-id"]) or nil
    if display and display >= 1 and display % 1 == 0 then
      display_ids[display] = true
    end
    if known_workspaces[workspace] and display and display_ids[display] then
      if not displays[workspace] then found = found + 1 end
      displays[workspace] = display
      if is_focused == true or is_focused == "true" then focused = workspace end
    end
  end

  if found ~= #workspace_names or not focused then return nil end
  local display_count = 0
  for _ in pairs(display_ids) do display_count = display_count + 1 end
  if display_count == 0 then return nil end
  return displays, focused, display_count
end

local function parse_windows(rows)
  if type(rows) ~= "table" then return nil end

  local icons_by_workspace = {}
  local seen_apps_by_workspace = {}

  for _, workspace in ipairs(workspace_names) do
    icons_by_workspace[workspace] = {}
    seen_apps_by_workspace[workspace] = {}
  end

  for _, row in ipairs(rows) do
    local workspace = type(row) == "table" and tostring(row.workspace or "") or ""
    local app = type(row) == "table" and row["app-name"] or nil
    if known_workspaces[workspace]
      and type(app) == "string"
      and app ~= ""
      and not seen_apps_by_workspace[workspace][app]
    then
      seen_apps_by_workspace[workspace][app] = true
      table.insert(icons_by_workspace[workspace], app_icon(app))
    end
  end

  return icons_by_workspace
end

local function update_spaces(windows_only)
  windows_only = windows_only == true and cached_workspaces ~= nil
  if full_refresh_running then
    full_refresh_pending = true
    pending_windows_only = pending_windows_only and windows_only
    return
  end

  full_refresh_running = true
  local current_focus_revision = focus_revision
  local results = {}
  local completed = 0

  local function finish()
    full_refresh_running = false
    if full_refresh_pending then
      full_refresh_pending = false
      local only_windows = pending_windows_only
      pending_windows_only = true
      update_spaces(only_windows)
    end
  end

  local function receive(name, result, exit_code)
    results[name] = {
      output = result,
      ok = exit_code == 0,
    }
    completed = completed + 1
    if completed ~= 2 then return end
    if not results.workspaces.ok or not results.windows.ok then
      finish()
      return
    end

    local workspace_displays, queried_focus, display_count = parse_workspaces(results.workspaces.output)
    local icons_by_workspace = parse_windows(results.windows.output)
    if not workspace_displays or not icons_by_workspace then
      finish()
      return
    end

    local selected_workspace = queried_focus
    if (windows_only or focus_revision ~= current_focus_revision) and known_workspaces[focused_workspace] then
      selected_workspace = focused_workspace
    end
    focused_workspace = selected_workspace
    if not windows_only then cached_workspaces = results.workspaces.output end

    for _, workspace in ipairs(workspace_names) do
      local display = workspace_displays[workspace]
      local has_windows = #icons_by_workspace[workspace] > 0
      local available = display_count > 1 or tonumber(workspace) <= 6 or has_windows
      local selected = workspace == selected_workspace
      local icon_line = has_windows and table.concat(icons_by_workspace[workspace]) or " —"
      workspace_available[workspace] = available
      local drawing = spaces_mode_visible and (available or selected)
      local previous = rendered[workspace]
      if not previous or previous.display ~= display or previous.drawing ~= drawing
        or previous.selected ~= selected or previous.icon_line ~= icon_line then
        rendered[workspace] = {
          display = display, drawing = drawing, selected = selected, icon_line = icon_line,
        }
        spaces[workspace]:set({
          display = display,
          drawing = drawing,
          icon = { highlight = selected },
          label = {
            string = icon_line,
            highlight = selected,
          },
          background = { border_color = selected and colors.black or colors.bg2 },
        })
        space_brackets[workspace]:set({
          display = display,
          drawing = drawing,
          background = { border_color = selected and colors.grey or colors.bg2 },
        })
        space_paddings[workspace]:set({
          display = display,
          drawing = drawing,
        })
      end
    end
    finish()
  end

  if windows_only then
    results.workspaces = { output = cached_workspaces, ok = true }
    completed = 1
  else
    sbar.exec(
      "/opt/homebrew/bin/aerospace list-workspaces --all --format '%{workspace} %{workspace-is-focused} %{monitor-appkit-nsscreen-screens-id}' --json",
      function(result, exit_code) receive("workspaces", result, exit_code) end
    )
  end
  sbar.exec(
    "/opt/homebrew/bin/aerospace list-windows --all --format '%{workspace} %{app-name}' --json",
    function(result, exit_code) receive("windows", result, exit_code) end
  )
end

-- Focus events are only a fallback for window changes. Coalesce a burst and
-- reuse the display mapping until a topology event requests a full refresh.
local function schedule_focus_refresh()
  if focus_refresh_scheduled then return end
  focus_refresh_scheduled = true
  sbar.delay(0.2, function()
    focus_refresh_scheduled = false
    update_spaces(true)
  end)
end

local function schedule_window_refresh()
  window_refresh_revision = window_refresh_revision + 1
  local revision = window_refresh_revision
  sbar.delay(0.2, function()
    if revision == window_refresh_revision then update_spaces() end
  end)
end

local function update_space_windows()
  update_spaces()
  schedule_window_refresh()
end

local function update_workspace_focus(env)
  local next_workspace = env.FOCUSED
  if not known_workspaces[next_workspace] then return end

  local previous_workspace = env.PREV
  if not known_workspaces[previous_workspace] then previous_workspace = focused_workspace end

  focus_revision = focus_revision + 1
  focused_workspace = next_workspace
  if previous_workspace and previous_workspace ~= next_workspace then
    set_selected(previous_workspace, false)
  end
  set_selected(next_workspace, true)
end

for index, workspace in ipairs(workspace_names) do
  local space = sbar.add("item", "space." .. workspace, {
    position = "left",
    display = 1,
    drawing = index <= 6,
    icon = {
      font = { family = settings.font.numbers },
      string = workspace,
      padding_left = 15,
      padding_right = 8,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      string = " —",
      padding_right = 20,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left = 1,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 26,
      border_color = colors.black,
    },
  })

  spaces[workspace] = space

  local space_bracket = sbar.add("bracket", { space.name }, {
    display = 1,
    drawing = index <= 6,
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 2
    }
  })

  space_brackets[workspace] = space_bracket

  space_paddings[workspace] = sbar.add("item", "space.padding." .. workspace, {
    position = "left",
    display = 1,
    drawing = index <= 6,
    width = settings.group_paddings,
  })

  space:subscribe("mouse.clicked", function(env)
    local op = (env.BUTTON == "right") and "move-node-to-workspace --focus-follows-window" or "workspace"
    sbar.exec("/opt/homebrew/bin/aerospace " .. op .. " " .. workspace)
  end)
end

local space_window_observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

local spaces_indicator = sbar.add("item", {
  padding_left = -3,
  padding_right = 0,
  icon = {
    padding_left = 8,
    padding_right = 9,
    color = colors.grey,
    string = icons.switch.on,
  },
  label = {
    width = 0,
    padding_left = 0,
    padding_right = 8,
    string = "Spaces",
    color = colors.bg1,
  },
  background = {
    color = colors.with_alpha(colors.grey, 0.0),
    border_color = colors.with_alpha(colors.bg1, 0.0),
  }
})

space_window_observer:subscribe({
  "display_change",
  "forced",
  "system_woke",
}, update_spaces)
space_window_observer:subscribe("aerospace_windows_change", schedule_focus_refresh)
space_window_observer:subscribe("space_windows_change", update_space_windows)
space_window_observer:subscribe("aerospace_workspace_change", update_workspace_focus)

spaces_indicator:subscribe("swap_menus_and_spaces", function(env)
  local currently_on = spaces_indicator:query().icon.value == icons.switch.on
  spaces_mode_visible = not currently_on
  spaces_indicator:set({
    icon = currently_on and icons.switch.off or icons.switch.on
  })
  apply_drawing()
end)

spaces_indicator:subscribe("mouse.entered", function(env)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic" }
    })
  end)
end)

spaces_indicator:subscribe("mouse.exited", function(env)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0, }
    })
  end)
end)

spaces_indicator:subscribe("mouse.clicked", function(env)
  sbar.trigger("swap_menus_and_spaces")
end)
