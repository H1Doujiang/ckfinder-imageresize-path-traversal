#!/usr/bin/env bash
# 发送一组请求，便于观察 ParamDumpFilter 输出
set -u
EP='http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java'
TOK='0123456789abcdef0123456789abcdef01234567'

echo '--- GET ---'
curl -s -o /dev/null -w '  HTTP %{http_code}\n' "$EP?command=Init&type=Images&currentFolder=%2F"
echo '--- POST ---'
curl -s -X POST -H "Cookie: ckCsrfToken=$TOK" -H 'CKFinderCommand: true' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "command=Init&type=Images&currentFolder=%2F&ckCsrfToken=$TOK" "$EP" | head -c 260
echo
echo '--- POST（无 type） ---'
curl -s -X POST -H "Cookie: ckCsrfToken=$TOK" -H 'CKFinderCommand: true' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "command=Init&currentFolder=%2F&ckCsrfToken=$TOK" "$EP" | grep -o 'Error number="[-0-9]*"'
