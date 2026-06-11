local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local spaces = {}
local space_brackets = {}
local workspace_names = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }
local workspace_displays = {
  ["1"] = 1,
  ["2"] = 1,
  ["3"] = 1,
  ["4"] = 1,
  ["5"] = 1,
  ["6"] = 1,
  ["7"] = 2,
  ["8"] = 2,
  ["9"] = 2,
  ["10"] = 2,
}
local update_id = 0

sbar.add("event", "aerospace_workspace_change")

local function app_icon(app)
  return app_icons[app] or app_icons["Default"]
end

local function update_spaces()
  update_id = update_id + 1
  local current_update_id = update_id

  sbar.exec("/opt/homebrew/bin/aerospace list-workspaces --all --format '%{workspace}%{tab}%{workspace-is-focused}'", function(workspaces)
    if current_update_id ~= update_id then return end

    local focused = {}
    for line in string.gmatch(workspaces, "[^\r\n]+") do
      local workspace, is_focused = line:match("^([^\t]+)\t(.+)$")
      if workspace then
        focused[workspace] = is_focused == "true"
      end
    end

    sbar.exec("/opt/homebrew/bin/aerospace list-windows --all --format '%{workspace}%{tab}%{app-name}'", function(windows)
      if current_update_id ~= update_id then return end

      local icons_by_workspace = {}
      local seen_apps_by_workspace = {}

      for _, workspace in ipairs(workspace_names) do
        icons_by_workspace[workspace] = {}
        seen_apps_by_workspace[workspace] = {}
      end

      for line in string.gmatch(windows, "[^\r\n]+") do
        local workspace, app = line:match("^([^\t]+)\t(.+)$")
        if workspace and spaces[workspace] and app and not seen_apps_by_workspace[workspace][app] then
          seen_apps_by_workspace[workspace][app] = true
          table.insert(icons_by_workspace[workspace], app_icon(app))
        end
      end

      for _, workspace in ipairs(workspace_names) do
        local selected = focused[workspace] == true
        local icon_line = #icons_by_workspace[workspace] > 0 and table.concat(icons_by_workspace[workspace]) or " —"

        spaces[workspace]:set({
          icon = { highlight = selected },
          label = {
            string = icon_line,
            highlight = selected,
          },
          background = { border_color = selected and colors.black or colors.bg2 },
        })
        space_brackets[workspace]:set({
          background = { border_color = selected and colors.grey or colors.bg2 }
        })
      end
    end)
  end)
end

for _, workspace in ipairs(workspace_names) do
  local space = sbar.add("item", "space." .. workspace, {
    position = "left",
    display = workspace_displays[workspace],
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
    display = workspace_displays[workspace],
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 2
    }
  })

  space_brackets[workspace] = space_bracket

  sbar.add("item", "space.padding." .. workspace, {
    position = "left",
    display = workspace_displays[workspace],
    width = settings.group_paddings,
  })

  space:subscribe("mouse.clicked", function(env)
    local op = (env.BUTTON == "right") and "move-node-to-workspace --focus-follows-window" or "workspace"
    sbar.exec("/opt/homebrew/bin/aerospace " .. op .. " " .. workspace, function()
      sbar.trigger("aerospace_workspace_change")
    end)
  end)
end

local space_window_observer = sbar.add("item", {
  drawing = false,
  updates = true,
  update_freq = 2,
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
  "forced",
  "routine",
  "front_app_switched",
  "aerospace_workspace_change",
  "space_windows_change",
  "system_woke",
}, update_spaces)

update_spaces()

spaces_indicator:subscribe("swap_menus_and_spaces", function(env)
  local currently_on = spaces_indicator:query().icon.value == icons.switch.on
  spaces_indicator:set({
    icon = currently_on and icons.switch.off or icons.switch.on
  })
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
