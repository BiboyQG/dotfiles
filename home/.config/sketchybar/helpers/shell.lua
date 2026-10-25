local M = {}

function M.quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

return M
