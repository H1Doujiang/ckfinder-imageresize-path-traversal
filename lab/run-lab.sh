#!/usr/bin/env bash
# 实验室启动脚本（容器内 PID 1）
#
# 为什么不是简单的 `exec catalina.sh run`：
#   容器内 `shutdown.sh` 会停掉 Tomcat —— 而 Tomcat 就是 PID 1，
#   一旦它退出容器就整体退出了（修复验证需要反复重启 Tomcat）。
#   因此这里用极简 supervisor：Tomcat 退出后按需拉起，容器保持存活。
#
# 控制：
#   关闭容器          -> docker stop ckfinder-lab
#   仅重启 Tomcat     -> docker exec ckfinder-lab /lab/restart-tomcat.sh
#   关闭实验室        -> docker exec ckfinder-lab /lab/stop-lab.sh
set -uo pipefail

export CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$CATALINA_HOME/bin:$PATH"

# 若应用缺失（例如首次绑定挂载覆盖了镜像内容），自动补部署
if [ ! -f "$CATALINA_HOME/webapps/ROOT/WEB-INF/config.xml" ]; then
  echo "[run-lab] 未检测到部署，执行 setup.sh"
  /lab/setup.sh
fi
mkdir -p "$CATALINA_HOME/webapps/shared/WEB-INF" "$CATALINA_HOME/webapps/ROOT/upload/login"

echo "[run-lab] CKFinder 连接器: http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java"
echo "[run-lab] 资源目录: $CATALINA_HOME/webapps/ROOT/Resources/userfiles"

STOP=/lab/.stop
RESTART=/lab/.restart
rm -f "$STOP" "$RESTART"

while true; do
  rm -f "$RESTART"
  echo "[run-lab] $(date '+%F %T') 启动 Tomcat"

  catalina.sh run &
  pid=$!

  # 轮询：既等进程退出，也等"重启请求"标记
  while true; do
    if [ -f "$RESTART" ]; then
      echo "[run-lab] $(date '+%F %T') 收到重启请求，停止 Tomcat"
      catalina.sh stop 10 -force >/dev/null 2>&1 || true
      wait "$pid" 2>/dev/null || true
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      break
    fi
    sleep 1
  done

  rm -f "$CATALINA_HOME"/bin/tomcat.pid 2>/dev/null || true

  if [ -f "$STOP" ]; then
    echo "[run-lab] 收到关闭请求，容器退出"
    exit 0
  fi
  if [ ! -f "$RESTART" ]; then
    echo "[run-lab] Tomcat 已退出且未请求重启，容器退出"
    exit 0
  fi
  echo "[run-lab] 重启 Tomcat"
  sleep 2
done
