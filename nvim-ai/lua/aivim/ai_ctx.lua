-- aivim.ai_ctx: 把代码上下文"填进" agent 输入框,但不提交。
-- 你可以随后自己补充问题再按 Enter 发送。
--
-- 规则:
--   有 visual 选区      -> 选区
--   否则光标在函数内    -> 当前函数
--   否则                -> 当前行
-- 加文件上下文时只登记文件路径(Referenced Files),不复制内容。
local M = {}

local function visual_range()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  return s - 1, e - 1
end

local function function_range(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    local ft = vim.bo[buf].filetype
    if ft == "" then
      return nil
    end
    ok, parser = pcall(vim.treesitter.get_parser, buf, ft)
  end
  if not ok or not parser then
    return nil
  end
  local ok2, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok2 or not tree then
    return nil
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  while node and node:type() ~= "function_definition" do
    node = node:parent()
  end
  if not node then
    return nil
  end
  local sr, _, er = node:range()
  return sr, er
end

--- 取本次要放进输入框的代码范围
--- @return integer|nil start_row, integer|nil end_row, string scope
function M.pick_range()
  local buf = vim.api.nvim_get_current_buf()
  local sr, er = visual_range()
  if sr then
    return sr, er, "selection"
  end
  sr, er = function_range(buf)
  if sr then
    return sr, er, "function"
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  return row, row, "line"
end

--- 生成填进输入框的文本(不含提交)
function M.compose()
  local buf = vim.api.nvim_get_current_buf()
  local sr, er, scope = M.pick_range()
  if not sr then
    return nil, "无法确定上下文"
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local rel = path
  local root = vim.fs.root(path, { ".git", ".repo" })
  if root and path:sub(1, #root + 1) == root .. "/" then
    rel = path:sub(#root + 2)
  end
  local kind = ({
    selection = "选区",
    ["function"] = "当前函数",
    line = "当前行",
  })[scope] or scope

  -- agent 通过 Referenced Files 读取文件;这里只给范围提示,不复制代码
  return table.concat({
    ("@%s "):format(rel),
    ("（%s L%d-L%d）"):format(kind, sr + 1, er + 1),
    "",
    "请先不要改动代码。",
  }, "\n")
end

--- 把上下文写入 agent 输入框并聚焦,不提交
--- @param opts? { file?: boolean } file=true 时用 add_file 登记整个文件
function M.fill(opts)
  opts = opts or {}
  local agentic_ok, agentic = pcall(require, "agentic")
  if not agentic_ok then
    vim.notify("[aivim] agentic 未加载", vim.log.levels.WARN)
    return
  end

  local input_hint, err = M.compose()
  if not input_hint then
    vim.notify("[aivim] " .. err, vim.log.levels.WARN)
    return
  end

  -- 打开面板但不自动塞上下文
  agentic.open({ auto_add_to_context = false })

  -- 登记文件,让 agent 知道要读哪个文件
  if opts.file ~= false then
    local registry_ok, registry = pcall(require, "agentic.session_registry")
    if registry_ok then
      local session = registry.current()
      if session and session.session_id then
        pcall(function()
          session:add_file_to_session()
        end)
      end
    end
  end

  -- 写入输入框
  local ok = M.set_input(input_hint)
  if not ok then
    vim.notify("[aivim] 已打开面板,请手动粘贴:\n" .. input_hint, vim.log.levels.INFO)
  end
end

--- 找到 AgenticInput buffer 并写入文本,光标放到末尾
function M.set_input(text)
  local target
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "AgenticInput" then
      target = b
    end
  end
  if not target then
    return false
  end
  local lines = vim.split(text, "\n", { plain = true })
  pcall(vim.api.nvim_buf_set_lines, target, 0, -1, false, lines)
  -- 聚焦输入窗口
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == target then
      pcall(vim.api.nvim_set_current_win, w)
      pcall(vim.api.nvim_win_set_cursor, w, { #lines, #(lines[#lines] or "") })
      vim.cmd("startinsert!")
      break
    end
  end
  return true
end

return M
