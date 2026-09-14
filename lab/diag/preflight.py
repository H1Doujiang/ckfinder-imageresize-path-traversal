#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""提交前静态检查：脱敏、二进制、行尾、断链、大文件、可疑内容。"""
import os
import re
import subprocess
import sys

REPO = r"E:\Oracle\myproject\CKFinder\publish"
os.chdir(REPO)

files = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                       encoding="utf-8").stdout.split()
problems = []


def report(ok, label, detail=""):
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", label,
                           ("  " + detail) if detail else ""))
    if not ok:
        problems.append(label)


print("=== 1. 文件数与二进制 ===")
report(len(files) > 0, "跟踪文件数 = %d" % len(files))
bins = [f for f in files if os.path.splitext(f)[1].lower() in
        (".war", ".jar", ".zip", ".png", ".jpg", ".gif", ".class", ".exe")]
report(not bins, "无二进制文件", str(bins) if bins else "")

print("\n=== 2. 行尾（容器内执行的前提） ===")
cr = []
for f in files:
    with open(f, "rb") as fh:
        if b"\r" in fh.read():
            cr.append(f)
report(not cr, "全部 LF，无 CR", str(cr) if cr else "")

print("\n=== 3. 客户信息脱敏 ===")
sens = ["sdent", "lcxzpthl", "山东省", "维保保", "handoff", "finding-F008",
        "navi --dir", "/workspace/tgt"]
hits = []
for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            for s in sens:
                if s in line:
                    hits.append("%s:%d %s" % (f, n, s))
report(not hits, "无客户/内部项目信息", "; ".join(hits) if hits else "")

print("\n=== 4. 主机绝对路径 / 个人邮箱 ===")
host = []
for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            if re.search(r"[A-Za-z]:\\|/mnt/[a-z]/|C:\\Users", line):
                host.append("%s:%d" % (f, n))
            if "hidoujiang@qq.com" in line:
                host.append("%s:%d qq邮箱" % (f, n))
report(not host, "无本机绝对路径、无个人邮箱", "; ".join(host) if host else "")

print("\n=== 5. 内链是否都存在 ===")
missing = []
for f in files:
    if not f.endswith(".md"):
        continue
    base = os.path.dirname(f)
    with open(f, encoding="utf-8") as fh:
        for m in re.finditer(r"\]\((?!https?://|#)([^)#]+)", fh.read()):
            tgt = os.path.normpath(os.path.join(base, m.group(1)))
            if not os.path.exists(tgt):
                missing.append("%s -> %s" % (f, m.group(1)))
report(not missing, "Markdown 相对链接均可解析", "; ".join(missing) if missing else "")

print("\n=== 6. 官方哈希是否与实际一致 ===")
import hashlib


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


ex = os.path.join(os.environ.get("TEMP", "/tmp"), "ckf-ex")
doc = open("ADVISORY-hashes.md", encoding="utf-8").read()
bad_hash = []
checked = 0
if os.path.isdir(ex):
    for v in sorted(os.listdir(ex)):
        d = os.path.join(ex, v)
        if not os.path.isdir(d):
            continue
        for root, _, fs in os.walk(d):
            for fn in fs:
                if fn == "ImageResizeCommad.java":
                    checked += 1
                    h = sha(os.path.join(root, fn))
                    if h not in doc:
                        bad_hash.append("%s %s" % (v, h[:16]))
    report(not bad_hash, "%d 个版本的缺陷文件哈希均在文档中命中" % checked,
           "; ".join(bad_hash) if bad_hash else "")
else:
    print("  [SKIP] 本地发行包缓存不存在，跳过哈希复算")

print("\n=== 7. 大文件（>100KB 应无） ===")
big = ["%s %.0fKB" % (f, os.path.getsize(f) / 1024) for f in files
       if os.path.getsize(f) > 100 * 1024]
report(not big, "无异常大文件", "; ".join(big) if big else "")

print("\n" + "=" * 60)
if problems:
    print("存在 %d 项问题：%s" % (len(problems), problems))
    sys.exit(1)
print("静态检查全部通过（%d 个文件）" % len(files))
