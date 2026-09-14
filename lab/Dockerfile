# CKFinder for Java 2.6.x —— ImageResize 路径穿越写漏洞 · 隔离复现实验室
#
# 基础镜像：ubuntu:22.04（纯净，不使用任何既有业务容器）
# 运行时：OpenJDK 8（javax.servlet 世代，与 2.6.x 原始部署一致）+ Tomcat 9（javax.servlet 容器）
#
# 说明：Tomcat 10+ 使用 jakarta.servlet，CKFinder 2.6.x 无法运行，故固定 Tomcat 9。
FROM ubuntu:22.04

# 被测版本：默认 2.6.2；可用 --build-arg WAR_VERSION=2.1 切换到其他受影响版本
ARG WAR_VERSION=2.6.2
# 对应版本的 WAR SHA-256；非 2.6.2 必须显式传入（哈希清单见 ADVISORY-hashes.md）
ARG EXPECT_WAR_SHA256=e17ab903aff78efaa88fa252a1708b785c871c1ae0db94f6100644dcd1995a0c

ENV DEBIAN_FRONTEND=noninteractive \
    TOMCAT_VERSION=9.0.99 \
    CATALINA_HOME=/opt/tomcat \
    JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
    WAR_VERSION=${WAR_VERSION} \
    EXPECT_WAR_SHA256=${EXPECT_WAR_SHA256} \
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
