---------------------------------------------------------------------------
--  WeChat LLM-reply with AXUIElement + Ollama
--  ⌘G → 读取最近 nMessages 条 → 调用 qwen2.5:14b → 写入输入框
---------------------------------------------------------------------------

local ax        = require("hs.axuielement")
local appFinder = require("hs.appfinder")
local hotkey    = require("hs.hotkey")
local http      = require("hs.http")
local json      = require("hs.json")

-- ⚙️ tweak here
local nMessages  = 10               -- 最近 N 条
local appName    = "WeChat"        -- 确保已运行
local modelName  = "qwen2.5:14b"
local ollamaBin = "/usr/local/bin/ollama"

---------------------------------------------------------------------------
--  AX helper：深度优先查找
---------------------------------------------------------------------------
local function dfs(el, matcher)
    if not el or not el.AXRole then return nil end
    if matcher(el) then return el end
    for _,child in ipairs(el.AXChildren or {}) do
        local found = dfs(child, matcher)
        if found then return found end
    end
end

---------------------------------------------------------------------------
--  收集最近 N 条消息文本
---------------------------------------------------------------------------
local function collectLastMessages(axApp, n)
    local msgList = dfs(axApp, function(el)
        return el.AXRole == "AXList" and (el.AXTitle or "") == "Messages"
    end)
    if not msgList then error("🥲 找不到消息列表") end

    local children = msgList.AXChildren or {}
    if #children == 0 then error("✉️ 没有可读取的消息") end

    local first = math.max(1, #children - n + 1)
    local texts = {}
    for i = first, #children do
        local msg = children[i]
        if msg and msg.AXRole == "AXStaticText" then
            table.insert(texts, msg.AXValue or msg.AXTitle or "")
        end
    end
    return texts
end

---------------------------------------------------------------------------
--  调用 Ollama 生成回复（流式）
--  prompt   : 要发送给模型的提示
--  onUpdate : 每收到新 token 时调用，一般用来写入输入框
---------------------------------------------------------------------------
local function requestOllama(prompt, onUpdate)
    local ollamaUrl = "http://localhost:11434/api/generate"
    local requestBody = {
        model = modelName,
        prompt = prompt,
        stream = true
    }

    local accumulatedText = ""

    http.asyncPost(ollamaUrl, json.encode(requestBody), {
        ["Content-Type"] = "application/json"
    }, function(status, body, headers)
        if status ~= 200 then
            hs.alert.show("❌ Ollama 请求失败: " .. tostring(status))
            return
        end

        -- 处理流式响应：每行是一个 JSON 对象
        for line in body:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$")  -- 去除首尾空白
            if line ~= "" then
                local ok, jsonObj = pcall(json.decode, line)
                if ok and jsonObj.response then
                    accumulatedText = accumulatedText .. jsonObj.response

                    -- 实时更新输入框
                    if onUpdate then
                        onUpdate(accumulatedText)
                    end

                    -- 如果 done=true，表示流结束
                    if jsonObj.done then
                        hs.notify.new({title = "WeChat", informativeText = "✅ 回复生成完成"}):send()
                        break
                    end
                end
            end
        end
    end)
end


---------------------------------------------------------------------------
--  把文本写入输入框
---------------------------------------------------------------------------
local function writeToInput(axApp, text)
    local input = dfs(axApp, function(el) return el.AXRole == "AXTextArea" end)
    if not input then
        hs.alert.show("✏️ 找不到输入框")
        return
    end
    pcall(function() input.AXFocused = true end)   -- 聚焦
    -- 直接设置值更稳定；如遇失效，可以改用 hs.eventtap.keyStrokes(text)
    input.AXValue = text
end

---------------------------------------------------------------------------
--  热键触发主流程
---------------------------------------------------------------------------
local function handleHotkey()
    local app = appFinder.appFromName(appName)
    if not app then hs.alert.show(appName.." 未运行"); return end
    local axApp = ax.applicationElement(app)

    local ok, texts = pcall(collectLastMessages, axApp, nMessages)
    if not ok then hs.alert.show(texts); return end

    local prompt = table.concat(texts, "\n")
    prompt = "你是一个真实的即时聊天软件用户，正在与其他用户进行日常对话。请根据以下聊天历史记录，理解对话的语境、语气和情感，生成一句简短、自然、得体的回复。回复应符合真实用户的表达方式，既不过于生硬，也不夸张造作，避免AI腔。请用中文作答，最多不超过25字。聊天记录：" .. prompt
    hs.notify.new({title = "WeChat", informativeText = "🤖 正在生成回复..."}):send()

    requestOllama(prompt, function(reply)
        writeToInput(axApp, reply)
    end)
end

hotkey.bind({"cmd"}, "g", handleHotkey)
