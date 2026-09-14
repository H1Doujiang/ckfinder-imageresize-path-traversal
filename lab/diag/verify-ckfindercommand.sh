#!/usr/bin/env bash
# 验证：POST 必须把 CKFinderCommand=true 作为【表单参数】提交（ConnectorServlet.checkPostRequest）
set -u
EP='http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java'
TOK='0123456789abcdef0123456789abcdef01234567'

post() { # post <描述> <是否带 CKFinderCommand 表单参数>
  local desc="$1" extra="$2"
  local out
  out=$(curl -s -X POST -H "Cookie: ckCsrfToken=$TOK" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "command=Init&type=Images&currentFolder=%2F&ckCsrfToken=$TOK${extra}" "$EP")
  printf '%-52s -> %s\n' "$desc" "$(printf '%s' "$out" | grep -o 'Error number="[-0-9]*"' | head -1)"
}

post 'POST 无 CKFinderCommand 表单参数' ''
post 'POST 带 &CKFinderCommand=true'    '&CKFinderCommand=true'

echo
echo '--- GetFiles 对照 ---'
for extra in '' '&CKFinderCommand=true'; do
  out=$(curl -s -X POST -H "Cookie: ckCsrfToken=$TOK" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "command=GetFiles&type=Images&currentFolder=%2F&ckCsrfToken=$TOK${extra}" "$EP")
  printf '%-52s -> %s\n' "GetFiles${extra:-（无 CKFinderCommand）}" \
    "$(printf '%s' "$out" | grep -o 'Error number="[-0-9]*"' | head -1)"
done
