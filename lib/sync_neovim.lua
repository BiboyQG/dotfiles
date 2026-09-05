-- Lazy waits for failed tasks too; +qa alone would still exit successfully.
local ok, message = xpcall(function()
  local config = require("lazy.core.config")
  local checked = {}
  local plugins = {}
  local function remember(collection)
    for _, plugin in pairs(collection) do
      if not checked[plugin] then
        checked[plugin] = true
        plugins[#plugins + 1] = plugin
      end
    end
  end

  remember(config.plugins)
  -- Lazy replaces to_clean during sync, so retain the cleanup task objects.
  remember(config.to_clean)
  local task = require("lazy.manage.task")
  local original_spawn = task.spawn
  -- Headless streaming can leave failed subprocesses without a task error,
  -- including a shell build that exits nonzero without producing any output.
  task.spawn = function(self, command, options)
    local success = original_spawn(self, command, options)
    if not success and not self:has_errors() then
      self:error("Process failed: " .. command)
    end
    return success
  end
  local synced, sync_error = pcall(function()
    require("lazy").sync({ wait = true, show = false })
  end)
  task.spawn = original_spawn
  assert(synced, sync_error)
  remember(config.plugins)
  remember(config.to_clean)

  local failures = {}
  local checked_tasks = {}
  for _, plugin in ipairs(plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      if not checked_tasks[task] then
        checked_tasks[task] = true
        if task:running() then
          failures[#failures + 1] = plugin.name .. ": unfinished task " .. task.name
        elseif task:has_errors() then
          failures[#failures + 1] = plugin.name .. ": " .. task.name .. " failed\n" .. task:output()
        end
      end
    end
  end
  for _, plugin in pairs(config.plugins) do
    if not plugin._.installed then
      failures[#failures + 1] = plugin.name .. ": plugin is not installed"
    end
  end
  assert(#failures == 0, "Neovim plugin sync failed:\n" .. table.concat(failures, "\n"))
  print("Neovim plugins synchronized and verified.")
end, debug.traceback)

if not ok then
  vim.api.nvim_err_writeln(message)
  vim.cmd("cquit 1")
end
