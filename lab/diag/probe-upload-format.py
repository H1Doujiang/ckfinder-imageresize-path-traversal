#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""打印老版本 QuickUpload 的原始响应，用于适配不同版本的返回格式。"""
import os
import urllib.request

TOKEN = "0123456789abcdef0123456789abcdef01234567"
EP = "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java"

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

for label, url in (
    ("responseType=json", EP + "?command=QuickUpload&type=Images&currentFolder=%2F&responseType=json"),
    ("无 responseType",   EP + "?command=QuickUpload&type=Images&currentFolder=%2F"),
):
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Cookie", "ckCsrfToken=" + TOKEN)
    req.add_header("Content-Type", "multipart/form-data; boundary=" + b)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            text = r.read().decode("utf-8", "replace")
        print("--- %s -> HTTP %s ---" % (label, r.status))
        print("  " + text[:600].replace("\n", "\n  "))
    except Exception as e:
        print("--- %s -> 异常: %s" % (label, e))
    print()

print("--- images 目录内容 ---")
d = "/opt/tomcat/webapps/ROOT/Resources/userfiles/images"
print("  " + (", ".join(os.listdir(d)) if os.path.isdir(d) else "(不存在)"))
