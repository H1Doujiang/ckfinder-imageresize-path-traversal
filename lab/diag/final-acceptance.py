#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""提交验收：仓库完整性、commit 身份、内容一致性、推送准备度。

用法（仓库根目录或任意位置）：
    python3 lab/diag/final-acceptance.py [仓库目录]
"""
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.normpath(
    os.path.join(here, "..", ".."))
os.chdir(repo)

problems = []


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True,
                          encoding="utf-8").stdout.strip()


def chk(ok, label, detail=""):
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", label,
                           ("  " + detail) if detail else ""))
    if not ok:
        problems.append(label)


def read(f):
    with open(f, encoding="utf-8", errors="replace") as fh:
        return fh.read()


files = sh("git", "ls-files").split()
readme = read("README.md")
hashes = read("ADVISORY-hashes.md")
labreadme = read("lab/README.md")

print("=== 1. 仓库状态 ===")
chk(not sh("git", "status", "--porcelain"), "工作区干净")
chk(not sh("git", "status", "--porcelain", "-uall"), "无未跟踪文件")
chk(sh("git", "branch", "--show-current") == "main", "分支为 main")
chk(not sh("git", "for-each-ref", "refs/original/"), "无 filter-branch 残留引用")

print("\n=== 2. commit 身份（push 后不可逆） ===")
mails = sorted(set(sh("git", "log", "--format=%ae %ce").replace("\n", " ").split()))
chk(len(mails) == 1, "所有提交同一身份", " ".join(mails))
chk(mails and "noreply" in mails[0] and "qq.com" not in mails[0],
    "使用 GitHub noreply 邮箱（未暴露真实邮箱）")
chk(not any("qq.com" in m for m in mails), "无 qq.com 残留")

print("\n=== 3. 影响范围口径一致 ===")
chk("2.0.2 – 2.6.3" in readme or "2.0.2 - 2.6.3" in readme,
    "README 英文部分声明 2.0.2 – 2.6.3")
chk("2.0.2 – 2.6.3" in readme.split("## 中文说明")[-1],
    "README 中文部分声明同一范围")
chk("20" in readme and "20" in hashes, "两处均提到 20 个版本")
chk("2.0.2" in labreadme, "lab/README 也提到可复现的下界版本")

print("\n=== 4. 修复建议口径一致（不得推荐 && -> ||） ===")
for name, txt in (("README", readme), ("lab/README", labreadme)):
    bad = re.search(r"1\.\s*`&&`\s*改为\s*`\|\|`", txt)
    chk(not bad, "%s 未把 && -> || 列为修复方案" % name)
chk("checkIfFileIsHidden" in readme, "README 给出正确守卫写法")

print("\n=== 5. 哈希清单完整性 ===")
n64 = len(re.findall(r"\b[0-9a-f]{64}\b", hashes))
chk(n64 >= 15, "哈希条目数 = %d" % n64)
for v in ("2.0.2", "2.3.1", "2.5.0", "2.5.1", "2.6.0", "2.6.3"):
    chk(v in hashes, "清单覆盖 %s" % v)

print("\n=== 6. 可复现性文件齐备 ===")
for f in ("lab/Dockerfile", "lab/setup.sh", "lab/run-lab.sh", "lab/restart-tomcat.sh",
          "lab/poc/exploit.py", "lab/poc/poc.sh", "lab/fix-verify/run.sh",
          "lab/fix-verify/ImageResizeCommad-patched.java", "deploy.sh", "LICENSE"):
    chk(os.path.isfile(f), "存在 %s" % f)

print("\n=== 7. 远端一致性（推送后核对） ===")
remote_url = sh("git", "remote", "get-url", "origin")
if not remote_url:
    chk(False, "remote origin 未配置")
    print("      配置并推送：")
    print("        git remote add origin git@github.com:H1Doujiang/ckfinder-imageresize-path-traversal.git")
    print("        git push -u origin main")
else:
    chk(True, "remote origin = %s" % remote_url)
    upstream = sh("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    chk(bool(upstream), "本地分支已跟踪远端（%s）" % (upstream or "无"))
    # 远端 HEAD 需要走网络；失败时给 WARN 而不是 FAIL，避免离线误判
    r = subprocess.run(["git", "ls-remote", "origin", "main"],
                       capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        print("  [WARN] 无法访问远端（离线或链路问题）：%s" % (r.stderr.strip()[:80]))
    else:
        remote_head = r.stdout.split()[0] if r.stdout.split() else ""
        local_head = sh("git", "rev-parse", "HEAD")
        chk(remote_head == local_head, "远端 HEAD 与本地一致",
            "%s vs %s" % (remote_head[:7], local_head[:7]))

print("\n" + "=" * 62)
print("文件数 %d ｜ 提交数 %s ｜ 分支 %s" % (
    len(files), sh("git", "rev-list", "--count", "HEAD"), sh("git", "branch", "--show-current")))
if problems:
    print("存在 %d 项问题：%s" % (len(problems), problems))
    sys.exit(1)
print("验收全部通过")
