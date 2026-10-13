return {
  paddings = 3,
  group_paddings = 5,

  -- SketchyBar exports the directory of the running config as CONFIG_DIR.
  config_dir = os.getenv("CONFIG_DIR") or os.getenv("HOME") .. "/.config/sketchybar",

  -- This is a font configuration for SF Pro and SF Mono (installed manually)
  font = require("helpers.default_font"),
}
