local M = {}

function M.quote(value)
  return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

return M
