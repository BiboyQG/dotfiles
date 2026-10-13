local colors = require("colors")
local settings = require("settings")

local M = {}

-- Spacer between the right-side item groups; brackets need one on each side.
function M.group_padding(name)
  local properties = { position = "right", width = settings.group_paddings }
  if name then return sbar.add("item", name, properties) end
  return sbar.add("item", properties)
end

-- Second border around a single item, drawn by a transparent bracket.
function M.double_border(item_name)
  return sbar.add("bracket", { item_name }, {
    background = {
      color = colors.transparent,
      height = 30,
      border_color = colors.grey,
    },
  })
end

return M
