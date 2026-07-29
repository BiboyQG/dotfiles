local shell = require("helpers.shell")
local helper_dir = os.getenv("SKETCHYBAR_HELPER_DIR")
  or (os.getenv("HOME") .. "/.local/libexec/sketchybar")

if os.execute("test -x " .. shell.quote(helper_dir .. "/menus")) then
  require("items.apple")
  require("items.menus")
end
require("items.spaces")
require("items.front_app")
require("items.calendar")
require("items.widgets")
require("items.ai_usage")
require("items.media")
