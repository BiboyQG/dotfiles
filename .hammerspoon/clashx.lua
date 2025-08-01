---------------------------------------------------------------
--  ClashX Meta 快捷键控制
---------------------------------------------------------------

local mod = {}

-- AppleScript 调用封装
local function applescriptF(script)
    return hs.osascript.applescript(script)
end

---------------------------------------------------------------
-- 判断系统代理是否开启
-- 返回 true = 已开代理；false = 直连
---------------------------------------------------------------
local function isProxyOn()
    local proxies = hs.network.configuration.open():proxies()
    return (proxies.HTTPEnable  == 1)         -- HTTP 代理
        or (proxies.HTTPSEnable == 1)         -- HTTPS 代理
        or (proxies.SOCKSEnable == 1)         -- SOCKS 代理
end

---------------------------------------------------------------
-- 切换系统代理，并根据结果弹出不同通知
---------------------------------------------------------------
function mod.toggleProxy()
    -- 记录切换前状态
    local before = isProxyOn()

    -- 调用 ClashX Meta 的 AppleScript 接口
    if not hs.application.get("ClashX Meta") then
        hs.application.launchOrFocus("/Applications/ClashX Meta.app")
        hs.timer.doAfter(1, function()
            applescriptF([[tell application "ClashX Meta" to toggleProxy]])
        end)
    else
        applescriptF([[tell application "ClashX Meta" to toggleProxy]])
    end

    -- 等 0.1 s 让系统写入新配置，然后再检查一次
    hs.timer.doAfter(0.1, function()
        local after = isProxyOn()
        local msg   = after and "🟢 已开启系统代理" or "🔴 已关闭系统代理"
        hs.notify.new({title = "ClashX Meta", informativeText = msg}):send()
    end)
end

---------------------------------------------------------------
-- 快捷键绑定
-- ⌘P  → 代理开关
---------------------------------------------------------------

local hyper = {"cmd"}

hs.hotkey.bind(hyper, "P", mod.toggleProxy)

---------------------------------------------------------------
--  End of file
---------------------------------------------------------------
