-- 诊断脚本: nvim -l scripts/check.lua
local function out(...)
  io.write(table.concat({ ... }, " ") .. "\n")
end

-- 模拟真实启动时的 VeryLazy
pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "VeryLazy" })

out("leader=" .. tostring(vim.g.mapleader), "localleader=" .. tostring(vim.g.maplocalleader))
out("ts=" .. tostring(vim.opt.tabstop:get()), "sw=" .. tostring(vim.opt.shiftwidth:get()),
  "et=" .. tostring(vim.opt.expandtab:get()), "sts=" .. tostring(vim.opt.softtabstop:get()),
  "mouse=" .. tostring(vim.opt.mouse:get()))

local missing = 0
local keys = {
  "<C-\\>", ";w", ";wq", ";W", ";Q", ";1", ";9", ";12", "[b", "]b",
  "wn", ";wl", ";wr", ";wj", ";wk", ";m", ";/", ";.", ";sp",
  ";n", ";f", ";a", ";cc", ";cu", ";cn", ";cA",
  "<F8>", "<F9>", ";tb", ";td", ";bm", "<C-k>", "<C-j>",
  ";;w", ";;W", ";;f", ";;F",
  ";gg", ";gr", ";gs", ";gt", ";gf", ";gi", ";gc", ";gd", ";ga", ";gz", ";ge", ";gh",
  ";jd", ";jc",
}
for _, k in ipairs(keys) do
  local m = vim.fn.maparg(k, "n")
  if m == "" then
    missing = missing + 1
  end
  out(string.format("%-10s %s", k, m == "" and "MISSING" or "OK"))
end

if vim.o.mouse ~= "a" then
  missing = missing + 1
  out("mouse=" .. tostring(vim.o.mouse) .. " (expected a)")
end
if vim.opt.tabstop:get() ~= 8 or vim.opt.shiftwidth:get() ~= 8
  or vim.opt.expandtab:get() ~= false or vim.opt.softtabstop:get() ~= -1 then
  missing = missing + 1
  out("indent options mismatch")
end

for _, c in ipairs({ "IndexBuild", "IndexUpdate", "IndexStatus", "IndexCancel", "IndexClean" }) do
  local e = vim.fn.exists(":" .. c)
  if e ~= 2 then
    missing = missing + 1
  end
  out(c .. "=" .. tostring(e))
end

local ok, err = pcall(require, "aivim.index")
out("aivim.index load=" .. tostring(ok) .. " " .. tostring(err))
local ok2, err2 = pcall(require, "aivim.blink")
out("aivim.blink load=" .. tostring(ok2) .. " " .. tostring(err2))

out("missing=" .. tostring(missing))
if missing > 0 then
  os.exit(1)
end
