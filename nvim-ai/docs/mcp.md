# aicx MCP server

`aicx mcp` 是一个本地 **stdio MCP server**，把 gtags 索引和 ripgrep/grep 暴露给任意 MCP 客户端（Claude Code、Codex 等）。

## 工具

| 工具 | 参数 | 说明 |
|---|---|---|
| `workspace_info` | `path?` | 当前工作区 root/profile/arch/索引状态 |
| `find_definition` | `symbol`, `path?` | `global -d`，返回定义位置 |
| `find_references` | `symbol`, `path?` | `global -r`，返回所有引用 |
| `find_symbol` | `pattern`, `path?` | `global -s` |
| `search_text` | `pattern`, `glob?`, `path?` | ripgrep；没有 rg 时用 grep |
| `list_files` | `glob?`, `path?` | `rg --files`；没有 rg 时用 `find` |
| `read_file` | `file`, `start_line?`, `end_line?`, `path?` | 读取工作区内文件，默认最多 400 行 |
| `git_diff` | `file?`, `staged?`, `path?` | `git diff` |

`path` 可以是文件或目录；server 用它定位工作区。索引缺失时，`find_*` 会提示先运行 `aicx index build <root>`；文本工具不依赖索引。

## 已注册

```sh
claude mcp list
# aivim-gtags: python3 .../tools/aicx.py mcp - ✔ Connected

codex mcp list
# aivim-gtags ... enabled
```

配置文件位置：

- Claude Code：`~/.claude.json`
- Codex：`~/.codex/config.toml` 的 `[mcp_servers.aivim-gtags]`

## 手动配置

```sh
# 打印 Claude/Codex 的命令和 JSON/TOML 片段
python3 ~/.config/nvim-ai/tools/aicx.py mcp-config

# Claude Code
claude mcp add --scope user aivim-gtags python3 /abs/path/tools/aicx.py mcp

# Codex
codex mcp add aivim-gtags -- python3 /abs/path/tools/aicx.py mcp
```

Codex 默认会要求 MCP 工具审批。本 server 的工具全是只读，可在
`~/.codex/config.toml` 的 `[mcp_servers.aivim-gtags]` 下设置：

```toml
default_tools_approval_mode = "approve"
```

## 安全

- 只读：不写文件、不执行 shell 命令。
- `read_file` / `git_diff` 限制在工作区内。
- 输出截断（默认 200 行 / 60KB）。
- API key / 登录信息不经过本 server；它只调用本机 `global` / `grep` / `git`。

## 手工测试

```sh
python3 - <<'PY' | python3 ~/.config/nvim-ai/tools/aicx.py mcp
import json
msgs = [
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}},
 {"jsonrpc":"2.0","id":2,"method":"tools/list"},
 {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find_definition","arguments":{"symbol":"target_symbol","path":"/path/to/project/src/foo.c"}}},
]
for m in msgs:
    print(json.dumps(m))
PY
```

## 端到端验证（Claude Code）

```sh
cd /path/to/project
claude -p "Use the aivim-gtags MCP server's find_definition tool with symbol 'target_symbol' and path '/path/to/project/src/foo.c'. Print the tool result verbatim." \
  --allowedTools "mcp__aivim-gtags__find_definition"
```

预期返回类似：

```
src/foo.c:42: int target_symbol(...)
```
