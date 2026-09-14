# Official artifact hashes used in this analysis

All hashes are SHA-256. Vendored binaries are **not** redistributed in this repository;
download them from the vendor's official channel and verify against the values below.

## CKFinder for Java 2.6.2 (primary reproduction target)

| Artifact | SHA-256 | Size |
|---|---|---|
| `ckfinder_java_2.6.2.zip` | `b3060bb63c74544b4babc57a1ba7355934816e0719805cb0acb27101cee732f4` | 5,904,882 B |
| `CKFinderJava-2.6.2.war` (inside the zip) | `e17ab903aff78efaa88fa252a1708b785c871c1ae0db94f6100644dcd1995a0c` | 3,592,381 B |

Download:
`https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2/ckfinder_java_2.6.2.zip`

`lab/setup.sh` downloads this archive at build time and aborts if the WAR hash does not match
`EXPECT_WAR_SHA256`.

## CKFinder for Java 2.6.2.1

| Artifact | SHA-256 | Size |
|---|---|---|
| `ckfinder_java_2.6.2.1.zip` | `fc64f9de9f575156c85a930520629c46446cc5b5305ac1d032551927d19ff936` | 5,905,084 B |

Download:
`https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2.1/ckfinder_java_2.6.2.1.zip`

## CKFinder for Java 2.6.3 (final 2.6.x release — still affected)

| Artifact | SHA-256 | Size |
|---|---|---|
| `ckfinder_java_2.6.3.zip` | `5f0ed19e6b6007ec15dd0c134af7a7a7aef40d99fdfdb0745daee7bbd6742bc7` | 5,919,911 B |

Download:
`https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.3/ckfinder_java_2.6.3.zip`

## CKFinder 3.x (verified NOT affected)

| Artifact | SHA-256 | Size |
|---|---|---|
| `ckfinder3-3.5.1.jar` | `f3135dd103ae2e2beb7b0c299e88a30216b75f9ad5d0030ceabdb2029be96fb8` | 3,463,703 B |

Download: `https://maven.cksource.com/com/cksource/ckfinder3/3.5.1/ckfinder3-3.5.1.jar`

---

## The defective source file

Path inside every affected distribution:

```
ckfinder/_source/CKFinder for Java/ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java
```

Byte-identical in all three affected versions:

| Version | SHA-256 | Size |
|---|---|---|
| 2.6.2 | `6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f` | 8,336 B |
| 2.6.2.1 | `6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f` | 8,336 B |
| 2.6.3 | `6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f` | 8,336 B |

Verify with:

```bash
unzip -p ckfinder_java_2.6.3.zip \
  '*/ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java' \
  | sha256sum
# expected: 6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f
```

## Default authentication behaviour

`Configuration.checkAuthentication()` in `CKFinder-2.6.2.jar` (inside the WAR) compiles to an
unconditional `return true`:

```
$ javap -p -c -cp CKFinder-2.6.2.jar com.ckfinder.connector.configuration.Configuration
  public boolean checkAuthentication(javax.servlet.http.HttpServletRequest);
      Code:
         0: iconst_1
         1: ireturn
```

## Note on `enabled=false`

The bundled sample `WEB-INF/config.xml` ships with `<enabled>false</enabled>` and carries a
warning against enabling it without implementing session validation. The lab sets
`<enabled>true</enabled>` and leaves `checkAuthentication` unoverridden — i.e. exactly the
configuration a deployer reaches by following the sample — and changes nothing else.
