log = hs.logger.new("ime", "debug")

-- you can find the source id by running `hs.keycodes.currentSourceID()`

local function zh()
	hs.keycodes.currentSourceID("com.sogou.inputmethod.sogou.pinyin")
end

local function en()
	hs.keycodes.currentSourceID("com.apple.keylayout.ABC")
end

-- app to expected ime config
local appName2Ime = {
	{ "Finder", "en" },
	{ "Arc", "zh" },
	{ "Cursor", "en" },
	{ "kitty", "en" },
	{ "Spotify", "zh" },
	{ "Raycast", "en" },
	{ "System Preferences", "en" },
	{ "Hoppscotch", "en" },
	{ "Wechat", "zh" },
	{ "Outlook", "en" },
	{ "Claude", "zh" },
	{ "Discord", "zh" },
	{ "Slack", "en" },
}

function updateFocusAppInputMethod()
	local focusAppName = hs.window.frontmostWindow():application():name()
	if focusAppName == nil then
		return
	end
	-- hs.alert.show(focusAppPath)
	for index, app in pairs(appName2Ime) do
		local appName = app[1]
		local expectedIme = app[2]

		if focusAppName == appName then
			if expectedIme == "en" then
				en()
			else
				zh()
			end
			break
		end
	end
end

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

-- Handle cursor focus and application's screen manage.
function applicationWatcher(appName, eventType, appObject)
	if eventType == hs.application.watcher.activated or eventType == hs.application.watcher.launched then
		updateFocusAppInputMethod()
	end
end

appWatcher = hs.application.watcher.new(applicationWatcher)
appWatcher:start()
