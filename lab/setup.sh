#!/usr/bin/env bash
# 一次性部署：安装 Tomcat 9 + 部署官方指定版本的 CKFinder WAR + 生成测试资源
#
# 可用 WAR_VERSION 选择被测版本（默认 2.6.2）：
#   docker build --build-arg WAR_VERSION=2.1 -t ckfinder-lab:2.1 ./lab
# 老版本的 WAR 文件名不同（2.0.x–2.3 为 CKFinderJava.war，2.4+ 带版本号），脚本按版本推导。
set -euo pipefail

TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.99}"
CATALINA_HOME="${CATALINA_HOME:-/opt/tomcat}"
WAR_VERSION="${WAR_VERSION:-2.6.2}"

log() { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }

# 各版本 WAR 在官方 zip 内的文件名
case "$WAR_VERSION" in
  2.0.*|2.1|2.1.1|2.2|2.2.1|2.2.2|2.3|2.3.1) WAR_NAME="CKFinderJava.war" ;;
  *)                                           WAR_NAME="CKFinderJava-${WAR_VERSION}.war" ;;
esac

# ---------------------------------------------------------------------------
# 0) 定位官方 WAR
#    查找顺序：-e WAR=... 指定 -> 离线暂存目录 -> 官方渠道下载
# 本仓库不分发厂商二进制，构建时从官方渠道下载
# ---------------------------------------------------------------------------
if [ -z "${WAR:-}" ]; then
  for c in "/opt/ckfinder-pkgs/$WAR_NAME" "/lab/src/$WAR_NAME"; do
    [ -f "$c" ] && WAR="$c" && break
  done
fi
if [ -z "${WAR:-}" ] || [ ! -f "${WAR:-}" ]; then
  mkdir -p /lab/src
  WAR="/lab/src/$WAR_NAME"
  log "从官方渠道下载 ckfinder_java_${WAR_VERSION}.zip"
  curl -fsSL --retry 3 --retry-delay 2 -o "/tmp/war-$WAR_VERSION.zip" \
    "https://download.cksource.com/CKFinder/CKFinder%20for%20Java/${WAR_VERSION}/ckfinder_java_${WAR_VERSION}.zip"
  unzip -q -j "/tmp/war-$WAR_VERSION.zip" "*/$WAR_NAME" -d /lab/src
  rm -f "/tmp/war-$WAR_VERSION.zip"
fi

# 校验官方 WAR 的 SHA-256 —— 确保复现针对的是未被篡改的官方原件
# 默认值为 2.6.2 的 WAR；测其他版本时用 -e EXPECT_WAR_SHA256=<实际值> 指定，
# 或先离线放好再构建。哈希清单见 ADVISORY-hashes.md。
EXPECT_WAR_SHA256="${EXPECT_WAR_SHA256:-e17ab903aff78efaa88fa252a1708b785c871c1ae0db94f6100644dcd1995a0c}"
actual_war_sha256="$(sha256sum "$WAR" | awk '{print $1}')"
if [ "$actual_war_sha256" = "$EXPECT_WAR_SHA256" ]; then
  log "WAR SHA-256 校验通过: $actual_war_sha256"
else
  log "!! WAR SHA-256 不匹配"
  log "   期望: $EXPECT_WAR_SHA256"
  log "   实际: $actual_war_sha256"
  log "   如确认是官方原件，可用 -e EXPECT_WAR_SHA256=<实际值> 覆盖重跑"
  exit 1
fi
log "使用 WAR: $WAR ($(stat -c%s "$WAR") bytes)  版本 $WAR_VERSION"

# ---------------------------------------------------------------------------
# 1) Tomcat 9（javax.servlet）
# ---------------------------------------------------------------------------
if [ ! -x "$CATALINA_HOME/bin/catalina.sh" ]; then
  log "下载 Apache Tomcat ${TOMCAT_VERSION}"
  mkdir -p /opt/tomcat-dl
  url="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
  curl -fsSL --retry 3 --retry-delay 2 -o /opt/tomcat-dl/tomcat.tar.gz "$url"
  mkdir -p "$CATALINA_HOME"
  tar -xzf /opt/tomcat-dl/tomcat.tar.gz -C "$CATALINA_HOME" --strip-components=1
  rm -rf /opt/tomcat-dl
  log "Tomcat 安装完成: $("$CATALINA_HOME/bin/version.sh" 2>/dev/null | grep -m1 'Server version' || echo "$TOMCAT_VERSION")"
else
  log "Tomcat 已存在，跳过下载"
fi

# 去掉发行包自带的示例应用，减小噪声
rm -rf "$CATALINA_HOME"/webapps/docs "$CATALINA_HOME"/webapps/examples \
       "$CATALINA_HOME"/webapps/manager "$CATALINA_HOME"/webapps/host-manager 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2) 目录布局
#    官方 WAR 的 web.xml 把上下文路径写死在 servlet 映射里：
#      <url-pattern> /ckfinder/core/connector/java/connector.java </url-pattern>
#    因此必须以 ROOT 上下文部署（应用上下文 = /），连接器才是
#      /ckfinder/core/connector/java/connector.java
#
#    /opt/tomcat/webapps/ROOT/Resources/userfiles        <- CKFinder 资源目录（仅应写此处）
#    /opt/tomcat/webapps/ROOT/upload/login               <- 资源目录之外的"公网可访问目录"（穿越目标）
#    /opt/tomcat/webapps/shared                          <- 资源目录之外的"同机其他应用目录"（穿越目标）
# ---------------------------------------------------------------------------
APP="$CATALINA_HOME/webapps/ROOT"
BASE="$APP/Resources/userfiles"

log "创建实验室目录布局"
mkdir -p "$BASE"
mkdir -p "$APP/upload/login"
# shared 要成为 Tomcat 认得的 webapp，必须有 WEB-INF（否则会被当成静态目录自动卸载）
mkdir -p "$CATALINA_HOME/webapps/shared/WEB-INF"

# ---------------------------------------------------------------------------
# 3) 部署官方 WAR（解包部署到 ROOT，保持官方 config.xml 原样后再打补丁）
# ---------------------------------------------------------------------------
if [ ! -f "$APP/WEB-INF/config.xml" ]; then
  log "解包部署 WAR -> $APP"
  # 整个清空 ROOT（含 Tomcat 自带默认首页）后解包
  rm -rf "$APP"; mkdir -p "$APP"
  unzip -q "$WAR" -d "$APP"
else
  log "应用已部署，仅重打配置补丁"
fi

# 整个删除 META-INF/context.xml：其 antiJARLocking 属性在 Tomcat 9 已废弃，会告警
rm -f "$APP/META-INF/context.xml"

# 资源类型根目录（config.xml 声明 Files/Images/Flash 三个类型）。
# 必须在 WAR 解包之后创建 —— 上面的 rm -rf "$APP" 会一并删掉提前建好的目录。
mkdir -p "$BASE/files" "$BASE/images" "$BASE/flash"

# ---------------------------------------------------------------------------
# 4) 配置补丁：启用连接器 + 指定资源目录；认证与 ACL 保持官方默认
#    Configuration.checkAuthentication() 直通 return true；
#    样例 ACL 对通配角色 <role>*</role> 授予全部权限
# ---------------------------------------------------------------------------
log "打配置补丁（enabled=true / baseDir / baseURL），认证与 ACL 保持官方默认"
python3 - "$APP/WEB-INF/config.xml" "$BASE" <<'PY'
import re, sys
path, base = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8').read()
orig = s

s = s.replace('<enabled>false</enabled>', '<enabled>true</enabled>')
# 已打过补丁时上面不会命中；此时 enabled 已是 true，无需处理

# baseDir：把标签内容替换为实验室目录（无论官方样例是空、是默认值还是已打过补丁）
s, n = re.subn(r'<baseDir>.*?</baseDir>|<baseDir\s*/>',
               '<baseDir>%s</baseDir>' % base, s, count=1, flags=re.S)
if n == 0:
    raise SystemExit('!! 未能定位 baseDir 标签，请人工检查 config.xml')

# baseURL 与 baseDir 对应
s = re.sub(r'<baseURL>.*?</baseURL>', '<baseURL>/Resources/userfiles/</baseURL>',
           s, count=1, flags=re.S)

if s == orig:
    raise SystemExit('!! config.xml 未发生任何变化，补丁失败')
open(path, 'w', encoding='utf-8').write(s)

ok_enabled = '<enabled>true</enabled>' in s
ok_base    = ('<baseDir>%s</baseDir>' % base) in s
ok_url     = '<baseURL>/Resources/userfiles/</baseURL>' in s
print('   enabled=true : %s' % ok_enabled)
print('   baseDir      : %s -> %s' % (ok_base, base))
print('   baseURL      : %s' % ok_url)
assert ok_enabled and ok_base and ok_url, '配置补丁校验未通过'
PY

# 插件由官方 config.xml 启用，此处只断言其存在
grep -q 'imageresize' "$APP/WEB-INF/config.xml" \
  && log "imageresize 插件：已启用（官方默认）" \
  || log "警告：config.xml 中未见 imageresize 插件"

# ---------------------------------------------------------------------------
# 5) 生成容器内辅助脚本 + 测试用源图
#    lab-reset.sh 由本脚本在构建期写入容器，不进仓库（内容是实验室产物清理）
# ---------------------------------------------------------------------------
cat > /lab/lab-reset.sh <<'SH'
#!/usr/bin/env bash
# 清理上一轮复现产物，恢复到"只有跳板目录 + 空目标目录"的状态
set -euo pipefail
BASE=/opt/tomcat/webapps/ROOT/Resources/userfiles
rm -rf "$BASE/Resources" "$BASE/shared" "$BASE/upload"
rm -rf /opt/tomcat/webapps/ROOT/upload/login/*
rm -rf /opt/tomcat/webapps/shared/*
mkdir -p /opt/tomcat/webapps/shared/WEB-INF /opt/tomcat/webapps/ROOT/upload/login
echo "[lab-reset] 已清理：userfiles 穿越残留 + ROOT/upload/login + webapps/shared"
SH

chmod +x /lab/lab-reset.sh

# 测试用源图（1x1 与 10x10，用于区分"重采样"与"原样字节复制"）
python3 - <<'PY'
import struct, zlib, os
def png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)
    return data
os.makedirs('/lab/poc/assets', exist_ok=True)
a = png('/lab/poc/assets/marker-1x1.png', 1, 1, (255, 0, 0))
b = png('/lab/poc/assets/marker-10x10.png', 10, 10, (0, 128, 255))
print('   marker-1x1.png   %d bytes' % len(a))
print('   marker-10x10.png %d bytes' % len(b))
PY

log "部署完成"
log "连接器 URL        : /ckfinder/core/connector/java/connector.java"
log "资源目录(CKFinder) : $BASE"
log "穿越目标(公网可访问): $APP/upload/login/"
log "穿越目标(同机他应用): $CATALINA_HOME/webapps/shared/"
