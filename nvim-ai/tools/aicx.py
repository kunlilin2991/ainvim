#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
aicx: generic GNU GLOBAL indexer + gtags/rg MCP server for nvim-ai.

设计目标:
  * 不硬编码任何工程路径;按目录自动识别 kernel / qcom-kernel / android-platform / generic-c
  * 索引只写 ~/.cache/nvim-ai/index/<key>,不污染源码树
  * 建库/增量用 gtags;查询用 global;文本/兜底用 rg
  * 同一套逻辑同时服务 Neovim 和 MCP(Claude Code / Codex 等)

只用 Python 3.8 标准库。
"""

import argparse
import fnmatch
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

VERSION = 1
CACHE_ROOT = Path(os.environ.get("AIVIM_CACHE", str(Path.home() / ".cache" / "nvim-ai")))
INDEX_ROOT = CACHE_ROOT / "index"
ORPHAN_ROOT = CACHE_ROOT / "orphans"

KERNEL_EXTS = {".c", ".h", ".S", ".s"}
CPP_EXTS = {".c", ".h", ".S", ".s", ".cc", ".cpp", ".cxx", ".hpp", ".hh", ".hxx", ".C", ".H", ".ipp"}

SKIP_DIRS = {
    ".git", ".repo", ".cache", ".idea", ".vscode", ".clangd", "CMakeFiles",
    "node_modules", "__pycache__", "out", "output", "prebuilts", "prebuilt",
    "prebuild", "generated", "build", ".deps", ".tmp",
}
KERNEL_SKIP_DIRS = {"Documentation", "tools", "samples", "selftests", "scripts", "rust", "build"}
ANDROID_SKIP_DIRS = {
    "cts", "test", "tests", "sdk", "development", "toolchain", "proprietary",
    "prebuilts", "prebuilt", "out", "build",
}
HONOR_SKIP_DIRS = {"prebuilt", "prebuild", "prebuilts", "itrustee", "trustedcore", "test", "tests", "out"}

KERNEL_MODULE_DIRS = {
    "audio-kernel", "display-drivers", "camera-kernel", "bt-kernel", "data-kernel",
    "graphics-kernel", "video-driver", "wlan", "dsp-kernel", "eva-kernel",
    "securemsm-kernel", "synx-kernel", "datarmnet", "datarmnet-ext",
    "audio-devicetree", "camera-devicetree", "display-devicetree",
    "bt-devicetree", "data-devicetree",
}


def eprint(*a):
    print(*a, file=sys.stderr)


def posix_rel(path, root):
    return os.path.relpath(str(path), str(root)).replace(os.sep, "/")


def read_json(path, default=None):
    try:
        with open(str(path), "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def write_json(path, data):
    tmp = str(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp, str(path))


def which(name):
    return shutil.which(name)


# ───────────────────────────── workspace detection ─────────────────────────────

def is_kernel_root(d):
    d = Path(d)
    if not (d / "arch").is_dir():
        return False
    if not (d / "Kbuild").is_file():
        return False
    mk = d / "Makefile"
    if not mk.is_file():
        return False
    try:
        head = "\n".join(mk.read_text(errors="ignore").splitlines()[:8])
    except Exception:
        return False
    return ("VERSION" in head and "PATCHLEVEL" in head)


def detect_arch(kernel_dir, requested=None):
    if requested and requested != "auto":
        return requested
    env_arch = os.environ.get("ARCH")
    if env_arch:
        return env_arch
    d = Path(kernel_dir)
    for a in ("arm64", "x86", "arm", "riscv", "loongarch", "mips", "powerpc"):
        if (d / "arch" / a).is_dir():
            return a
    return "all"


def classify_qcom(root, path):
    root = Path(root)
    path = Path(path)
    try:
        rel = path.resolve().relative_to(root.resolve())
    except Exception:
        try:
            rel = path.relative_to(root)
        except Exception:
            return "android-platform"
    parts = rel.parts
    if not parts:
        return "android-platform"
    if parts[0] == "kernel_platform":
        return "qcom-kernel"
    if parts[0] == "vendor" and len(parts) >= 4:
        if parts[1] == "qcom" and parts[2] == "opensource":
            name = parts[3]
            if name in KERNEL_MODULE_DIRS or name.endswith("-kernel"):
                return "qcom-kernel"
        if parts[1] == "honor" and any(p in ("kernel", "kernel_modules") for p in parts):
            return "qcom-kernel"
    return "android-platform"


def cache_key(root, profile, arch):
    raw = "%s|%s|%s" % (os.path.realpath(str(root)), profile, arch)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def cache_dir(root, profile, arch):
    return INDEX_ROOT / cache_key(root, profile, arch)


def db_files(cache):
    return [Path(cache) / "GTAGS", Path(cache) / "GRTAGS", Path(cache) / "GPATH"]


def db_ok(cache):
    for f in db_files(cache):
        try:
            if not f.is_file() or f.stat().st_size <= 0:
                return False
        except Exception:
            return False
    return True


def db_bytes(cache):
    total = 0
    for f in db_files(cache):
        try:
            total += f.stat().st_size
        except Exception:
            pass
    return total


def make_info(root, profile, arch, requested_root=False):
    root = Path(root).resolve()
    arch = arch or "all"
    cache = cache_dir(root, profile, arch)
    meta = read_json(cache / "meta.json")
    indexed = db_ok(cache) and bool(meta)
    if meta and (meta.get("profile") != profile or meta.get("arch") != arch):
        indexed = False
    stale = False
    if meta and meta.get("built_at"):
        stale = (time.time() - float(meta["built_at"])) > 7 * 86400
    return {
        "root": str(root),
        "profile": profile,
        "arch": arch,
        "cache": str(cache),
        "indexed": bool(indexed),
        "stale": bool(stale),
        "meta": meta,
        "bytes": db_bytes(cache) if indexed else 0,
        "requested_root": bool(requested_root),
    }


def detect_workspace(path, profile=None, arch=None, root=None):
    p = Path(path).expanduser()
    try:
        p = p.resolve()
    except Exception:
        pass
    if root:
        r = Path(root).expanduser().resolve()
        prof = profile or ("qcom-kernel" if (r / "kernel_platform" / "common").is_dir() else "generic-c")
        a = arch or (detect_arch(r / "kernel_platform" / "common") if prof == "qcom-kernel" else "all")
        return make_info(r, prof, a, requested_root=True)

    start = p if p.is_dir() else p.parent

    # Pass 1: platform/repo root 优先。
    # 内核树自己也可能有 .repo，所以 .repo 要先判断是不是 kernel root。
    cur = start
    while True:
        if (cur / "kernel_platform" / "common").is_dir() and (cur / "vendor").is_dir():
            prof = profile or classify_qcom(cur, p)
            a = arch or (detect_arch(cur / "kernel_platform" / "common") if prof == "qcom-kernel" else "all")
            return make_info(cur, prof, a)
        if (cur / ".repo").is_dir():
            if is_kernel_root(cur):
                return make_info(cur, profile or "kernel", arch or detect_arch(cur))
            prof = profile or "android-platform"
            if (cur / "kernel_platform" / "common").is_dir() and classify_qcom(cur, p) == "qcom-kernel":
                prof = "qcom-kernel"
            a = arch or (detect_arch(cur / "kernel_platform" / "common") if prof == "qcom-kernel" else "all")
            return make_info(cur, prof, a)
        if cur.parent == cur:
            break
        cur = cur.parent

    # Pass 2: 普通 kernel / Android / 通用 C 工程。
    git_root = None
    cur = start
    while True:
        if is_kernel_root(cur):
            return make_info(cur, profile or "kernel", arch or detect_arch(cur))
        if (cur / "build" / "soong").is_dir() or (cur / "Android.bp").is_file():
            return make_info(cur, profile or "android-platform", arch or "all")
        if (cur / ".git").exists():
            if git_root is None:
                git_root = cur
            if any((cur / x).exists() for x in ("Makefile", "CMakeLists.txt", "compile_commands.json", "meson.build")):
                return make_info(cur, profile or "generic-c", arch or "all")
        if cur.parent == cur:
            break
        cur = cur.parent

    base = git_root or start
    return make_info(base, profile or "generic-c", arch or "all")


def project_config(root):
    cfg = read_json(Path(root) / ".aivim-index.json", {}) or {}
    if not isinstance(cfg, dict):
        cfg = {}
    return cfg


# ───────────────────────────── file selection ─────────────────────────────

def skip_dir(name, profile):
    if name in SKIP_DIRS:
        return True
    if name.startswith("."):
        return True
    if profile in ("kernel", "qcom-kernel") and name in KERNEL_SKIP_DIRS:
        return True
    if profile == "android-platform" and name in ANDROID_SKIP_DIRS:
        return True
    return False


def file_ok(name, exts):
    ext = os.path.splitext(name)[1]
    if ext not in exts:
        return False
    if name.endswith((".mod.c", ".mod.h", ".cmd", ".o", ".a", ".so", ".pyc")):
        return False
    return True


def walk_files(base, root, profile, arch, exts, arch_base=None, prune_extra=None):
    base = Path(base)
    if not base.exists():
        return
    for dirpath, dirnames, filenames in os.walk(str(base), followlinks=False):
        rel_base = os.path.relpath(dirpath, str(base))
        parts_base = [] if rel_base == "." else rel_base.split(os.sep)

        if arch_base is not None and profile in ("kernel", "qcom-kernel") and arch != "all":
            if parts_base == ["arch"]:
                dirnames[:] = [d for d in dirnames if d == arch]
            elif parts_base and parts_base[0] == "arch":
                if len(parts_base) < 2 or parts_base[1] != arch:
                    dirnames[:] = []
                    continue

        dirnames[:] = [d for d in dirnames if not skip_dir(d, profile)]
        if prune_extra:
            dirnames[:] = [d for d in dirnames if d not in prune_extra]

        for fn in filenames:
            if fn.startswith("."):
                continue
            if not file_ok(fn, exts):
                continue
            full = os.path.join(dirpath, fn)
            if not os.path.isfile(full):
                continue
            yield posix_rel(full, root)


def find_named_dirs(base, names, prune):
    base = Path(base)
    if not base.exists():
        return
    for dirpath, dirnames, _ in os.walk(str(base), followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in prune and not d.startswith(".")]
        name = os.path.basename(dirpath)
        if name in names and Path(dirpath) != base:
            yield Path(dirpath)


def iter_files(root, profile, arch):
    root = Path(root)
    cfg = project_config(root)
    profile = cfg.get("profile", profile)
    arch = cfg.get("arch", arch)
    includes = cfg.get("include") or []
    excludes = cfg.get("exclude") or []
    exts = set(cfg.get("extensions") or (KERNEL_EXTS if profile in ("kernel", "qcom-kernel") else CPP_EXTS))

    files = set()

    def add_walk(base, e=exts, arch_base=None, prune=None):
        for f in walk_files(base, root, profile, arch, e, arch_base=arch_base, prune_extra=prune):
            files.add(f)

    if includes:
        for inc in includes:
            p = (root / inc).resolve() if not Path(inc).is_absolute() else Path(inc)
            if p.is_file():
                if file_ok(p.name, exts):
                    files.add(posix_rel(p, root))
            elif p.is_dir():
                add_walk(p)
    elif profile == "qcom-kernel":
        common = root / "kernel_platform" / "common"
        add_walk(common, arch_base=common)
        add_walk(root / "kernel_platform" / "qcom")
        opensource = root / "vendor" / "qcom" / "opensource"
        if opensource.is_dir():
            for d in sorted(opensource.iterdir()):
                if d.is_dir() and (d.name in KERNEL_MODULE_DIRS or d.name.endswith("-kernel")):
                    add_walk(d)
        honor = root / "vendor" / "honor" / "chipset"
        if honor.is_dir():
            for d in find_named_dirs(honor, {"kernel", "kernel_modules"}, HONOR_SKIP_DIRS):
                add_walk(d, prune=HONOR_SKIP_DIRS)
    elif profile == "kernel":
        add_walk(root, arch_base=root)
    elif profile == "android-platform":
        for sub in ("system", "hardware", "vendor", "frameworks/native"):
            p = root / sub
            if p.is_dir():
                add_walk(p)
    else:
        add_walk(root)

    # excludes: glob against relative path
    if excludes:
        files = {
            f for f in files
            if not any(fnmatch.fnmatch(f, pat) or fnmatch.fnmatch("/" + f, pat) for pat in excludes)
        }

    return sorted(files)


# ───────────────────────────── index build/update ─────────────────────────────

def write_list(cache, files):
    Path(cache).mkdir(parents=True, exist_ok=True)
    path = Path(cache) / "files.list"
    tmp = Path(str(path) + ".tmp")
    with open(str(tmp), "w", encoding="utf-8") as f:
        for x in files:
            f.write(x + "\n")
    os.replace(str(tmp), str(path))
    return path


def move_orphans(root, key):
    root = Path(root)
    moved = []
    for name in ("GTAGS", "GRTAGS", "GPATH"):
        src = root / name
        if src.exists() and src.is_file():
            dst_dir = ORPHAN_ROOT / ("%s-%d" % (key, int(time.time())))
            dst_dir.mkdir(parents=True, exist_ok=True)
            dst = dst_dir / name
            try:
                shutil.move(str(src), str(dst))
                moved.append(str(dst))
            except Exception as e:
                eprint("warning: cannot move stray %s: %s" % (src, e))
    if moved:
        eprint("moved stray GTAGS files to: %s" % moved[0].rsplit("/", 1)[0])
    return moved


def run_gtags_full(root, cache, list_path):
    tmp = Path(str(cache) + ".tmp-%d" % os.getpid())
    if tmp.exists():
        shutil.rmtree(str(tmp), ignore_errors=True)
    tmp.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GTAGSROOT"] = str(root)
    env["GTAGSDBPATH"] = str(tmp)
    env["LC_ALL"] = "C"
    cmd = [which("gtags") or "gtags", "-f", str(list_path), "-o", str(tmp)]
    t0 = time.time()
    p = subprocess.run(cmd, cwd=str(root), env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    secs = time.time() - t0
    if p.returncode != 0:
        shutil.rmtree(str(tmp), ignore_errors=True)
        raise RuntimeError("gtags failed (%d): %s" % (p.returncode, (p.stderr or p.stdout)[-2000:]))
    if not db_ok(tmp):
        shutil.rmtree(str(tmp), ignore_errors=True)
        raise RuntimeError("gtags produced empty/incomplete DB: %s" % (p.stderr or "")[-1000:])

    old = Path(str(cache) + ".old")
    if cache.exists():
        if old.exists():
            shutil.rmtree(str(old), ignore_errors=True)
        os.replace(str(cache), str(old))
    os.replace(str(tmp), str(cache))
    if old.exists():
        shutil.rmtree(str(old), ignore_errors=True)
    return secs, p.stderr


def cmd_index_build(args):
    info = detect_workspace(args.path, args.profile, args.arch, args.root)
    root = Path(info["root"])
    profile = info["profile"]
    arch = info["arch"]
    if info["indexed"] and not args.force:
        out = dict(info)
        out["ok"] = True
        out["skipped"] = True
        print(json.dumps(out, ensure_ascii=False))
        return 0

    t0 = time.time()
    files = iter_files(root, profile, arch)
    if not files:
        msg = "no source files found (root=%s profile=%s arch=%s)" % (root, profile, arch)
        eprint(msg)
        print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
        return 1

    cache = cache_dir(root, profile, arch)
    cache.parent.mkdir(parents=True, exist_ok=True)
    key = cache_key(root, profile, arch)
    move_orphans(root, key)
    list_path = write_list(cache, files)
    try:
        secs, stderr = run_gtags_full(root, cache, list_path)
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 1

    meta = {
        "version": VERSION,
        "root": str(root),
        "profile": profile,
        "arch": arch,
        "files": len(files),
        "built_at": time.time(),
        "build_seconds": round(secs, 2),
        "list_sha": hashlib.sha1("\n".join(files).encode("utf-8")).hexdigest(),
        "gtags_stderr_tail": (stderr or "")[-2000:],
    }
    write_json(cache / "meta.json", meta)
    out = {
        "ok": True,
        "root": str(root),
        "profile": profile,
        "arch": arch,
        "cache": str(cache),
        "files": len(files),
        "seconds": round(time.time() - t0, 2),
        "bytes": db_bytes(cache),
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


def cmd_index_update(args):
    info = detect_workspace(args.path, args.profile, args.arch, args.root)
    root = Path(info["root"])
    profile = info["profile"]
    arch = info["arch"]
    cache = cache_dir(root, profile, arch)
    if not (db_ok(cache) and (cache / "meta.json").exists()):
        return cmd_index_build(argparse.Namespace(
            path=str(root), profile=profile, arch=arch, root=None, force=False))

    cache.mkdir(parents=True, exist_ok=True)
    lock_path = cache / ".lock"
    lock_fd = open(str(lock_path), "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_fd.close()
        print(json.dumps({"ok": True, "busy": True, "root": str(root)}, ensure_ascii=False))
        return 0

    try:
        t0 = time.time()
        files = iter_files(root, profile, arch)
        if not files:
            print(json.dumps({"ok": False, "error": "no source files"}, ensure_ascii=False))
            return 1
        list_path = write_list(cache, files)

        env = os.environ.copy()
        env["GTAGSROOT"] = str(root)
        env["GTAGSDBPATH"] = str(cache)
        env["LC_ALL"] = "C"
        cmd = [which("gtags") or "gtags", "-i", "-f", str(list_path), "-o", str(cache)]
        p = subprocess.run(cmd, cwd=str(root), env=env, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode != 0:
            print(json.dumps({
                "ok": False,
                "error": "gtags -i failed (%d): %s" % (p.returncode, (p.stderr or p.stdout)[-2000:]),
            }, ensure_ascii=False))
            return 1

        meta = read_json(cache / "meta.json", {}) or {}
        meta.update({
            "version": VERSION,
            "root": str(root),
            "profile": profile,
            "arch": arch,
            "files": len(files),
            "updated_at": time.time(),
            "update_seconds": round(time.time() - t0, 2),
            "list_sha": hashlib.sha1("\n".join(files).encode("utf-8")).hexdigest(),
        })
        write_json(cache / "meta.json", meta)
        print(json.dumps({
            "ok": True,
            "busy": False,
            "root": str(root),
            "files": len(files),
            "seconds": round(time.time() - t0, 2),
            "bytes": db_bytes(cache),
        }, ensure_ascii=False))
        return 0
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except Exception:
            pass
        lock_fd.close()


def cmd_index_status(args):
    info = detect_workspace(args.path, args.profile, args.arch, args.root)
    out = dict(info)
    out["ok"] = True
    if args.json:
        print(json.dumps(out, ensure_ascii=False))
    else:
        m = info.get("meta") or {}
        print("root:    %s" % info["root"])
        print("profile: %s  arch: %s" % (info["profile"], info["arch"]))
        print("cache:   %s" % info["cache"])
        print("indexed: %s  stale: %s" % (info["indexed"], info.get("stale")))
        print("files:   %s" % m.get("files", "?"))
        print("size:    %.1f MB" % (info.get("bytes", 0) / 1048576.0))
        if m.get("built_at"):
            print("built:   %s" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(m["built_at"]))))
        if m.get("updated_at"):
            print("updated: %s" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(float(m["updated_at"]))))
    return 0


def cmd_index_clean(args):
    removed = []
    if args.all:
        if INDEX_ROOT.exists():
            for d in INDEX_ROOT.iterdir():
                if d.is_dir():
                    shutil.rmtree(str(d), ignore_errors=True)
                    removed.append(str(d))
    else:
        info = detect_workspace(args.path, args.profile, args.arch, getattr(args, "root", None))
        d = Path(info["cache"])
        if d.exists():
            shutil.rmtree(str(d), ignore_errors=True)
            removed.append(str(d))
    out = {"ok": True, "removed": removed}
    print(json.dumps(out, ensure_ascii=False))
    return 0


# ───────────────────────────── queries ─────────────────────────────

def run_global(info, args):
    env = os.environ.copy()
    env["GTAGSROOT"] = info["root"]
    env["GTAGSDBPATH"] = info["cache"]
    env["LC_ALL"] = "C"
    return subprocess.run([which("global") or "global"] + args, cwd=info["root"], env=env,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def query_flag(kind):
    return {
        "def": "-d", "definition": "-d",
        "refs": "-r", "references": "-r",
        "symbol": "-s", "text": "-g",
        "file": "-P",
    }.get(kind)


def cmd_query(args):
    info = detect_workspace(args.path or os.getcwd(), None, None, None)
    if not info["indexed"]:
        print("no index for %s; run: aicx index build %s" % (info["root"], info["root"]))
        return 1
    flag = query_flag(args.kind)
    if not flag:
        print("unknown query kind: %s" % args.kind)
        return 2
    argv = ["-a"]
    if flag != "-P":
        argv.append("--result=grep")
    argv.extend([flag, args.symbol])
    p = run_global(info, argv)
    if p.returncode != 0 and not p.stdout:
        print(p.stderr or "global failed", file=sys.stderr)
        return 1
    print(p.stdout, end="")
    return 0


# ───────────────────────────── MCP server ─────────────────────────────

def truncate(text, limit=200, max_bytes=60000):
    lines = text.splitlines()
    if len(lines) > limit:
        lines = lines[:limit] + ["... (%d more lines)" % (len(text.splitlines()) - limit)]
    out = "\n".join(lines)
    if len(out.encode("utf-8")) > max_bytes:
        out = out.encode("utf-8")[:max_bytes].decode("utf-8", "ignore") + "\n... (truncated)"
    return out


def rel_lines(out, root):
    lines = []
    for line in out.splitlines():
        # global -a --result=grep => /abs/path:line:text
        m = re.match(r"^(/[^:]+):(\d+):(.*)$", line)
        if m:
            try:
                rp = os.path.relpath(m.group(1), root)
            except Exception:
                rp = m.group(1)
            lines.append("%s:%s:%s" % (rp, m.group(2), m.group(3)))
        else:
            lines.append(line)
    return "\n".join(lines)


class McpError(Exception):
    pass


def rel_file_lines(out, root):
    lines = []
    for line in out.splitlines():
        p = line
        if os.path.isabs(p):
            try:
                p = os.path.relpath(p, root)
            except Exception:
                pass
        lines.append(p)
    return "\n".join(lines)


def info_for_mcp(path=None):
    p = path or os.getcwd()
    info = detect_workspace(p, None, None, None)
    if not info["indexed"]:
        raise McpError(
            "no gtags index for workspace %s (profile=%s). Run: aicx index build %s"
            % (info["root"], info["profile"], info["root"])
        )
    return info


def mcp_find(info, flag, symbol):
    argv = ["-a", "--result=grep", flag, symbol]
    p = run_global(info, argv)
    if p.returncode != 0 and not p.stdout:
        raise McpError((p.stderr or "global failed").strip())
    out = rel_lines(p.stdout or "", info["root"])
    if not out.strip():
        return "no results for '%s' (%s) in %s" % (symbol, flag, info["root"])
    return truncate(out)


def tool_workspace_info(args):
    info = detect_workspace(args.get("path") or os.getcwd(), None, None, None)
    return json.dumps(info, ensure_ascii=False, indent=2)


def tool_find_definition(args):
    return mcp_find(info_for_mcp(args.get("path")), "-d", args["symbol"])


def tool_find_references(args):
    return mcp_find(info_for_mcp(args.get("path")), "-r", args["symbol"])


def tool_find_symbol(args):
    return mcp_find(info_for_mcp(args.get("path")), "-s", args["pattern"])


def tool_search_text(args):
    info = detect_workspace(args.get("path") or os.getcwd(), None, None, None)
    glob = args.get("glob")
    if which("rg"):
        cmd = [which("rg"), "-n", "--no-heading", "--color", "never"]
        if glob:
            cmd.extend(["-g", glob])
        cmd.extend(["--", args["pattern"], info["root"]])
    else:
        # 无 ripgrep 时用 grep/ugrep;项目里已确认 grep 是 ugrep,支持 -r/-E/--include
        cmd = [which("grep") or "grep", "-rnI", "-E", "--color=never",
               "--exclude-dir=.git", "--exclude-dir=.repo", "--exclude-dir=out",
               "--exclude-dir=prebuilts", "--exclude-dir=build"]
        if glob:
            cmd.append("--include=" + glob)
        cmd.extend(["-e", args["pattern"], info["root"]])
    p = subprocess.run(cmd, cwd=info["root"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode not in (0, 1):
        raise McpError((p.stderr or "search failed").strip())
    out = rel_lines(p.stdout or "", info["root"])
    return truncate(out) if out.strip() else "no matches for '%s'" % args["pattern"]


def tool_list_files(args):
    info = detect_workspace(args.get("path") or os.getcwd(), None, None, None)
    glob = args.get("glob")
    if which("rg"):
        cmd = [which("rg"), "--files", info["root"]]
        if glob:
            cmd.extend(["-g", glob])
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode not in (0, 1):
            raise McpError((p.stderr or "rg --files failed").strip())
        out = rel_file_lines(p.stdout or "", info["root"])
    else:
        prune = ["-name", ".git", "-o", "-name", ".repo", "-o", "-name", "out", "-o", "-name", "prebuilts", "-o", "-name", "build"]
        cmd = ["find", info["root"], "(", *prune, ")", "-prune", "-o", "-type", "f"]
        if glob:
            cmd.extend(["-name", glob])
        cmd.append("-print")
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode != 0:
            raise McpError((p.stderr or "find failed").strip())
        out = rel_file_lines(p.stdout or "", info["root"])
    return truncate(out) if out.strip() else "no files"


def safe_path(info, p):
    path = Path(p)
    if not path.is_absolute():
        path = Path(info["root"]) / path
    path = path.resolve()
    root = Path(info["root"]).resolve()
    try:
        path.relative_to(root)
    except Exception:
        raise McpError("path is outside workspace: %s" % path)
    return path


def tool_read_file(args):
    info = detect_workspace(args.get("path") or os.getcwd(), None, None, None)
    path = safe_path(info, args["file"])
    if not path.is_file():
        raise McpError("not a file: %s" % path)
    start = max(1, int(args.get("start_line") or 1))
    end = args.get("end_line")
    lines = path.read_text(errors="ignore").splitlines()
    if end is None:
        end = min(len(lines), start + 399)
    end = min(len(lines), int(end))
    body = "\n".join("%6d  %s" % (i + 1, lines[i]) for i in range(start - 1, end))
    return truncate(body, limit=500)


def tool_git_diff(args):
    info = detect_workspace(args.get("path") or os.getcwd(), None, None, None)
    cmd = ["git", "-C", info["root"], "diff", "--no-color"]
    if args.get("staged"):
        cmd.append("--cached")
    if args.get("file"):
        cmd.extend(["--", args["file"]])
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise McpError((p.stderr or "git diff failed").strip())
    out = p.stdout or ""
    return truncate(out, limit=400) if out.strip() else "working tree is clean"


MCP_TOOLS = [
    {
        "name": "workspace_info",
        "description": "Detect the code workspace (root, profile, index status) for a path.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "File or directory path; defaults to cwd."}},
        },
    },
    {
        "name": "find_definition",
        "description": "Find the definition(s) of a C/C++ symbol using the GNU GLOBAL index.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "symbol": {"type": "string"},
                "path": {"type": "string", "description": "File or directory in the workspace."},
            },
            "required": ["symbol"],
        },
    },
    {
        "name": "find_references",
        "description": "Find all references (uses) of a symbol using the GNU GLOBAL index.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "symbol": {"type": "string"},
                "path": {"type": "string"},
            },
            "required": ["symbol"],
        },
    },
    {
        "name": "find_symbol",
        "description": "Search symbols by name/pattern (GNU GLOBAL -s).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "path": {"type": "string"},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "search_text",
        "description": "Fast text search (ripgrep) in the workspace; returns file:line:text.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "glob": {"type": "string", "description": "Optional ripgrep -g glob, e.g. '*.c'."},
                "path": {"type": "string"},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "list_files",
        "description": "List workspace files with ripgrep --files, optionally filtered by glob.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "glob": {"type": "string"},
                "path": {"type": "string"},
            },
        },
    },
    {
        "name": "read_file",
        "description": "Read a text file (or line range) inside the workspace.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file": {"type": "string"},
                "start_line": {"type": "integer"},
                "end_line": {"type": "integer"},
                "path": {"type": "string"},
            },
            "required": ["file"],
        },
    },
    {
        "name": "git_diff",
        "description": "Show git diff for the workspace or a single file.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file": {"type": "string"},
                "staged": {"type": "boolean"},
                "path": {"type": "string"},
            },
        },
    },
]

# 所有工具都是只读的;给 MCP 客户端(Codex/Claude 等)提供 annotations
for _t in MCP_TOOLS:
    _t.setdefault("annotations", {}).update({
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    })

MCP_HANDLERS = {
    "workspace_info": tool_workspace_info,
    "find_definition": tool_find_definition,
    "find_references": tool_find_references,
    "find_symbol": tool_find_symbol,
    "search_text": tool_search_text,
    "list_files": tool_list_files,
    "read_file": tool_read_file,
    "git_diff": tool_git_diff,
}


def mcp_response(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def mcp_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def handle_mcp(msg):
    if not isinstance(msg, dict):
        return mcp_error(None, -32600, "invalid request")
    method = msg.get("method")
    req_id = msg.get("id")
    if method == "initialize":
        return mcp_response(req_id, {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "aivim-gtags", "version": "0.1.0"},
        })
    if method == "notifications/initialized":
        return None
    if method == "ping":
        return mcp_response(req_id, {})
    if method == "tools/list":
        return mcp_response(req_id, {"tools": MCP_TOOLS})
    if method == "tools/call":
        params = msg.get("params") or {}
        name = params.get("name")
        args = params.get("arguments") or {}
        handler = MCP_HANDLERS.get(name)
        if not handler:
            return mcp_error(req_id, -32602, "unknown tool: %s" % name)
        try:
            text = handler(args)
            return mcp_response(req_id, {
                "content": [{"type": "text", "text": text}],
                "isError": False,
            })
        except McpError as e:
            return mcp_response(req_id, {
                "content": [{"type": "text", "text": str(e)}],
                "isError": True,
            })
        except Exception as e:
            return mcp_response(req_id, {
                "content": [{"type": "text", "text": "error: %s" % e}],
                "isError": True,
            })
    return mcp_error(req_id, -32601, "method not found: %s" % method)


def cmd_mcp(_args):
    eprint("aicx mcp: ready (stdio)")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception as e:
            print(json.dumps(mcp_error(None, -32700, "parse error: %s" % e)), flush=True)
            continue
        try:
            resp = handle_mcp(msg)
        except Exception as e:
            resp = mcp_error(msg.get("id") if isinstance(msg, dict) else None, -32603, str(e))
        if resp is not None:
            print(json.dumps(resp, ensure_ascii=False), flush=True)
    return 0


def cmd_mcp_config(_args):
    script = str(Path(__file__).resolve())
    py = which("python3") or "python3"
    data = {
        "claude_command": "claude mcp add --scope user aivim-gtags -- %s %s mcp" % (py, script),
        "codex_command": "codex mcp add aivim-gtags -- %s %s mcp" % (py, script),
        "json": {
            "mcpServers": {
                "aivim-gtags": {
                    "command": py,
                    "args": [script, "mcp"],
                }
            }
        },
        "toml": (
            "[mcp_servers.aivim-gtags]\n"
            'command = "%s"\n'
            'args = ["%s", "mcp"]\n' % (py, script)
        ),
    }
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


# ───────────────────────────── CLI ─────────────────────────────

def main(argv=None):
    ap = argparse.ArgumentParser(prog="aicx", description="generic gtags indexer + MCP server")
    sub = ap.add_subparsers(dest="cmd", required=True)

    ws = sub.add_parser("workspace", help="workspace detection")
    ws_sub = ws.add_subparsers(dest="ws_cmd", required=True)
    wsd = ws_sub.add_parser("detect", help="detect workspace for a path")
    wsd.add_argument("path", nargs="?", default=".")
    wsd.add_argument("--json", action="store_true")
    wsd.add_argument("--profile")
    wsd.add_argument("--arch")
    wsd.add_argument("--root")

    idx = sub.add_parser("index", help="index management")
    idx_sub = idx.add_subparsers(dest="idx_cmd", required=True)

    b = idx_sub.add_parser("build", help="build index")
    b.add_argument("path", nargs="?", default=".")
    b.add_argument("--profile")
    b.add_argument("--arch")
    b.add_argument("--root")
    b.add_argument("--force", action="store_true")
    b.add_argument("--json", action="store_true")

    u = idx_sub.add_parser("update", help="incremental update")
    u.add_argument("path", nargs="?", default=".")
    u.add_argument("--profile")
    u.add_argument("--arch")
    u.add_argument("--root")
    u.add_argument("--json", action="store_true")

    s = idx_sub.add_parser("status", help="index status")
    s.add_argument("path", nargs="?", default=".")
    s.add_argument("--profile")
    s.add_argument("--arch")
    s.add_argument("--root")
    s.add_argument("--json", action="store_true")

    c = idx_sub.add_parser("clean", help="clean index cache")
    c.add_argument("path", nargs="?", default=".")
    c.add_argument("--all", action="store_true")
    c.add_argument("--json", action="store_true")
    c.add_argument("--profile")
    c.add_argument("--arch")
    c.add_argument("--root")

    q = sub.add_parser("query", help="query the index")
    q.add_argument("kind", choices=["def", "definition", "refs", "references", "symbol", "text", "file"])
    q.add_argument("symbol")
    q.add_argument("--path", default=".")

    m = sub.add_parser("mcp", help="run MCP stdio server")
    mc = sub.add_parser("mcp-config", help="print MCP config snippets")

    args = ap.parse_args(argv)

    if args.cmd == "workspace":
        info = detect_workspace(args.path, args.profile, args.arch, args.root)
        if args.json:
            print(json.dumps(info, ensure_ascii=False))
        else:
            print("root:    %s" % info["root"])
            print("profile: %s" % info["profile"])
            print("arch:    %s" % info["arch"])
            print("cache:   %s" % info["cache"])
            print("indexed: %s  stale: %s" % (info["indexed"], info["stale"]))
        return 0
    if args.cmd == "index":
        if args.idx_cmd == "build":
            return cmd_index_build(args)
        if args.idx_cmd == "update":
            return cmd_index_update(args)
        if args.idx_cmd == "status":
            return cmd_index_status(args)
        if args.idx_cmd == "clean":
            return cmd_index_clean(args)
    if args.cmd == "query":
        return cmd_query(args)
    if args.cmd == "mcp":
        return cmd_mcp(args)
    if args.cmd == "mcp-config":
        return cmd_mcp_config(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
