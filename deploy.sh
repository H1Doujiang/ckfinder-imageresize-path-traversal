#!/usr/bin/env bash
# 一键搭建 + 复现 + 修复验证
#
#   ./deploy.sh build     仅构建镜像
#   ./deploy.sh up        启动容器（宿主 18080 -> 容器 8080）
#   ./deploy.sh poc       跑 6 项用例（原始官方插件，预期全部 PASS）
#   ./deploy.sh fix       打补丁重编译 -> 重启 -> 重跑同一套用例（预期穿越全部被拒）
#   ./deploy.sh all       build + up + poc
#   ./deploy.sh down      删除容器
#
# 前置：本机已安装 Docker，且能访问 download.cksource.com（镜像构建期会从官方渠道拉取 WAR）。
set -euo pipefail

NAME="${NAME:-ckfinder-lab}"
TAG="${TAG:-ckfinder-lab:2.6.2}"
HOST_PORT="${HOST_PORT:-18080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

case "${1:-}" in
  build)
    docker build -t "$TAG" "$HERE/lab"
    ;;
  up)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -p "${HOST_PORT}:8080" "$TAG" >/dev/null
    echo "容器已启动：http://127.0.0.1:${HOST_PORT}"
    echo "等待就绪 ..."
    for i in $(seq 1 60); do
      if docker exec "$NAME" curl -fsS -o /dev/null \
         "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java?command=Init" 2>/dev/null; then
        echo "就绪（${i}s）"; exit 0
      fi
      sleep 1
    done
    echo "!! 超时未就绪：docker logs $NAME"; exit 1
    ;;
  poc)
    docker exec -it "$NAME" /lab/poc/poc.sh
    ;;
  fix)
    docker exec -it "$NAME" /lab/fix-verify/run.sh
    ;;
  all)
    "$0" build && "$0" up && "$0" poc
    ;;
  down)
    docker rm -f "$NAME"
    ;;
  *)
    usage
    ;;
esac
