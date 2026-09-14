# CKFinder 本地复现实验室（Docker / ubuntu:22.04）

隔离复现 **CKFinder for Java 2.6.x —— ImageResize 插件路径穿越写入漏洞**。
所有环境（JDK、Tomcat、部署、PoC、修复验证）都在容器内，宿主只存放脚本与官方 WAR，**不污染本机**。

---

## 1. 目录

```
lab/
├── Dockerfile                      # ubuntu:22.04 + OpenJDK 8 + Tomcat 9
├── setup.sh                        # 容器内一次性部署（装 Tomcat、部署 WAR、打配置补丁、生成源图）
├── run-lab.sh                      # 容器启动入口（前台 Tomcat，便于 docker exec 进容器）
├── poc/
│   ├── exploit.py                  # 全流程验证（T0~T5 用例 + 自动判定）
│   └── poc.sh                      # 等待就绪后一键跑 PoC
└── fix-verify/
    ├── ImageResizeCommad-patched.java   # 加固版（&& -> || + canonical 边界校验）
    └── run.sh                           # 编译补丁 -> 替换 jar -> 重启 -> 重跑同一套 PoC
```

## 2. 快速开始

```powershell
# 宿主（Windows）: 进入 lab 目录
cd E:\Oracle\myproject\CKFinder\lab

# 1) 构建镜像（会自动下载 Tomcat 9.0.99 到镜像内）
docker build -t ckfinder-lab:2.6.2 .

# 2) 启动容器（宿主 18080 -> 容器 8080）
docker run -d --name ckfinder-lab -p 18080:8080 ckfinder-lab:2.6.2

# 3) 一键跑 PoC（T0~T5）
docker exec -it ckfinder-lab /lab/poc/poc.sh

# 4) 修复验证（编译加固版插件、重启、重跑同一套 PoC）
docker exec -it ckfinder-lab /lab/fix-verify/run.sh

# 5) 进容器自己复测
docker exec -it ckfinder-lab bash

# 6) 清理
docker rm -f ckfinder-lab; docker rmi ckfinder-lab:2.6.2
```

宿主直接访问写入结果（证明"资源目录之外 + 匿名可读"）：

```
http://127.0.0.1:18080/upload/login/poc-public.png
```

## 3. 容器内布局与对照关系

| 角色 | 容器内路径 | 对外 URL |
|---|---|---|
| CKFinder 连接器 | `webapps/ckfinder/` | `/ckfinder/core/connector/java/connector.java` |
| **资源目录**（只应写此处） | `webapps/ckfinder/Resources/userfiles/` | `/ckfinder/Resources/userfiles/` |
| Images 类型根 | `.../Resources/userfiles/Resources/images/` | — |
| **穿越目标①：公网可访问目录** | `webapps/ROOT/upload/login/` | `/upload/login/` |
| **穿越目标②：同机其他应用目录** | `webapps/shared/` | `/shared/` |

> 资源目录之外的路径之所以能通过 HTTP 读到，是因为 `webapps/ROOT` 与 `webapps/shared` 同为 Tomcat 应用 —— 与真实环境中"CKFinder 资源目录之外的静态资源目录/同机其他应用"等价。

## 4. 配置基线（**未做任何额外加固**）

| 配置项 | 取值 | 说明 |
|---|---|---|
| `<enabled>` | `true` | 官方样例默认 `false`，部署方必须手动打开 |
| `<baseDir>` | `webapps/ROOT/Resources/userfiles` | 资源目录 |
| `baseURL` | `/Resources/userfiles/` | 同上 |
| `checkAuthentication` | **未覆写** | 官方 `Configuration.checkAuthentication()` 直通 `return true` |
| `accessControls` | 官方样例：`<role>*</role>` 全部 8 项权限 | 与"照样例启用"的真实部署一致 |
| `enableCsrfProtection` | `true`（官方默认） | 双提交 cookie，攻击者自造 token 即可 |
| `hideFiles` | `.*`（官方默认） | 这就是"点开头名被拒"的来源 |
| 插件 | `imageresize`、`fileeditor` | 官方 `config.xml` 中默认已启用 |

**这就是本漏洞最关键的部署事实**：照官方样例把 CKFinder 启用起来，认证检查即直通，`ImageResize` 未认证可用。

`checkAuthentication()` 直通已用官方 jar 字节码独立确认：

```
$ javap -p -c -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.Configuration
  public boolean checkAuthentication(javax.servlet.http.HttpServletRequest);
      0: iconst_1        // 无条件 true
      1: ireturn
$ javap -p -constants ... IConfiguration
  public static final boolean DEFAULT_CHECKAUTHENTICATION = true;
```

## 4.1 搭建过程中实测确认的关键事实（避免踩坑）

这几条是本地部署时**实测**出来的，直接影响能否复现，建议报送材料里也写清楚：

1. **必须以 ROOT 上下文部署。** 官方 WAR 的 `WEB-INF/web.xml` 把上下文路径写死在 servlet 映射里：
   `<url-pattern>/ckfinder/core/connector/java/connector.java</url-pattern>`。
   把应用放在 `/ckfinder` 上下文时，容器会把 context path 剥掉，映射变成
   `/core/connector/java/connector.java`，与 web.xml 不匹配 → 连接器 404。
   真实目标上的 `/plugins/ckfinder/...` 端点属于同类"上下文前缀与映射拼接"的部署形态。
2. **POST 必须带 `CKFinderCommand=true` 作为表单参数**（不是请求头）。
   `ConnectorServlet.checkPostRequest()` 对原生命令强制校验，缺失时直接返回
   `Error 109 (INVALID_REQUEST)`；`QuickUpload`/`FileUpload` 不受此限。
3. **路径穿越深度**：`newFileName` 相对于"类型根目录"解析。本实验室布局下
   `images/` → 需 **4 层** `../` 才落到 webapp 根；差一层会落到不存在的
   `webapps/upload` 并以 `Error 104 (ACCESS_DENIED)` 失败。
   深度可用 `/lab/diag/probe-depth.py` 一键标定。
4. **跳板目录必须落在 Web 应用可部署范围内**才能被 HTTP 读取；
   仅建空目录而没有 `WEB-INF` 会被 Tomcat 当作静态目录自动卸载。
5. **不要用 `pkill -f Bootstrap` 重启容器内 Tomcat** —— 容器内 Tomcat 即 PID 1，
   会被一起杀掉导致容器退出；`/lab/restart-tomcat.sh` 已封装"等停稳再拉起"的正确流程。


## 5. PoC 用例与预期

| 用例 | 内容 | 预期（未修复） |
|---|---|---|
| T0 | 匿名 `Init` | `Error 0`（无认证） |
| T1 | `newFileName=xd/../../../ROOT/upload/login/poc-public.png` | `Error 0`，落盘 + 匿名 GET 200 |
| T2 | 跨应用写 `xd/../../../shared/poc-shared.txt` | `Error 0`，落盘 |
| T3 | 覆盖既有 `victim.txt`：无 `overwrite` vs `overwrite=1` | 前者 `Error 115` 且文件不变；后者 `Error 0` 且内容被 PNG 替换 |
| T4 | 请求尺寸 == 源图尺寸 | 输出与源图 **sha256 完全一致**（原样字节复制，尾部附加数据保留） |
| T5 | 反证 4 项 | 点开头名→`102`；`.jsp`→`105`；源图不存在→`109`；目录内正常改名→`Error 0` |

判定由 `exploit.py` 自动汇总，退出码非 0 表示存在 FAIL。

## 6. 注意事项

- **容器内端口 8080 未暴露到公网**，仅在宿主 `127.0.0.1:18080` 可访问。
- 容器内没有任何客户环境信息：目标为官方发行包自带的 `CKFinderJava-2.6.2.war`。
- Tomcat 必须为 **9.x（javax.servlet）**；Tomcat 10+ 为 jakarta.servlet，CKFinder 2.6.x 无法运行。
- 官方 WAR 自带 `commons-fileupload-1.2.2`、`thumbnailator-0.4.8` 等依赖，无需额外下载。
- 官方发行包为 licensed software，本实验室仅用于授权范围内的漏洞研究与报送，**勿公开传播**。
