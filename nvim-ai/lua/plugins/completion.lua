-- 补全:blink.cmp
-- 本地源 = gtags 符号 + buffer + path(+ 片段);不接 LSP,不接云端。
return {
  {
    "saghen/blink.cmp",
    event = "InsertEnter",
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.default = { "global", "snippets", "buffer", "path" }
      opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
        global = {
          name = "global",
          module = "aivim.blink",
          score_offset = 0,
        },
      })
      opts.keymap = vim.tbl_deep_extend("force", opts.keymap or {}, {
        preset = "enter",
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<Tab>"] = { "snippet_forward", "select_next", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
        ["<C-j>"] = { "snippet_forward", "fallback" },
        ["<C-k>"] = { "snippet_backward", "fallback" },
      })
      return opts
    end,
  },
}
