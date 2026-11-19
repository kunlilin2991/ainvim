-- aivim.agent_term: 在 Neovim 里开一个 terminal 直接跑 agent CLI(claude/codex/...),
-- 把光标处的上下文"打字"进它的输入框,但不按回车 —— 由你补充问题后自己发送。
--
-- 不经过 ACP/MCP,只是普通终端 + chansend。
local M = {}

-- 每个 tabpage 一个终端
local terms = {}
-- 最近一次代码窗口的 buffer,避免终端聚焦时 compose 取到 term://
local last_code_buf = nil

--- 记录当前代码 buffer(在调用前执行)
function M.mark_code_buf()
  local b = vim.api.nvim_get_current_buf()
  if vim.bo[b].buftype ~= "terminal" and vim.api.nvim_buf_get_name(b) ~= "" then
    last_code_buf = b
  end
end

local function code_buf()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype ~= "terminal" and vim.api.nvim_buf_get_name(cur) ~= "" then
    last_code_buf = cur
    return cur
  end
  if last_code_buf and vim.api.nvim_buf_is_valid(last_code_buf) then
    return last_code_buf
  end
  return cur
end

local function agent_cmd()
  return vim.env.AIVIM_AGENT_CMD or "claude"
end

local function term_alive(entry)
  if not entry then
    return false
  end
  if not (entry.buf and vim.api.nvim_buf_is_valid(entry.buf)) then
    return false
  end
  return entry.job and vim.fn.jobwait({ entry.job }, 0)[1] == -1
end

--- 打开(或复用)当前 tab 的 agent 终端
--- @param opts? { cmd?: string, vertical?: boolean }
function M.open(opts)
  opts = opts or {}
  local tab = vim.api.nvim_get_current_tabpage()
  local entry = terms[tab]
  if term_alive(entry) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_buf(w) == entry.buf then
        vim.api.nvim_set_current_win(w)
        vim.cmd("startinsert")
        return entry
      end
    end
    return entry
  end

  local cmd = opts.cmd or agent_cmd()
  local height = math.max(10, math.floor(vim.o.lines * 0.4))
  if opts.vertical then
    vim.cmd("botright vertical new")
  else
    vim.cmd(height .. "new")
  end
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart({ vim.o.shell, "-lc", cmd }, {
    term = true,
    on_exit = function()
      vim.schedule(function()
        terms[tab] = nil
      end)
    end,
  })
  vim.bo[buf].bufhidden = "hide"
  vim.keymap.set("n", "q", function()
    vim.cmd("hide")
  end, { buffer = buf, desc = "隐藏 agent 终端" })
  vim.keymap.set("t", "<C-q>", function()
    vim.cmd("hide")
  end, { buffer = buf, desc = "隐藏 agent 终端" })

  entry = { buf = buf, job = job, tab = tab }
  terms[tab] = entry
  -- 隐藏终端时不要退出插入模式
  vim.cmd("startinsert")
  return entry
end

function M.toggle(opts)
  local tab = vim.api.nvim_get_current_tabpage()
  local entry = terms[tab]
  if term_alive(entry) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_buf(w) == entry.buf then
        vim.cmd("hide")
        return
      end
    end
    vim.api.nvim_set_current_buf(entry.buf)
    vim.cmd("startinsert")
    return
  end
  M.open(opts)
end

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

--- 有选区用选区,否则函数,否则当前行
local function pick()
  local buf = vim.api.nvim_get_current_buf()
  local sr, er = visual_range()
  if sr then
    return sr, er, "选区"
  end
  sr, er = function_range(buf)
  if sr then
    return sr, er, "当前函数"
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  return row, row, "当前行"
end

--- 生成要发进终端输入框的文本(单行,方便 TUI 输入)
function M.compose()
  local buf = code_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return nil, "当前 buffer 没有文件路径"
  end
  local root = vim.fs.root(path, { ".git", ".repo" })
  local rel = path
  if root and path:sub(1, #root + 1) == root .. "/" then
    rel = path:sub(#root + 2)
  end
  local sr, er, kind = pick()
  return ("@%s:%d-%d  (%s)"):format(rel, sr + 1, er + 1, kind)
end

--- 把文本作为"粘贴"送进终端,不发送回车
function M.send_text(text)
  local tab = vim.api.nvim_get_current_tabpage()
  local entry = terms[tab]
  if not term_alive(entry) then
    entry = M.open()
    -- 等 CLI 起来(粗略)
    vim.wait(1200, function()
      return vim.api.nvim_buf_is_valid(entry.buf)
    end)
  end
  if not entry or not entry.job then
    return false, "agent 终端未启动"
  end
  local chan = entry.job
  if not chan or chan <= 0 then
    return false, "拿不到终端 channel"
  end
  -- 括号粘贴模式:多行/特殊字符不会被当成按键
  vim.fn.chansend(chan, "\27[200~" .. text .. "\27[201~")
  -- 聚焦终端并进入插入模式
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(w) == entry.buf then
      vim.api.nvim_set_current_win(w)
      break
    end
  end
  vim.cmd("startinsert")
  return true
end

--- 把光标处上下文送进 agent 终端输入框(不提交)
function M.forward()
  M.mark_code_buf()
  local text, err = M.compose()
  if not text then
    vim.notify("[aivim] " .. err, vim.log.levels.WARN)
    return
  end
  local ok, serr = M.send_text(text)
  if not ok then
    vim.notify("[aivim] " .. serr, vim.log.levels.WARN)
  end
end

--- 只打开终端
function M.focus()
  M.open()
end

return M
