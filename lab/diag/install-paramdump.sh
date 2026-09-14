#!/usr/bin/env bash
# 安装诊断过滤器 -> 重启 Tomcat -> 对比 GET/POST 下连接器看到的参数
set -euo pipefail
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"
CATALINA_HOME=/opt/tomcat
APP="$CATALINA_HOME/webapps/ROOT"
BUILD=/tmp/paramdump

mkdir -p "$BUILD/src/lab" "$BUILD/classes" "$APP/WEB-INF/classes/lab"
cp /lab/diag/ParamDumpFilter.java "$BUILD/src/lab/"
CP="$(find "$APP/WEB-INF/lib" -name '*.jar' | tr '\n' ':')$CATALINA_HOME/lib/servlet-api.jar"
javac -encoding UTF-8 -nowarn -cp "$CP" -d "$BUILD/classes" "$BUILD/src/lab/ParamDumpFilter.java"
cp "$BUILD"/classes/lab/*.class "$APP/WEB-INF/classes/lab/"

python3 - "$APP/WEB-INF/web.xml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'ParamDumpFilter' not in s:
    block = ('\t<filter>\n\t\t<filter-name>ParamDumpFilter</filter-name>\n'
             '\t\t<filter-class>lab.ParamDumpFilter</filter-class>\n\t</filter>\n'
             '\t<filter-mapping>\n\t\t<filter-name>ParamDumpFilter</filter-name>\n'
             '\t\t<url-pattern>/*</url-pattern>\n\t</filter-mapping>\n')
    s = s.replace('</web-app>', block + '</web-app>')
    open(p, 'w', encoding='utf-8').write(s)
    print('web.xml: ParamDumpFilter 已注册')
else:
    print('web.xml: 已存在')
PY

echo "== 重启 Tomcat =="
if [ -x /lab/restart-tomcat.sh ]; then
  /lab/restart-tomcat.sh || true
else
  "$CATALINA_HOME/bin/shutdown.sh" 2>/dev/null || true
  sleep 5
  nohup "$CATALINA_HOME/bin/catalina.sh" run >/tmp/tomcat-diag.log 2>&1 &
  for i in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java?command=Init" 2>/dev/null; then
      echo "  Tomcat 就绪 (${i})"; break
    fi
    sleep 1
  done
fi

EP='http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java'
TOK='0123456789abcdef0123456789abcdef01234567'

echo
echo "== A) GET 形态 =="
curl -s -o /dev/null "$EP?command=Init&type=Images&currentFolder=%2F"
echo "== B) POST 形态 =="
curl -s -o /dev/null -X POST -H "Cookie: ckCsrfToken=$TOK" -H 'CKFinderCommand: true' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "command=Init&type=Images&currentFolder=%2F&ckCsrfToken=$TOK" "$EP"
sleep 1

echo
echo "== 过滤器抓到的参数（Tomcat 由 supervisor 启动，日志在 docker logs） =="
grep -h 'ParamDump' /opt/tomcat/logs/catalina.*.log 2>/dev/null | tail -20 | sed 's/^/  /' \
  || echo '  （去 docker logs ckfinder-lab 里查 ParamDump）'
