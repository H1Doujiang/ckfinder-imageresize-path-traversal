#!/usr/bin/env bash
# 修复验证：把 [&& -> ||] + [canonical 边界校验] 打进插件 jar，重启 Tomcat，重跑同一套 PoC。
# 预期：T1/T2/T3/T4 全部失败（穿越被拒），T5 反证仍全部符合预期。
set -euo pipefail

CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"
APP="$CATALINA_HOME/webapps/ROOT"
PLUGIN_JAR="$APP/WEB-INF/lib/CKFinderPlugin-ImageResize-2.6.2.jar"
BUILD=/tmp/fix-build

echo "== 1) 准备编译环境（依赖取自官方 WAR 自带 jar） =="
rm -rf "$BUILD"; mkdir -p "$BUILD/src" "$BUILD/classes"
# javac 要求 public 类所在文件名与类名一致（ImageResizeCommad，注意官方原始拼写）
cp /lab/fix-verify/ImageResizeCommad-patched.java "$BUILD/src/ImageResizeCommad.java"

CP="$(find "$APP/WEB-INF/lib" -name '*.jar' | tr '\n' ':')$CATALINA_HOME/lib/servlet-api.jar"
echo "  classpath jars: $(find "$APP/WEB-INF/lib" -name '*.jar' | wc -l) 个"

echo "== 2) 编译补丁版 =="
javac -encoding UTF-8 -nowarn -cp "$CP" -d "$BUILD/classes" "$BUILD/src/ImageResizeCommad.java"
echo "  编译产物:"; find "$BUILD/classes" -name '*.class' | sed 's/^/    /'

echo "== 3) 备份原 jar 并替换类 =="
cp -n "$PLUGIN_JAR" "$PLUGIN_JAR.orig" || true
cd "$BUILD/classes"
jar uf "$PLUGIN_JAR" com/ckfinder/connector/plugins/ImageResizeCommad*.class
echo "  已更新 $PLUGIN_JAR"
unzip -l "$PLUGIN_JAR" | grep ImageResizeCommad | sed 's/^/    /'

echo "== 4) 重启 Tomcat（容器内置 supervisor 负责拉起） =="
if [ -x /lab/restart-tomcat.sh ]; then
  /lab/restart-tomcat.sh
else
  "$CATALINA_HOME/bin/shutdown.sh" 2>/dev/null || true
  sleep 5
  nohup "$CATALINA_HOME/bin/catalina.sh" run >/tmp/tomcat-patched.log 2>&1 &
  for i in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java?command=Init" 2>/dev/null; then
      echo "  Tomcat 已重启（第 ${i} 次探测）"; break
    fi
    sleep 1
    [ "$i" = "60" ] && { echo "  !! 重启失败，见 /tmp/tomcat-patched.log"; exit 1; }
  done
fi
echo "== 5) 重跑同一套 PoC（预期：穿越用例全部被拒） =="
set +e
python3 /lab/poc/exploit.py
rc=$?
set -e

echo
echo "== 6) 结论 =="
if [ "$rc" -ne 0 ]; then
  echo "  PoC 出现 FAIL 项 —— 对补丁版而言这通常正是『穿越已阻断』的预期结果："
  echo "    T1/T2/T3/T4 因穿越被拒而 FAIL = 修复生效"
  echo "    T5 反证是否仍符合预期，请对照上方输出"
else
  echo "  所有用例 PASS —— 说明补丁未生效或补丁未加载，请检查 jar 替换与 Tomcat 重启"
fi
echo
echo "  回滚原版: cp $PLUGIN_JAR.orig $PLUGIN_JAR && $CATALINA_HOME/bin/shutdown.sh && /lab/run-lab.sh"
