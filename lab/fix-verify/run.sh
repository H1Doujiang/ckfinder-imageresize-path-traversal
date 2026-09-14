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
# 文件名须与 public 类名一致；"Commad" 是官方原始拼写，勿改
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
/lab/restart-tomcat.sh

echo "== 5) 重跑同一套 PoC（预期：穿越用例全部被拒） =="
OUT=/tmp/poc-patched.txt
set +e
python3 /lab/poc/exploit.py 2>&1 | tee "$OUT"
set -e
# 去掉 ANSI 颜色码，便于匹配
sed -i 's/\x1b\[[0-9;]*m//g' "$OUT"

echo
echo "== 6) 判定 =="
# 补丁生效的判据：T1~T4 的穿越被拒（FAIL），而 T0 与 T5 的反证仍成立（PASS）
fail_traversal=0
for t in "穿越写入成功且可被匿名 HTTP 读取" "跨应用目录写入成功" \
         "无 overwrite 被拒(115)" "输出文件与源文件 sha256 完全一致"; do
  grep -qF "FAIL ] $t" "$OUT" && fail_traversal=$((fail_traversal + 1))
done
pass_controls=0
grep -qF "PASS ] 匿名 Init 返回 Error 0" "$OUT" && pass_controls=$((pass_controls + 1))
grep -qF "PASS ] 四项反证符合预期" "$OUT" && pass_controls=$((pass_controls + 1))

printf '  穿越用例被拒: %d/4   反证仍成立: %d/2\n' "$fail_traversal" "$pass_controls"
if [ "$fail_traversal" -eq 4 ] && [ "$pass_controls" -eq 2 ]; then
  echo "  补丁生效：四类穿越全部被拒，且 T0/T5 行为不变"
else
  echo "  判定不通过，需人工检查："
  [ "$fail_traversal" -ne 4 ] && echo "    - 有穿越用例仍然成功，补丁可能未加载"
  [ "$pass_controls" -ne 2 ] && echo "    - T0/T5 反证未通过，补丁可能改坏了正常行为"
  echo "    原始输出: $OUT"
fi
echo
echo "  回滚原版: cp $PLUGIN_JAR.orig $PLUGIN_JAR && /lab/restart-tomcat.sh"
