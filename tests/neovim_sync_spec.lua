local root = assert(arg[1])
for _, failure in ipairs({ "none", "missing", "task", "process", "cleanup", "running", "exception" }) do
  local synced, exit_command, diagnostic = false, nil, nil
  local plugin = { name = "fixture", _ = { installed = false } }
  local removed = { name = "removed", _ = { installed = true } }
  local config = { plugins = { fixture = plugin }, to_clean = { removed } }
  local function task(name, failed, running)
    return {
      name = name,
      running = function()
        assert(synced, "inspected task before synchronization finished")
        return running
      end,
      has_errors = function(self) return failed or self.diagnostic ~= nil end,
      error = function(self, message) self.diagnostic = message end,
      output = function(self) return self.diagnostic or "fixture task diagnostic" end,
    }
  end
  local original_spawn = function() return failure ~= "process" end
  local task_module = { spawn = original_spawn }
  package.loaded["lazy.manage.task"] = task_module
  package.loaded["lazy.core.config"] = config
  package.loaded.lazy = {
    sync = function(options)
      assert(options.wait == true and options.show == false)
      if failure == "exception" then error("fixture sync exception") end
      plugin._.installed = failure ~= "missing"
      plugin._.tasks = { task("build", failure == "task", failure == "running") }
      task_module.spawn(plugin._.tasks[1], "/bin/sh")
      removed._.tasks = { task("clean", failure == "cleanup", false) }
      config.plugins.fixture = { name = plugin.name, _ = plugin._ }
      config.to_clean = {}
      synced = true
      -- The real Lazy sync API returns nil, including after task failures.
    end,
  }
  _G.vim = {
    api = { nvim_err_writeln = function(message) diagnostic = message end },
    cmd = function(command) exit_command = command end,
  }
  dofile(root .. "/lib/sync_neovim.lua")
  assert(task_module.spawn == original_spawn, "did not restore Lazy's process runner")
  if failure == "none" then
    assert(synced and exit_command == nil and diagnostic == nil)
  else
    assert(exit_command == "cquit 1", "sync failure did not fail the process: " .. failure)
    assert(diagnostic:find("stack traceback:", 1, true), "missing error context")
    local expected = ({
      missing = "fixture: plugin is not installed",
      task = "fixture: build failed\nfixture task diagnostic",
      process = "fixture: build failed\nProcess failed: /bin/sh",
      cleanup = "removed: clean failed\nfixture task diagnostic",
      running = "fixture: unfinished task build",
      exception = "fixture sync exception",
    })[failure]
    local first = assert(diagnostic:find(expected, 1, true), "missing failure diagnostic: " .. failure)
    assert(not diagnostic:find(expected, first + 1, true), "duplicated failure diagnostic: " .. failure)
  end
end
print("Neovim plugin sync completion and failure fixtures passed.")
