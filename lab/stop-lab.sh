#!/usr/bin/env bash
# 请求关闭实验室（让容器退出）
set -eu
touch /lab/.stop
echo "[stop-lab] 已请求关闭；容器将在数秒内退出"
