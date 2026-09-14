# CKFinder for Java 2.6.x —— ImageResize 路径穿越写漏洞 · 隔离复现实验室
#
# 基础镜像：ubuntu:22.04（纯净，不使用任何既有业务容器）
# 运行时：OpenJDK 8（javax.servlet 世代，与 2.6.x 原始部署一致）+ Tomcat 9（javax.servlet 容器）
#
# 说明：Tomcat 10+ 使用 jakarta.servlet，CKFinder 2.6.x 无法运行，故固定 Tomcat 9。
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TOMCAT_VERSION=9.0.99 \
    CATALINA_HOME=/opt/tomcat \
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
    PATH=/usr/lib/jvm/java-8-openjdk-amd64/bin:/opt/tomcat/bin:$PATH

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-8-jdk-headless \
      ca-certificates \
      curl \
      unzip \
      procps \
      python3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /lab

# 官方 2.6.2 发行包内的 WAR 由 setup.sh 在构建期从官方渠道下载并校验 SHA-256。
# 本仓库不重新分发厂商二进制。
# 离线/内网构建：把官方 WAR 放到 lab/src/ 下，或用 -v <dir>:/opt/ckfinder-pkgs 挂载。
COPY src/ /lab/src/

# 实验室配置与脚本
COPY setup.sh        /lab/setup.sh
COPY run-lab.sh      /lab/run-lab.sh
COPY restart-tomcat.sh /lab/restart-tomcat.sh
COPY poc/            /lab/poc/
COPY fix-verify/     /lab/fix-verify/
COPY diag/           /lab/diag/

RUN chmod +x /lab/*.sh /lab/poc/*.sh /lab/fix-verify/*.sh /lab/diag/*.sh 2>/dev/null || true

# 构建期完成依赖安装与部署
RUN /lab/setup.sh

EXPOSE 8080

CMD ["/lab/run-lab.sh"]
