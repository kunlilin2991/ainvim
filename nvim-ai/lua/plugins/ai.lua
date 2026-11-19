-- AI 层:agentic.nvim (ACP)
-- 通过 ACP 接 Claude Code / Codex / Gemini / OpenCode 等;复用 CLI 已有登录/API key。
-- 前缀 ;i (vimrc 未占用);<C-\> 仍保留为“定义列表”,不在这里抢。
local WARN = vim.log.levels.WARN

-- 等 session 真正 ready 后再提交 prompt(会话创建是异步的)
local pending_submit = false
local function submit_when_ready(prompt)
  if pending_submit then
    vim.notify("[aivim] 正在等待 Agent 会话就绪…", WARN)
    return
  end
  pending_submit = true
  local tries = 0
  local function try()
    tries = tries + 1
    local ok, registry = pcall(require, "agentic.session_registry")
    local session = ok and registry.current() or nil
    if session and session._connection_error then
      pending_submit = false
      vim.notify("[aivim] Agent 连接失败,请检查 provider/登录状态", WARN)
      return
    end
    if session and not session._destroyed and session.session_id then
      local ok2, accepted = pcall(function()
        return session:_handle_input_submit(prompt)
      end)
      if ok2 and accepted then
        pending_submit = false
        return
      end
    end
    if tries < 40 then
      vim.defer_fn(try, 500)
    else
      pending_submit = false
      vim.notify("[aivim] Agent 会话未就绪;上下文已加入,请在面板里手动输入问题", WARN)
    end
  end
  try()
end

-- 直接用 treesitter 构造当前函数的 selection,不依赖 visual 模式/选区标记。
-- 返回 agentic.Selection(只包含当前函数),避免把整个文件塞进 chat。
local function node_at_cursor(buf)
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
  local row = pos[1] - 1
  local col = pos[2]
  return tree:root():named_descendant_for_range(row, col, row, col)
end

local function current_function_selection()
  local buf = vim.api.nvim_get_current_buf()
  local node = node_at_cursor(buf)
  if not node then
    return nil
  end
  while node and node:type() ~= "function_definition" do
    node = node:parent()
  end
  if not node then
    return nil
  end
  local sr, _, er = node:range()
  -- treesitter end_row 是包含的(不是 exclusive),所以取到 er+1
  local lines = vim.api.nvim_buf_get_lines(buf, sr, er + 1, false)
  if #lines == 0 then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local FileSystem = require("agentic.utils.file_system")
  local Theme = require("agentic.theme")
  return {
    lines = lines,
    start_line = sr + 1,
    end_line = er + 1,
    file_path = FileSystem.to_smart_path(path),
    file_type = Theme.get_language_from_path(path),
  }
end

local function add_selection(selection, opts)
  local registry = require("agentic.session_registry")
  registry.resolve_or_create(function(session)
    session.code_selection:add(selection)
    if session.session_key then
      registry.show_session(session.session_key, opts or { focus_prompt = true })
    end
  end)
end

local function add_selection_and_submit(selection, prompt)
  local registry = require("agentic.session_registry")
  registry.resolve_or_create(function(session)
    session.code_selection:add(selection)
    if session.session_key then
      registry.show_session(session.session_key, { focus_prompt = true })
    end
    submit_when_ready(prompt)
  end)
end

local function explain_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("[aivim] 当前 buffer 没有文件路径", WARN)
    return
  end
  -- 不附加整个文件;把路径给 agent,让它自己按需读取
  require("agentic").open({ auto_add_to_context = false })
  submit_when_ready(
    "请解析文件 " .. path
      .. ":主要模块、关键函数、数据结构、调用关系、初始化流程和潜在问题。你可以自己读取该文件。"
  )
end

local function explain_function()
  local selection = current_function_selection()
  if not selection then
    return explain_file()
  end
  add_selection_and_submit(
    selection,
    "请解释当前函数:逻辑、关键数据结构、调用关系、错误路径和潜在问题。"
  )
end

local function selected_line_count()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" then
    return 0
  end
  local s = vim.fn.line("v")
  local e = vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  return e - s + 1
end

local function explain_selection()
  local n = selected_line_count()
  if n == 0 then
    vim.notify("[aivim] 请先在 visual 模式选择代码", WARN)
    return
  end
  if n > 800 then
    vim.notify("[aivim] 选区太大(" .. n .. " 行);用 ;ie 解释当前函数或 ;iE 解析文件", WARN)
    return
  end
  require("agentic").add_selection()
  submit_when_ready("请解释选中的代码:逻辑、输入输出、边界条件和潜在问题。")
end

local function add_current_function()
  local selection = current_function_selection()
  if selection then
    add_selection(selection)
  else
    require("agentic").add_file()
  end
end

return {
  {
    "carlos-algms/agentic.nvim",
    event = "VeryLazy",
    opts = {
      provider = "claude-agent-acp",
      acp_configs = {
        -- agent 的 cwd 用 gtags 工作区根(wkl/sys_comp/普通工程),不要用 autochdir 的文件目录
        session_cwd = function(current_cwd)
          local name = vim.api.nvim_buf_get_name(0)
          local info = name ~= "" and require("aivim.workspace").detect(name) or nil
          if info and info.root then
            return info.root
          end
          return vim.fs.root(current_cwd, { ".git", ".repo" }) or current_cwd
        end,
      },
    },
    keys = {
      -- ── 终端 agent(推荐): 普通 shell + CLI,不经 ACP/MCP ──
      {
        "<leader>it",
        function() require("aivim.agent_term").toggle() end,
        mode = { "n", "t" },
        desc = "切换 agent 终端(claude/codex)",
      },
      {
        "<leader>if",
        function() require("aivim.agent_term").forward() end,
        mode = { "n", "x" },
        desc = "上下文打进 agent 终端(不提交)",
      },

      -- ── 快速解释(直连 API,不产生 agent 工具调用) ──
      { "<leader>ie", function() require("aivim.explain").explain() end, desc = "解释当前函数(浮窗)" },
      { "<leader>iv", function() require("aivim.explain").explain() end, mode = "x", desc = "解释选中代码(浮窗)" },
      { "<leader>iq", function() require("aivim.explain").ask() end, desc = "问这段代码(浮窗)" },

      -- ── ACP 面板(agentic.nvim) ──
      { "<leader>iT", function() require("agentic").toggle() end, mode = { "n", "v", "i" }, desc = "Agentic 面板(ACP)" },
      { "<leader>iP", function() require("agentic").new_session_with_provider() end, desc = "选择 provider" },
      { "<leader>iR", function() require("agentic").new_session() end, desc = "新会话" },
      { "<leader>ir", function() require("agentic").restore_session() end, desc = "恢复会话" },
      { "<leader>is", function() require("agentic").add_selection() end, mode = "x", desc = "发送选区" },
      { "<leader>ib", function() require("agentic").add_file() end, desc = "加入当前文件" },
      { "<leader>ia", add_current_function, desc = "加入当前函数" },
      { "<leader>iS", function() require("agentic").stop_generation() end, desc = "停止生成" },
      {
        "<leader>i?",
        function()
          vim.notify(
            table.concat({
              ";it       切换 agent 终端(claude/codex)   ;if 上下文打进终端(不提交)",
              ";ie/;iv/;iq  快速解释函数/选区/自定义问题(浮窗,直连API)",
              ";iT       Agentic 面板(ACP)   ;iP 选 provider",
              ";is/;ib/;ia  发送选区/加文件/加函数   ;iS 停止",
              ";ir       恢复会话",
            }, "\n"),
            vim.log.levels.INFO
          )
        end,
        desc = "AI 键位帮助",
      },
    },
  },
}
