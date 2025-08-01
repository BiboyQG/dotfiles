-- helper hotkey to figure out the app path and name of current focused window
hs.hotkey.bind({ "ctrl", "cmd" }, ".", function()
	hs.alert.show(
		"App path: "
			.. hs.window.focusedWindow():application():path()
			.. "\n"
			.. "App name: "
			.. hs.window.focusedWindow():application():name()
			.. "\n"
			.. "Bundle ID: "
			.. hs.window.focusedWindow():application():bundleID()
			.. "\n"
			.. "IM source id: "
			.. hs.keycodes.currentSourceID()
	)
end)
