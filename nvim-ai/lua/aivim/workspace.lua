-- 工作区检测:调用 tools/aicx.py,结果按目录缓存。
-- 不在 Lua 里硬编码任何项目路径。
local M = {}

local config_dir = vim.fn.stdpath("config")
local script = config_dir .. "/tools/aicx.py"
local python = vim.fn.exepath("python3")
if python == "" then
  python = "python3"
end

local cache = {}

local function dir_of(path)
  local p = vim.fn.fnamemodify(path or "", ":p")
  if p == "" then
    return nil
  end
  if vim.fn.isdirectory(p) == 0 then
    p = vim.fn.fnamemodify(p, ":h")
  end
  return p
end

function M.script()
  return script
end

function M.python()
  return python
end

function M.invalidate()
  cache = {}
end

---@param path string|nil
---@return table|nil
function M.detect(path)
  if not path or path == "" then
    path = vim.api.nvim_buf_get_name(0)
  end
  local dir = dir_of(path)
  if not dir then
    return nil
  end
  if cache[dir] then
    return cache[dir]
  end
  local res = vim.system({ python, script, "workspace", "detect", "--json", dir }, { text = true }):wait()
  if res.code ~= 0 or not res.stdout or res.stdout == "" then
    return nil
  end
  local ok, info = pcall(vim.json.decode, res.stdout)
  if not ok or type(info) ~= "table" or not info.root then
    return nil
  end
  cache[dir] = info
  return info
end

return M
