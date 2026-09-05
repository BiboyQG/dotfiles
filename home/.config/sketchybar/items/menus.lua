local colors = require("colors")
local settings = require("settings")

local menu_watcher = sbar.add("item", {
  drawing = false,
  updates = false,
})
local space_menu_swap = sbar.add("item", {
  drawing = false,
  updates = true,
})
sbar.add("event", "swap_menus_and_spaces")

local max_items = 15
local menu_items = {}
for i = 1, max_items, 1 do
  local menu = sbar.add("item", "menu." .. i, {
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    drawing = false,
    icon = { drawing = false },
    label = {
      font = {
        style = settings.font.style_map[i == 1 and "Heavy" or "Semibold"]
      },
      padding_left = 6,
      padding_right = 6,
    },
    click_script = "$HOME/.local/libexec/sketchybar/menus -s " .. i,
  })

  menu_items[i] = menu
end

sbar.add("bracket", { '/menu\\..*/' }, {
  background = { color = colors.bg1 }
})

local menu_padding = sbar.add("item", "menu.padding", {
  drawing = false,
  width = 5
})

local menus_visible = false
local menu_revision = 0

local function update_menus()
  if not menus_visible then return end
  menu_revision = menu_revision + 1
  local revision = menu_revision
  sbar.exec("$HOME/.local/libexec/sketchybar/menus -l", function(menus)
    if not menus_visible or revision ~= menu_revision then return end
    sbar.set('/menu\\..*/', { drawing = false })
    menu_padding:set({ drawing = true })
    local id = 1
    for menu in string.gmatch(menus, '[^\r\n]+') do
      if id <= max_items then
        menu_items[id]:set( { label = menu, drawing = true } )
      else break end
      id = id + 1
    end
  end)
end

menu_watcher:subscribe("front_app_switched", update_menus)

space_menu_swap:subscribe("swap_menus_and_spaces", function()
  menus_visible = not menus_visible
  menu_revision = menu_revision + 1
  menu_watcher:set({ updates = menus_visible })
  sbar.set("front_app", { drawing = not menus_visible })
  if menus_visible then
    update_menus()
  else
    sbar.set("/menu\\..*/", { drawing = false })
  end
end)

return menu_watcher
