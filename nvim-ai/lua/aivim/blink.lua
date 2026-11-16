-- blink.cmp source: gtags 项目符号补全
local M = {}
M.__index = M

function M.new()
  return setmetatable({}, M)
end

function M:get_trigger_characters()
  return {}
end

function M:get_completions(ctx, callback)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local prefix = before:match("[%w_]+$") or ""
  local empty = { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
  if #prefix < 2 then
    callback(empty)
    return
  end
  local ok, idx = pcall(require, "aivim.index")
  if not ok then
    callback(empty)
    return
  end
  idx.complete(prefix, ctx.buf or 0, function(items)
    callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = items })
  end)
end

return M
