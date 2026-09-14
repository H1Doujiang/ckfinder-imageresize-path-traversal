#!/usr/bin/env bash
# 一键复现入口（容器内执行）
set -euo pipefail
export CKF_BASE="${CKF_BASE:-http://127.0.0.1:8080}"

echo "== 等待 Tomcat 就绪 =="
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null "${CKF_BASE}/ckfinder/core/connector/java/connector.java?command=Init&type=Images&currentFolder=%2F" 2>/dev/null; then
    echo "  就绪（第 ${i} 次探测）"
    break
  fi
  sleep 1
  [ "$i" = "60" ] && { echo "  !! Tomcat 未就绪，检查 /opt/tomcat/logs/catalina.out"; exit 1; }
done

exec python3 /lab/poc/exploit.py
