#!/usr/bin/env bash
#
# 关键：必须等旧实例真正停掉、新实例起来 —— 否则请求会打到尚未退出的旧进程，
# 让人误以为"补丁已替换却没生效"。
set -u
EP="http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java?command=Init"

up() { curl -fsS -o /dev/null --max-time 3 "$EP" 2>/dev/null; }

echo "[restart-tomcat] 发出重启请求"
touch /lab/.restart

echo -n "[restart-tomcat] 等待旧实例停止 "
for i in $(seq 1 60); do
  if ! up; then echo "-> 已停止（${i}s）"; break; fi
  sleep 1
  [ "$i" = "60" ] && { echo "-> !! 旧实例仍在响应"; exit 1; }
done

echo -n "[restart-tomcat] 等待新实例就绪 "
for i in $(seq 1 90); do
  if up; then echo "-> 就绪（${i}s）"; exit 0; fi
  sleep 1
done
echo "-> !! 超时未就绪，检查 /opt/tomcat/logs/catalina.*.log"
exit 1
