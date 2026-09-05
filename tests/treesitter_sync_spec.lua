local root = assert(arg[1])
local original_dofile = dofile
for _, failure in ipairs({ "none", "install", "update", "query", "timeout" }) do
  local installed, updated, verified = false, false, 0
  local function task(kind)
    return { wait = function(_, timeout)
      assert(timeout == 300000)
      if failure == "timeout" then error("timeout") end
      if kind == "install" then installed = true else
        assert(installed, "update started before installation finished")
        updated = true
      end
      return failure ~= kind
    end }
  end
  package.loaded["nvim-treesitter"] = {
    install = function() return task("install") end,
    update = function() return task("update") end,
  }
  _G.vim = {
    fn = { stdpath = function() return "/fixture" end },
    opt = { runtimepath = { prepend = function() end } },
    treesitter = {
      language = { add = function()
        assert(installed and updated, "validated before parser jobs finished")
      end },
      query = { get = function()
        verified = verified + 1
        if failure == "query" then error("incompatible parser") end
        return {}
      end },
    },
  }
  _G.dofile = function(path)
    if path == "/fixture/lazy/nvim-treesitter/plugin/filetypes.lua" then return end
    return original_dofile(path)
  end
  local ok = pcall(original_dofile, root .. "/lib/sync_treesitter.lua")
  assert(ok == (failure == "none"), "parser failure did not propagate: " .. failure)
  if failure == "none" then assert(verified == 4) end
end
_G.dofile = original_dofile
print("Tree-sitter completion and failure fixtures passed.")
