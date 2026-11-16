-- aivim.index: 通用 GNU GLOBAL 索引/查询层
--  * 工作区检测交给 tools/aicx.py(不硬编码任何路径)
--  * 建库/增量交给 aicx.py,缓存永远在 ~/.cache/nvim-ai/index
--  * 查询直接用 global,绝对路径进 quickfix
--  * 打开新工作区时自动检测;没有索引则后台异步建
local M = { VERSION = "2026-11-16.4" }
local workspace = require("aivim.workspace")
local python = workspace.python()
local script = workspace.script()

local WARN = vim.log.levels.WARN
local ERR = vim.log.levels.ERROR

local building = {}
local pending = {}
local jobs = {}

local function notify(msg, level)
  vim.notify("[aivim] " .. msg, level or vim.log.levels.INFO)
end

local function file_ext_ok(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  if ft == "c" or ft == "cpp" or ft == "objc" or ft == "objcpp" or ft == "asm" then
    return true
  end
  return name:match("%.[ch]$") ~= nil
    or name:match("%.S$") ~= nil
    or name:match("%.cc$") ~= nil
    or name:match("%.cpp$") ~= nil
    or name:match("%.cxx$") ~= nil
    or name:match("%.hpp$") ~= nil
    or name:match("%.hh$") ~= nil
end

local function is_code_buffer(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  if name == "" then
    return false
  end
  if ft == "qf" or ft == "help" or ft == "nofile" or ft == "terminal" or ft == "prompt" then
    return false
  end
  return true
end

function M.workspace(buf)
  buf = buf or 0
  local ws = vim.b[buf].aivim_ws
  if ws then
    return ws
  end
  -- quickfix/help/terminal 等无文件 buffer:回退到上一个代码工作区,
  -- 否则会拿空文件名去检测,甚至误把 home 当工程。
  if not is_code_buffer(buf) then
    if vim.g.aivim_last_ws then
      return vim.g.aivim_last_ws
    end
    local alt = vim.fn.bufnr("#")
    if alt > 0 and is_code_buffer(alt) then
      local info = vim.b[alt].aivim_ws or workspace.detect(vim.api.nvim_buf_get_name(alt))
      if info then
        return info
      end
    end
    return nil
  end
  local info = workspace.detect(vim.api.nvim_buf_get_name(buf))
  if info then
    vim.b[buf].aivim_ws = info
    vim.g.aivim_last_ws = info
  end
  return info
end

local function ws_env(info)
  return { GTAGSROOT = info.root, GTAGSDBPATH = info.cache }
end

-- 重新检测当前 buffer 的工作区(绕过 workspace 模块的目录缓存)
function M.refresh(buf)
  buf = buf or 0
  workspace.invalidate()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local info = workspace.detect(name)
  if info then
    vim.b[buf].aivim_ws = info
    vim.g.aivim_last_ws = info
  end
  return info
end

-- ── 建库/增量 ─────────────────────────────────────────────────────────
function M.build(root, profile, arch, opts)
  opts = opts or {}
  if not root then
    notify("无法识别工作区", WARN)
    return
  end
  if vim.fn.filereadable(script) == 0 then
    notify("找不到 " .. script, ERR)
    return
  end
  if building[root] then
    return
  end
  building[root] = true
  vim.g.aivim_indexing = vim.g.aivim_indexing or {}
  vim.g.aivim_indexing[root] = true
  notify("后台建索引: " .. root .. " (" .. (profile or "auto") .. (opts.force and ", force" or "") .. ")")

  local args = { python, script, "index", "build", root, "--json" }
  if profile then
    table.insert(args, "--profile")
    table.insert(args, profile)
  end
  if arch then
    table.insert(args, "--arch")
    table.insert(args, arch)
  end
  if opts.force then
    table.insert(args, "--force")
  end

  jobs[root] = vim.system(args, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      building[root] = nil
      jobs[root] = nil
      if vim.g.aivim_indexing then
        vim.g.aivim_indexing[root] = nil
      end
      workspace.invalidate()
      if res.code == 0 then
        local ok, data = pcall(vim.json.decode, res.stdout or "")
        if ok and type(data) == "table" and data.ok then
          notify(string.format("索引完成: %s 文件 / %.1fs / %.0fMB", data.files or "?", data.seconds or 0, (data.bytes or 0) / 1048576))
        else
          notify("索引完成")
        end
      else
        notify("索引失败: " .. ((res.stderr or "") .. (res.stdout or "")):sub(1, 800), ERR)
      end
      workspace.invalidate()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
          local n = vim.api.nvim_buf_get_name(b)
          if n ~= "" and vim.startswith(n, root) then
            local info = workspace.detect(n)
            if info then
              vim.b[b].aivim_ws = info
              if is_code_buffer(b) then
                vim.bo[b].tagfunc = "v:lua.aivim_tagfunc"
              end
            end
          end
        end
      end
    end)
  end)
end

function M.update(buf)
  local info = M.workspace(buf or 0)
  if not info or not info.indexed then
    return
  end
  local root = info.root
  if pending[root] or building[root] then
    return
  end
  pending[root] = true
  vim.defer_fn(function()
    pending[root] = nil
    if building[root] then
      return
    end
    building[root] = true
    jobs[root] = vim.system({
      python, script, "index", "update", root, "--json",
      "--profile", info.profile, "--arch", info.arch,
    }, { cwd = root, text = true }, function(res)
      vim.schedule(function()
        building[root] = nil
        jobs[root] = nil
        workspace.invalidate()
        if res.code ~= 0 then
          notify("索引增量失败: " .. ((res.stderr or "") .. (res.stdout or "")):sub(1, 400), WARN)
        end
      end)
    end)
  end, 2000)
end

function M.ensure(buf)
  if not file_ext_ok(buf) then
    return
  end
  local info = workspace.detect(vim.api.nvim_buf_get_name(buf))
  if not info then
    return
  end
  vim.b[buf].aivim_ws = info
  vim.g.aivim_last_ws = info
  vim.bo[buf].tagfunc = "v:lua.aivim_tagfunc"
  if not info.indexed then
    M.build(info.root, info.profile, info.arch)
  elseif info.stale then
    M.update(buf)
  end
end

-- ── 查询 ─────────────────────────────────────────────────────────────
local MAX_ITEMS = 5000

local function parse_grep(out, limit, root)
  limit = limit or MAX_ITEMS
  local items = {}
  local base = root and root:gsub("/+$", "") or nil
  for line in (out or ""):gmatch("[^\r\n]+") do
    local file, lno, text = line:match("^(.-):(%d+):(.*)$")
    if file then
      if base and not file:match("^/") then
        file = base .. "/" .. file:gsub("^%./", "")
      end
      items[#items + 1] = { filename = file, lnum = tonumber(lno), text = text }
      if #items >= limit then
        return items, true
      end
    end
  end
  return items, false
end

local function set_qf(title, items, truncated)
  if #items == 0 then
    notify("无结果: " .. title)
    return
  end
  if truncated then
    title = title .. " [truncated " .. MAX_ITEMS .. "]"
  end
  vim.fn.setqflist({}, " ", { title = title, items = items })
  if #items == 1 then
    vim.cmd("cfirst")
  else
    vim.cmd("copen")
  end
end

function M.query(flag, word)
  word = word or vim.fn.expand("<cword>")
  if not word or word == "" then
    notify("光标下没有符号", WARN)
    return
  end
  local info = M.workspace(0)
  if not info then
    notify("无法识别工作区", WARN)
    return
  end
  if not info.indexed then
    notify("索引尚未建立(后台进行中);文本查询先用 rg 兜底", WARN)
    if flag == "-g" then
      M.egrep(word)
    end
    return
  end
  local args = { "global", "-a" }
  if flag ~= "-P" then
    table.insert(args, "--result=grep")
  end
  table.insert(args, flag)
  table.insert(args, word)
  local res = vim.system(args, { cwd = info.root, env = ws_env(info), text = true }):wait()
  if res.code ~= 0 and (not res.stdout or res.stdout == "") then
    notify("gtags 查询失败: " .. flag, WARN)
    return
  end
  local items = {}
  if flag == "-P" then
    for line in (res.stdout or ""):gmatch("[^\r\n]+") do
      items[#items + 1] = { filename = line, lnum = 1, text = line }
    end
  else
    local truncated
    items, truncated = parse_grep(res.stdout)
    set_qf("gtags " .. flag .. " " .. word, items, truncated)
    return
  end
  set_qf("gtags " .. flag .. " " .. word, items)
end

function M.file(pattern)
  if not pattern or pattern == "" then
    pattern = vim.fn.expand("<cfile>")
  end
  M.query("-P", pattern)
end

local function regex_escape(s)
  return (s:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "\\%1"))
end

local function rg_exe()
  local p = vim.fn.exepath("rg")
  if p ~= "" then
    return p
  end
  return nil
end

-- 文本搜索优先用索引的 files.list(精确、只扫已索引文件);没有列表时按 profile 目录兜底。
local function search_roots(info)
  local candidates
  if info.profile == "qcom-kernel" then
    candidates = { "kernel_platform/common", "kernel_platform/qcom", "vendor/qcom/opensource" }
  elseif info.profile == "kernel" then
    candidates = { "." }
  elseif info.profile == "android-platform" then
    candidates = { "system", "hardware", "vendor", "frameworks/native" }
  else
    candidates = { "." }
  end
  local roots = {}
  for _, p in ipairs(candidates) do
    if p == "." or vim.fn.isdirectory(info.root .. "/" .. p) == 1 then
      roots[#roots + 1] = p
    end
  end
  if #roots == 0 then
    roots = { "." }
  end
  return roots
end

-- kind: callers / assignments / includes / egrep
function M.search(kind, pattern, title)
  local info = M.workspace(0)
  if not info then
    notify("无法识别工作区", WARN)
    return
  end

  local pat = pattern
  if kind == "callers" then
    pat = "\\b" .. regex_escape(pattern) .. "\\s*\\("
  elseif kind == "assignments" then
    pat = "\\b" .. regex_escape(pattern) .. "\\s*="
  elseif kind == "includes" then
    pat = "^\\s*#\\s*include.*" .. regex_escape(pattern)
  end

  local rg = rg_exe()
  local list_path = info.cache .. "/files.list"
  local use_list = info.indexed and vim.fn.filereadable(list_path) == 1
  local cmd

  if use_list then
    local script
    if rg then
      script = [[tr '\n' '\0' < "$1" | xargs -0 -r rg --no-heading --color never -n -- "$2" | head -n 5001]]
    else
      script = [[tr '\n' '\0' < "$1" | xargs -0 -r grep -nIE -e "$2" -- | head -n 5001]]
    end
    cmd = { "sh", "-c", script, "sh", list_path, pat }
  else
    local roots = search_roots(info)
    local code_globs = { "*.c", "*.h", "*.S", "*.cc", "*.cpp", "*.cxx", "*.hpp", "*.hh" }
    if rg then
      cmd = { rg, "--no-heading", "--color", "never", "-n" }
      for _, g in ipairs(code_globs) do
        vim.list_extend(cmd, { "-g", g })
      end
      vim.list_extend(cmd, { "--", pat })
      vim.list_extend(cmd, roots)
    else
      cmd = {
        "grep", "-rnI", "-E", "--color=never",
        "--exclude-dir=.git", "--exclude-dir=.repo", "--exclude-dir=out",
        "--exclude-dir=prebuilts", "--exclude-dir=build",
      }
      for _, g in ipairs(code_globs) do
        vim.list_extend(cmd, { "--include=" .. g })
      end
      vim.list_extend(cmd, { "-e", pat })
      vim.list_extend(cmd, roots)
    end
  end

  local res = vim.system(cmd, { cwd = info.root, text = true }):wait()
  if res.code == 127 then
    notify("找不到 rg/grep/xargs", WARN)
    return
  end
  local items, truncated = parse_grep(res.stdout, MAX_ITEMS, info.root)
  set_qf(title, items, truncated)
end

function M.includes(word)
  if not word or word == "" then
    return
  end
  M.search("includes", word, "includes " .. word)
end

function M.callers(word)
  if not word or word == "" then
    return
  end
  M.search("callers", word, "callers " .. word)
end

function M.assignments(word)
  if not word or word == "" then
    return
  end
  M.search("assignments", word, "assignments " .. word)
end

function M.egrep(pattern)
  if not pattern or pattern == "" then
    return
  end
  M.search("egrep", pattern, "egrep " .. pattern)
end

-- 文本查询(cscope text 的替代):用 grep/rg,不用 global -g(大库上太慢)
function M.text(word)
  if not word or word == "" then
    return
  end
  M.search("egrep", regex_escape(word), "text " .. word)
end

-- 符号查询(cscope symbol 的替代):定义 + 引用合并去重
function M.symbol(word)
  word = word or vim.fn.expand("<cword>")
  if not word or word == "" then
    notify("光标下没有符号", WARN)
    return
  end
  local info = M.workspace(0)
  if not info then
    notify("无法识别工作区", WARN)
    return
  end
  if not info.indexed then
    notify("索引尚未建立", WARN)
    return
  end
  local seen, items = {}, {}
  local truncated = false
  for _, flag in ipairs({ "-d", "-r" }) do
    local res = vim.system({ "global", "-a", "--result=grep", flag, word }, {
      cwd = info.root, env = ws_env(info), text = true,
    }):wait()
    for line in (res.stdout or ""):gmatch("[^\r\n]+") do
      local file, lno, text = line:match("^(.-):(%d+):(.*)$")
      if file then
        local key = file .. ":" .. lno
        if not seen[key] then
          seen[key] = true
          items[#items + 1] = { filename = file, lnum = tonumber(lno), text = text }
          if #items >= MAX_ITEMS then
            truncated = true
            break
          end
        end
      end
    end
    if truncated then
      break
    end
  end
  set_qf("symbol " .. word, items, truncated)
end

-- callees: treesitter 取当前函数体里的调用名,选择后跳到定义
function M.callees()
  local buf = vim.api.nvim_get_current_buf()
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  if not ok or not node then
    notify("当前 buffer 没有 treesitter parser", WARN)
    return
  end
  while node and node:type() ~= "function_definition" do
    node = node:parent()
  end
  if not node then
    notify("光标不在函数内", WARN)
    return
  end
  local text = vim.treesitter.get_node_text(node, buf)
  local skip = {
    ["if"] = true, ["for"] = true, ["while"] = true, ["switch"] = true, ["return"] = true,
    sizeof = true, typeof = true, ["__typeof__"] = true, min = true, max = true,
    likely = true, unlikely = true, static = true, const = true,
  }
  local fname = text:match("([%a_][%w_]*)%s*%b()%s*{")
  if fname then
    skip[fname] = true
  end
  local seen, names = {}, {}
  for name in text:gmatch("([%a_][%w_]*)[%s]*%(") do
    if not skip[name] and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  if #names == 0 then
    notify("当前函数没有识别到调用")
    return
  end
  vim.ui.select(names, { prompt = "callees -> 定义" }, function(choice)
    if choice then
      vim.cmd("tag " .. choice)
    end
  end)
end

function M.complete(prefix, buf, cb)
  local info = M.workspace(buf)
  if not info or not info.indexed then
    cb({})
    return
  end
  vim.system({ "global", "-c", prefix }, { cwd = info.root, env = ws_env(info), text = true }, function(res)
    local items = {}
    if res.code == 0 and res.stdout then
      for name in res.stdout:gmatch("[^\r\n]+") do
        items[#items + 1] = { label = name, kind = vim.lsp.protocol.CompletionItemKind.Function }
      end
    end
    vim.schedule(function()
      cb(items)
    end)
  end)
end

local TAG_MAX = 200

local function tag_items_from_text(out, pattern)
  local items = {}
  for line in (out or ""):gmatch("[^\r\n]+") do
    local file, lno = line:match("^(.-):(%d+):")
    if file then
      items[#items + 1] = { name = pattern, filename = file, cmd = tostring(lno) }
      if #items >= TAG_MAX then
        break
      end
    end
  end
  return items
end

-- 索引未完成/查不到时的 fallback:只找顶层定义/声明行(比扫所有调用点干净)
function M.grep_defs(pattern, ws)
  local rg = rg_exe()
  local roots = {}
  for _, p in ipairs(search_roots(ws)) do
    roots[#roots + 1] = (p == ".") and ws.root or (ws.root .. "/" .. p)
  end
  local pat = "^[[:alpha:]_].*\\b" .. regex_escape(pattern) .. "\\s*\\("
  local cmd
  if rg then
    cmd = { rg, "-n", "--no-heading", "--color", "never", "-g", "*.c", "-g", "*.h", "-g", "*.S", "-g", "*.cc", "-g", "*.cpp", "--", pat }
    vim.list_extend(cmd, roots)
  else
    cmd = {
      "grep", "-rnI", "-E", "--color=never",
      "--exclude-dir=.git", "--exclude-dir=.repo", "--exclude-dir=out",
      "--exclude-dir=prebuilts", "--exclude-dir=build",
      "--include=*.c", "--include=*.h", "--include=*.S",
      "--include=*.cc", "--include=*.cpp", "-e", pat,
    }
    vim.list_extend(cmd, roots)
  end
  local res = vim.system(cmd, { cwd = ws.root, text = true }):wait()
  return tag_items_from_text(res.stdout or "", pattern)
end

function M.tagfunc(pattern, _flags, _info)
  local ws = vim.b.aivim_ws
  if not ws then
    ws = M.workspace(0)
  end
  pattern = (pattern or ""):gsub("^%^", ""):gsub("%$$", "")
  if not ws or pattern == "" then
    return {}
  end

  if not ws.indexed then
    local fresh = M.refresh(0)
    if fresh and fresh.indexed then
      ws = fresh
    end
  end

  if not ws.indexed then
    local notified = vim.g.aivim_building_notified or {}
    if not notified[ws.root] then
      notified[ws.root] = true
      vim.g.aivim_building_notified = notified
      notify("索引建立中: " .. ws.root .. "; 先用 grep 兜底, 完成后 Ctrl+\\ 自动走 GLOBAL", WARN)
    end
    return M.grep_defs(pattern, ws)
  end

  local res = vim.system({ "global", "-a", "--result=grep", "-d", pattern }, {
    cwd = ws.root,
    env = ws_env(ws),
    text = true,
  }):wait()
  if res.code ~= 0 then
    return M.grep_defs(pattern, ws)
  end
  local items = tag_items_from_text(res.stdout, pattern)
  if #items == 0 then
    return M.grep_defs(pattern, ws)
  end
  return items
end

-- <C-\> 的智能行为: 1 个结果直接跳,多个才列表
function M.definition()
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    notify("光标下没有符号", WARN)
    return
  end
  local items = M.tagfunc(word)
  if not items or #items == 0 then
    notify("未找到定义: " .. word, WARN)
    return
  end
  local arg = vim.fn.escape(word, " \t|")
  if #items == 1 then
    local ok, err = pcall(vim.cmd, "tag " .. arg)
    if not ok then
      notify("跳转失败: " .. tostring(err), WARN)
    end
  else
    local ok, err = pcall(vim.cmd, "tselect " .. arg)
    if not ok then
      notify("定义列表打开失败: " .. tostring(err), WARN)
    end
  end
end

_G.aivim_tagfunc = function(pattern, flags, info)
  return M.tagfunc(pattern, flags, info)
end

-- ── 命令 ─────────────────────────────────────────────────────────────
function M.status()
  local info = M.workspace(0)
  if not info then
    notify("无法识别工作区", WARN)
    return
  end
  local res = vim.system({
    python, script, "index", "status", info.root, "--json",
    "--profile", info.profile, "--arch", info.arch,
  }, { text = true }):wait()
  if res.code ~= 0 then
    notify("索引状态读取失败: " .. ((res.stderr or "") .. (res.stdout or "")):sub(1, 300), WARN)
    return
  end
  local ok, data = pcall(vim.json.decode, res.stdout or "")
  if not ok or type(data) ~= "table" then
    notify(res.stdout or "无法解析状态", WARN)
    return
  end
  local meta = data.meta or {}
  local lines = {
    "root: " .. tostring(data.root),
    "profile: " .. tostring(data.profile) .. "  arch: " .. tostring(data.arch),
    "indexed: " .. tostring(data.indexed),
    "files: " .. tostring(meta.files or "?"),
    "size: " .. string.format("%.1f MB", (data.bytes or 0) / 1048576),
    "built: " .. (meta.built_at and os.date("%Y-%m-%d %H:%M:%S", math.floor(meta.built_at)) or "?"),
    "cache: " .. tostring(data.cache),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.cancel()
  local info = M.workspace(0)
  local root = info and info.root
  if root and jobs[root] then
    pcall(function()
      jobs[root]:kill("sigterm")
    end)
    jobs[root] = nil
    building[root] = nil
    if vim.g.aivim_indexing then
      vim.g.aivim_indexing[root] = nil
    end
    notify("已取消索引任务: " .. root)
  else
    notify("当前没有正在运行的索引任务")
  end
end

vim.api.nvim_create_user_command("IndexBuild", function(opts)
  local target = opts.args ~= "" and opts.args or nil
  local info
  if target then
    info = workspace.detect(target)
  else
    info = M.workspace(0)
  end
  if not info then
    notify("无法识别工作区", WARN)
    return
  end
  M.build(info.root, info.profile, info.arch, { force = true })
end, { nargs = "?", complete = "dir", force = true, desc = "建/重建 gtags 索引(自动识别工作区)" })

vim.api.nvim_create_user_command("IndexUpdate", function()
  local info = M.workspace(0)
  if not info then
    notify("无法识别工作区", WARN)
    return
  end
  if not info.indexed then
    M.build(info.root, info.profile, info.arch)
  else
    M.update(0)
  end
end, { force = true, desc = "立即增量更新当前工作区索引" })

vim.api.nvim_create_user_command("IndexStatus", function()
  M.status()
end, { force = true, desc = "查看当前工作区索引状态" })

vim.api.nvim_create_user_command("IndexCancel", function()
  M.cancel()
end, { force = true, desc = "取消当前索引任务" })

vim.api.nvim_create_user_command("IndexClean", function(opts)
  local info = M.workspace(0)
  local args = { python, script, "index", "clean", "--json" }
  if opts.args == "--all" then
    if vim.fn.confirm("清理所有 gtags 索引缓存?", "&Yes\n&No", 2) ~= 1 then
      return
    end
    table.insert(args, "--all")
  elseif info then
    vim.list_extend(args, { info.root, "--profile", info.profile, "--arch", info.arch })
  else
    notify("无法识别工作区;清理全部请用 :IndexClean --all", WARN)
    return
  end
  local res = vim.system(args, { text = true }):wait()
  if res.code == 0 then
    workspace.invalidate()
    notify("索引缓存已清理")
  else
    notify("清理失败: " .. ((res.stderr or "") .. (res.stdout or "")):sub(1, 300), WARN)
  end
end, { nargs = "?", complete = function() return { "--all" } end, force = true, desc = "清理索引缓存" })

-- ── autocmds ─────────────────────────────────────────────────────────
local grp = vim.api.nvim_create_augroup("AivimIndex", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = grp,
  callback = function(ev)
    M.ensure(ev.buf)
  end,
  desc = "aivim: 新工作区自动检测/后台建索引",
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = grp,
  callback = function(ev)
    M.update(ev.buf)
  end,
  desc = "aivim: 保存后后台增量索引",
})
-- FileType 晚于 BufReadPost;再补一次,防止某些打开路径漏掉 tagfunc
vim.api.nvim_create_autocmd("FileType", {
  group = grp,
  pattern = { "c", "cpp", "objc", "objcpp", "asm" },
  callback = function(ev)
    M.ensure(ev.buf)
  end,
  desc = "aivim: FileType 后补 tagfunc/工作区",
})
-- LSP attach 后可能把 tagfunc 覆盖成 vim.lsp.tagfunc;这里强制抢回来
vim.api.nvim_create_autocmd("LspAttach", {
  group = grp,
  callback = function(ev)
    if is_code_buffer(ev.buf) then
      vim.bo[ev.buf].tagfunc = "v:lua.aivim_tagfunc"
    end
  end,
  desc = "aivim: LSP 后恢复 gtags tagfunc",
})

vim.api.nvim_create_user_command("AivimDiag", function()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local ws = M.workspace(buf)
  local t = M.tagfunc("balance_pgdat")
  local src = debug.getinfo(M.tagfunc, "S")
  local lines = {
    "version: " .. tostring(M.VERSION),
    "module: " .. tostring(src and src.source),
    "config: " .. vim.fn.stdpath("config"),
    "buf: " .. name,
    "tagfunc: " .. tostring(vim.bo[buf].tagfunc),
    "ws: " .. tostring(ws and (ws.root .. " profile=" .. tostring(ws.profile) .. " indexed=" .. tostring(ws.indexed))),
    "tagfunc(balance_pgdat): " .. tostring(t and #t or "INVALID_NIL"),
    "aivim_tagfunc: " .. type(_G.aivim_tagfunc),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { force = true, desc = "aivim 诊断:当前加载的模块/工作区/tagfunc" })

vim.api.nvim_create_user_command("AivimReload", function()
  package.loaded["aivim.workspace"] = nil
  package.loaded["aivim.index"] = nil
  package.loaded["aivim.blink"] = nil
  require("aivim.index")
  package.loaded["config.keymaps"] = nil
  pcall(require, "config.keymaps")
  package.loaded["config.autocmds"] = nil
  pcall(require, "config.autocmds")
  -- 重载 bufferline,让顶部栏样式立即生效
  local okc, cfg = pcall(require, "lazy.core.config")
  local okl, loader = pcall(require, "lazy.core.loader")
  if okc and okl and cfg.plugins["bufferline.nvim"] then
    pcall(loader.reload, cfg.plugins["bufferline.nvim"])
  end
  notify("aivim 已重载: " .. M.VERSION)
end, { force = true, desc = "热重载 aivim 索引模块" })

return M
