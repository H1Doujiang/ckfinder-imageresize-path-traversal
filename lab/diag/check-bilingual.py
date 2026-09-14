#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""中英两节一致性核查：关键主张必须两边都在，旧说法必须都已清除。"""
import re
import sys

path = r"E:\Oracle\myproject\CKFinder\publish\README.md"
txt = open(path, encoding="utf-8").read()

i = txt.index("## 中文说明")
en, zh = txt[:i], txt[i:]
print("英文节 %d 字符 / 中文节 %d 字符\n" % (len(en), len(zh)))

checks = [
    ("影响范围下界 2.0.2",      r"2\.0\.2"),
    ("影响范围上界 2.6.3",      r"2\.6\.3"),
    ("覆盖分界 2.5.1",          r"2\.5\.1"),
    ("20 个版本",               r"20\b"),
    ("9 个不同文件版本",         r"\b9\b|nine"),
    ("CVSS 8.6",                r"8\.6"),
    ("CVSS 6.5",                r"6\.5"),
    ("非 RCE 结论",             r"RCE"),
    ("扩展名拦截 105",           r"105"),
    ("跨平台 PHP",              r"PHP"),
    ("跨平台 ASP.NET",          r"ASP\.NET"),
    ("跨平台 ColdFusion",       r"ColdFusion"),
    ("跨平台 Classic ASP",      r"Classic ASP"),
    ("说明为何不用 ||",          r"over-broad|rejects those too|不要.*套用|过宽|会连合法路径"),
    ("只保留隐藏文件检查",        r"checkIfFileIsHidden|隐藏文件检查"),
    ("canonical 边界校验",       r"canonical|Canonical|getCanonicalFile"),
    ("3.x / 4.x 不受影响",      r"3\.x\s*/\s*4\.x"),
]
bad = 0
for name, pat in checks:
    e, z = bool(re.search(pat, en, re.I)), bool(re.search(pat, zh, re.I))
    if e and z:
        mark = "OK  "
    elif e and not z:
        mark, bad = "!! 中文缺", bad + 1
    elif z and not e:
        mark, bad = "!! 英文缺", bad + 1
    else:
        mark, bad = "--  两节均无", bad + 1
    print("  [%s] %-22s en=%-5s zh=%s" % (mark, name, e, z))

print("\n=== 中文节旧说法清除情况 ===")
stale = [
    ("配合 overwrite=1 可覆盖既有文件（无限定）", r"配合 `overwrite=1` 可覆盖既有文件"),
    ("把 && 改成 || 即可阻断穿越",              r"把 `&&` 改成 `\|\|` 即可阻断"),
    ("修复建议第 1 条 = && 改为 ||",            r"1\. `&&` 改为 `\|\|`"),
    ("影响版本 = 仅三版列举",                    r"2\.6\.2 / 2\.6\.2\.1 / 2\.6\.3 的缺陷文件逐字节相同"),
]
for name, pat in stale:
    hit = bool(re.search(pat, zh))
    if hit:
        bad += 1
    print("  %-40s %s" % (name, "!! 仍存在" if hit else "已清除"))

print("\n结论：%s" % ("两节一致" if bad == 0 else "存在 %d 处不一致" % bad))
sys.exit(0 if bad == 0 else 1)
