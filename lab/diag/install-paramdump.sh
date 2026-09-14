#!/usr/bin/env bash
# 排查用：装一个把请求参数原样打日志的过滤器，然后对比 GET / POST 的差异。
# 曾用它定位"POST 返回 Error 109"——原因是 CKFinderCommand 必须是表单参数而非请求头。
# 会修改 webapp 的 web.xml 并重启 Tomcat，仅用于排查。
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
if 'ParamDumpFilter' in s:
    print('web.xml: 已注册')
else:
    block = ('\t<filter>\n\t\t<filter-name>ParamDumpFilter</filter-name>\n'
             '\t\t<filter-class>lab.ParamDumpFilter</filter-class>\n\t</filter>\n'
             '\t<filter-mapping>\n\t\t<filter-name>ParamDumpFilter</filter-name>\n'
             '\t\t<url-pattern>/*</url-pattern>\n\t</filter-mapping>\n')
    open(p, 'w', encoding='utf-8').write(s.replace('</web-app>', block + '</web-app>'))
    print('web.xml: ParamDumpFilter 已注册')
PY

/lab/restart-tomcat.sh

EP='http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java'
TOK='0123456789abcdef0123456789abcdef01234567'

curl -s -o /dev/null "$EP?command=Init&type=Images&currentFolder=%2F"
curl -s -o /dev/null -X POST -H "Cookie: ckCsrfToken=$TOK" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "command=Init&type=Images&currentFolder=%2F&ckCsrfToken=$TOK&CKFinderCommand=true" "$EP"
sleep 1

echo
echo "== 过滤器抓到的参数（Tomcat stdout 在 docker logs） =="
grep -h 'ParamDump' /opt/tomcat/logs/catalina.*.log 2>/dev/null | tail -20 | sed 's/^/  /' || true
echo "  若上方为空，执行： docker logs ckfinder-lab 2>&1 | grep ParamDump"
