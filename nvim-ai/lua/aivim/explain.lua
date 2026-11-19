-- aivim.explain: 轻量代码解释(直连 Anthropic 兼容 API,不走 agent 循环)
-- 只把当前函数/选区作为上下文,一次请求,结果写在浮窗里,不打开 Agentic 面板。
local M = {}

local state = { job = nil, win = nil, buf = nil }

local function gateway()
  local base = vim.env.ANTHROPIC_BASE_URL
  local token = vim.env.ANTHROPIC_AUTH_TOKEN or vim.env.ANTHROPIC_API_KEY
  if not base or base == "" then
    return nil, "未设置 ANTHROPIC_BASE_URL"
  end
  if not token or token == "" then
    return nil, "未设置 ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY"
  end
  local model = vim.env.AIVIM_EXPLAIN_MODEL
    or vim.env.ANTHROPIC_DEFAULT_SONNET_MODEL
    or "claude-sonnet-4-20250514"
  return { base = base:gsub("/+$", ""), token = token, model = model }
end

-- 取当前函数体;不在函数内则返回 nil
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

local function visual_lines()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" then
    return nil
  end
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  return s - 1, e - 1
end

local function current_context()
  local buf = vim.api.nvim_get_current_buf()
  local sr, er = visual_lines()
  if not sr then
    sr, er = function_range(buf)
  end
  if not sr then
    return nil, "光标不在函数内,也没有选中代码"
  end
  if er - sr > 400 then
    return nil, string.format("范围太大(%d 行),请选中要解释的代码", er - sr + 1)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, sr, er + 1, false)
  local path = vim.api.nvim_buf_get_name(buf)
  local lang = vim.bo[buf].filetype
  local body = table.concat(lines, "\n")
  return {
    path = path,
    lang = lang,
    start_line = sr + 1,
    end_line = er + 1,
    body = body,
  }
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win, state.buf = nil, nil
end

local function open_float()
  close()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = "markdown"
  local width = math.min(100, math.max(50, vim.o.columns - 20))
  local height = math.min(30, math.max(10, vim.o.lines - 10))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Explain ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 0
  vim.bo[buf].modifiable = false
  state.buf, state.win = buf, win
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "关闭解释窗口" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "关闭解释窗口" })
  return buf
end

local function append(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.split(text, "\n", { plain = true })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  vim.bo[buf].modifiable = false
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_cursor, state.win, { math.max(1, vim.api.nvim_buf_line_count(buf)), 0 })
  end
end

local function build_prompt(ctx, question)
  return table.concat({
    "请解释下面这段代码,回答使用中文,简洁直接:",
    "1) 它做什么",
    "2) 关键数据结构和控制流",
    "3) 边界条件/错误路径",
    "4) 潜在问题(如果有)",
    "",
    question ~= "" and ("额外问题: " .. question) or "",
    "",
    "文件: " .. ctx.path,
    "行: " .. ctx.start_line .. "-" .. ctx.end_line,
    "语言: " .. ctx.lang,
    "",
    "```" .. ctx.lang,
    ctx.body,
    "```",
  }, "\n")
end

local function request(ctx, question)
  local cfg, err = gateway()
  if not cfg then
    vim.notify("[aivim] " .. err, vim.log.levels.ERROR)
    return
  end

  local payload = vim.json.encode({
    model = cfg.model,
    max_tokens = 2048,
    messages = { { role = "user", content = build_prompt(ctx, question) } },
  })

  local buf = open_float()
  append(buf, "⏳ 请求中…")

  local cmd = {
    "curl", "-sS", "--max-time", "120",
    cfg.base .. "/v1/messages",
    "-H", "Authorization: Bearer " .. cfg.token,
    "-H", "anthropic-version: 2023-06-01",
    "-H", "content-type: application/json",
    "-d", payload,
  }

  local out = {}
  state.job = vim.system(cmd, {
    text = true,
    stdout = function(_, data)
      if data then
        out[#out + 1] = data
      end
    end,
    stderr = function(_, data)
      if data then
        out[#out + 1] = data
      end
    end,
  }, function(res)
    vim.schedule(function()
      state.job = nil
      local raw = table.concat(out)
      local ok, decoded = pcall(vim.json.decode, raw)
      if not ok or type(decoded) ~= "table" then
        append(buf, "\n❌ 响应解析失败:\n" .. raw:sub(1, 800))
        return
      end
      if decoded.error then
        local msg = type(decoded.error) == "table" and (decoded.error.message or vim.inspect(decoded.error))
          or tostring(decoded.error)
        append(buf, "\n❌ API 错误: " .. msg)
        return
      end
      local parts = {}
      for _, block in ipairs(decoded.content or {}) do
        if block.type == "text" and block.text then
          parts[#parts + 1] = block.text
        end
      end
      local text = table.concat(parts, "\n")
      if text == "" then
        text = "(空响应)\n" .. raw:sub(1, 500)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        vim.bo[buf].modifiable = false
      end
      append(buf, text)
    end)
  end)
end

--- 解释当前函数(光标所在函数)或选区
--- @param opts? { question?: string }
function M.explain(opts)
  opts = opts or {}
  if state.job then
    vim.notify("[aivim] 上一次解释还在进行中", vim.log.levels.WARN)
    return
  end
  local ctx, err = current_context()
  if not ctx then
    vim.notify("[aivim] " .. err, vim.log.levels.WARN)
    return
  end
  request(ctx, opts.question or "")
end

--- 解释时附带自定义问题
function M.ask()
  local ctx, err = current_context()
  if not ctx then
    vim.notify("[aivim] " .. err, vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "问这段代码: " }, function(input)
    if not input or input == "" then
      return
    end
    request(ctx, input)
  end)
end

function M.close()
  close()
end

return M
