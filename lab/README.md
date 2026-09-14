# CKFinder 复现实验室（Docker / ubuntu:22.04）

隔离复现 CKFinder for Java 2.6.x 的 ImageResize 路径穿越写漏洞。
厂商二进制不随仓库分发，构建时从官方渠道下载并校验 SHA-256。

---

## 1. 目录

```
lab/
├── Dockerfile                      # ubuntu:22.04 + OpenJDK 8 + Tomcat 9
├── setup.sh                        # Tomcat 9 + WAR + 配置补丁 + 测试源图
├── run-lab.sh                      # 容器入口：supervisor，只认 /lab/.restart 标记
├── restart-tomcat.sh               # 只重启 Tomcat，等旧实例停稳再拉起
├── src/                            # 离线构建用，默认空（见 src/README.md）
├── poc/
│   ├── exploit.py                  # T0~T5 用例 + 自动判定
│   └── poc.sh                      # 等连接器就绪后执行 exploit.py
├── fix-verify/
│   ├── ImageResizeCommad-patched.java   # 加固版（canonical 边界校验）
│   └── run.sh                           # 编译补丁 -> 替换 jar -> 重启 -> 重跑并判定
└── diag/                           # 排查用，不参与主链路
    ├── probe-depth.py              # 标定 ../ 穿越深度，找落点
    ├── probe-createfolder.py       # 单独验证 CreateFolder 的 CSRF 与返回
    ├── verify-ckfindercommand.sh   # 验证 CKFinderCommand 必须是表单参数
    ├── install-paramdump.sh        # 装一个把请求参数打印到日志的过滤器
    └── ParamDumpFilter.java
```

## 2. 快速开始

```bash
git clone https://github.com/H1Doujiang/ckfinder-imageresize-path-traversal.git
cd ckfinder-imageresize-path-traversal/lab

# 构建期从官方渠道下载 CKFinder 2.6.2 WAR 与 Tomcat 9.0.99，并校验 WAR 的 SHA-256
docker build -t ckfinder-lab:2.6.2 .

docker run -d --name ckfinder-lab -p 18080:8080 ckfinder-lab:2.6.2

docker exec -it ckfinder-lab /lab/poc/poc.sh              # T0~T5
docker exec -it ckfinder-lab /lab/fix-verify/run.sh       # 打补丁后重跑，穿越应被拒
docker exec -it ckfinder-lab /lab/lab-reset.sh            # 清理上一轮产物
docker exec -it ckfinder-lab bash                         # 进容器手动复测

docker rm -f ckfinder-lab; docker rmi ckfinder-lab:2.6.2
```

`docker stop` 会连带停掉容器（supervisor 只在 `/lab/.restart` 标记存在时才重新拉起 Tomcat）。
`deploy.sh` 是同一流程的封装（`all` / `fix` / `down` / `poc` / `up` / `build`）。

### 复现其他受影响版本

缺陷存在于全部 20 个可获取的 Java 2.x 版本，`WAR_VERSION` 可切换被测版本
（各版本 WAR 的 SHA-256 见仓库根目录 `ADVISORY-hashes.md`）：

```bash
docker build --build-arg WAR_VERSION=2.1 \
             --build-arg EXPECT_WAR_SHA256=4856551ede93e720eb1b7f4a83e118547563b137832ed553620414b41a52b2c9 \
             -t ckfinder-lab:2.1 .
docker run -d --name ckfinder-lab-21 -p 18081:8080 ckfinder-lab:2.1
```

两点版本差异会被 PoC 自动处理，不需要改用例：

- **响应格式**：2.0–2.5 的 `QuickUpload` 返回 JS 回调（`OnUploadCompleted(...)`），
  2.6.x 返回 JSON（`{"fileName":...}`）；`exploit.py` 按响应里出现的文件名统一提取。
- **覆盖能力**：2.0.2–2.5.0 的 `canWrite()` 判定缺 `exists()` 前置判断，
  覆盖既有文件一律失败；2.5.1 起恢复正常。T3 会先探测本版本行为再按对应判据断言，
  两条分支都应报 6/6。
- **WAR 文件名**：2.0.x–2.3.1 为 `CKFinderJava.war`，2.4+ 为 `CKFinderJava-<版本>.war`，`setup.sh` 按版本推导。

## 3. 容器内布局与对照关系

| 角色 | 容器内路径 | 对外 URL |
|---|---|---|
| CKFinder 连接器 | `webapps/ROOT/` | `/ckfinder/core/connector/java/connector.java` |
| 资源目录（只应写此处） | `webapps/ROOT/Resources/userfiles/` | `/Resources/userfiles/` |
| Images 类型根 | `.../userfiles/images/` | — |
| 穿越目标①：公网可访问目录 | `webapps/ROOT/upload/login/` | `/upload/login/` |
| 穿越目标②：同机其他应用目录 | `webapps/shared/` | `/shared/` |

资源目录之外的路径之所以能通过 HTTP 读到，是因为 `webapps/ROOT` 与 `webapps/shared` 同为
Tomcat 应用 —— 与真实环境中"CKFinder 资源目录之外的静态资源目录 / 同机其他应用"等价。

## 4. 配置基线（官方样例默认）

| 配置项 | 取值 | 说明 |
|---|---|---|
| `<enabled>` | `true` | 官方样例默认 `false`，部署方须手动打开 |
| `<baseDir>` | `webapps/ROOT/Resources/userfiles` | 官方样例中为空，须由部署方填 |
| `baseURL` | `/Resources/userfiles/` | 浏览器侧 URL 前缀，须与 baseDir 对应 |
| `checkAuthentication` | 未覆写 | 官方实现直通 `return true` |
| `accessControls` | 官方样例：`<role>*</role>` 全部 8 项权限 | 未改动 |
| `enableCsrfProtection` | `true`（官方默认） | 双提交 cookie |
| `hideFiles` | `.*`（官方默认） | "点开头名被拒"的来源 |
| 插件 | `imageresize`、`fileeditor` | 官方 `config.xml` 中默认已启用 |

照官方样例启用后，认证检查即直通，`ImageResize` 未认证可用。

`checkAuthentication()` 直通可用官方 jar 的字节码独立确认：

```
$ javap -p -c -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.Configuration
  public boolean checkAuthentication(javax.servlet.http.HttpServletRequest);
      0: iconst_1        // 无条件 true
      1: ireturn
$ javap -p -constants ... IConfiguration
  public static final boolean DEFAULT_CHECKAUTHENTICATION = true;
```

## 5. 部署约束

1. 必须以 ROOT 上下文部署。官方 WAR 的 `WEB-INF/web.xml` 把上下文路径写死在 servlet 映射里
   （`<url-pattern>/ckfinder/core/connector/java/connector.java</url-pattern>`）。放在 `/ckfinder`
   上下文时容器会剥掉 context path，映射变成 `/core/connector/java/connector.java`，与 web.xml
   不匹配，连接器 404。
2. POST 必须带 `CKFinderCommand=true` 作为表单参数（不是请求头）。`ConnectorServlet.checkPostRequest()`
   对原生命令强制校验，缺失时返回 `Error 109`；`QuickUpload` / `FileUpload` 不受此限。
3. 穿越深度：`newFileName` 相对于类型根目录解析。本实验室布局下需 4 层 `../` 才落到 webapp 根；
   差一层会落到不存在的 `webapps/upload` 并以 `Error 104` 失败。深度可用 `diag/probe-depth.py` 标定。
4. 跳板目录必须落在 Web 应用可部署范围内才能被 HTTP 读取；只建空目录而没有 `WEB-INF` 会被
   Tomcat 当作静态目录自动卸载。
5. 不要在容器内用 `pkill -f Bootstrap` 重启 Tomcat —— 容器内 Tomcat 即 PID 1，会被一起杀掉
   导致容器退出。用 `restart-tomcat.sh`。

## 6. PoC 用例与预期

| 用例 | 内容 | 预期（未修复） |
|---|---|---|
| T0 | 匿名 `Init` | `Error 0`（无认证） |
| T1 | `newFileName=xd/../../../../upload/login/poc-public.png` | `Error 0`，落盘 + 匿名 GET 200 |
| T2 | 跨应用写 `xd/../../../../../shared/poc-shared.png` | `Error 0`，落盘 |
| T3 | 覆盖既有 `victim.png`：无 `overwrite` vs `overwrite=1` | 支持覆盖的版本：前者 `Error 115` 且文件不变，后者 `Error 0` 且内容被 PNG 替换；2.0.2–2.5.0 拒绝一切覆盖，判据相应改为"文件未被改动" |
| T4 | 请求尺寸 == 源图尺寸 | 输出与源图 sha256 完全一致（原样字节复制，尾部附加数据保留） |
| T5 | 反证 4 项 | 点开头名→`102`；`.jsp`→`105`；源图不存在→`117`；目录内正常改名→`Error 0` |

判定由 `exploit.py` 自动汇总，退出码非 0 表示存在 FAIL。T1~T4 的穿越层数依赖 `baseDir` 布局，
换部署时需重新标定。

## 7. 其他

- `docker run -p 18080:8080` 绑定所有网卡。若宿主机不可信，改用
  `-p 127.0.0.1:18080:8080` 只监听回环。
- Tomcat 必须为 9.x（javax.servlet）；Tomcat 10+ 是 jakarta.servlet，CKFinder 2.x 无法运行。
- 官方 WAR 自带 `commons-fileupload`、`thumbnailator` 等依赖，无需额外下载。
- 已实测的版本：2.0.2、2.1、2.3.1、2.5.0、2.5.1、2.6.0、2.6.2 —— 均 6/6。
- 官方发行包为 licensed software，本实验室仅用于授权范围内的漏洞研究与报送。
