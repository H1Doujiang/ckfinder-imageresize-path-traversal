#!/usr/bin/env bash
# 只读诊断：查看全新容器中的目录布局与配置
set -u
echo '--- disk layout under Resources ---'
find /opt/tomcat/webapps/ROOT/Resources -maxdepth 3 2>/dev/null | sort
echo
echo '--- mkdir lines in setup.sh ---'
grep -n 'mkdir -p' /lab/setup.sh
echo
echo '--- config baseDir / baseURL ---'
grep -nE '<baseDir>|<baseURL>' /opt/tomcat/webapps/ROOT/WEB-INF/config.xml
echo
echo '--- Init (Images) ---'
curl -s 'http://127.0.0.1:8080/ckfinder/core/connector/java/connector.java?command=Init&type=Images&currentFolder=%2F' | head -c 240
echo
