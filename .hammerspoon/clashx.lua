---------------------------------------------------------------
--  ClashX Meta 快捷键控制
--  Banghao 的 Hammerspoon 配置片段
---------------------------------------------------------------

local mod = {}

-- AppleScript 调用封装
local function applescriptF(script)
    return hs.osascript.applescript(script)
end

---------------------------------------------------------------
-- 功能函数
---------------------------------------------------------------

-- 切换系统代理
function mod.toggleProxy()
    -- 确保 ClashX Meta 已运行；如果未运行则自动启动
    if not hs.application.get("ClashX Meta") then
        hs.application.launchOrFocus("/Applications/ClashX Meta.app")
        hs.timer.doAfter(1, function()  -- 给 App 一点启动时间
            applescriptF([[tell application "ClashX Meta" to toggleProxy]])
        end)
    else
        applescriptF([[tell application "ClashX Meta" to toggleProxy]])
    end
    hs.notify.new({title="ClashX Meta", informativeText="已切换系统代理"}):send()
end

-- 切换 TUN 模式
function mod.toggleTun()
    applescriptF([[tell application "ClashX Meta" to TunMode]])
    hs.notify.new({title="ClashX Meta", informativeText="已切换 TUN 模式"}):send()
end

---------------------------------------------------------------
-- 快捷键绑定
-- ⌘P  → 代理开关
-- ⌘T  → TUN 模式开关
---------------------------------------------------------------

local hyper = {"cmd"}

hs.hotkey.bind(hyper, "P", "ClashX Meta: Toggle Proxy", mod.toggleProxy)
hs.hotkey.bind(hyper, "T", "ClashX Meta: Toggle TUN",   mod.toggleTun)

---------------------------------------------------------------
--  End of file
---------------------------------------------------------------
