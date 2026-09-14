# Official artifact hashes

All hashes are SHA-256. Vendored binaries are not redistributed here; download them from the
vendor's official channel and verify against the values below.

The defective file is:

```
ckfinder/_source/CKFinder for Java/ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java
```

## The defective file across all 20 downloadable Java 2.x releases

The twenty releases reduce to **nine distinct versions** of this file. Every one contains the same
broken guard (`&&` where `||` was intended).

| sha256 | size | versions |
|---|---|---|
| `bbf242dc0e482dcd525f06431babd72a7eeba0d273ef2915e20a781eec421791` | 8,105 B | 2.0.2, 2.0.2.1, 2.1 |
| `61fcf4eee367eb2b017e6cc3a5790f0f634057edd600a6354b6359917d57211d` | 8,105 B | 2.1.1, 2.2, 2.2.1, 2.2.2, 2.3 |
| `3b46f36535a538d76066b82484d9600afbbefb2eaa1fd73522dd91f10d39fe08` | 7,885 B | 2.3.1 |
| `f5fbc042b47a9e95d383ea25412544e78c930a5aec6edc3278d4f90e50d56135` | 7,894 B | 2.4 |
| `a77c6f6e798e9cd5cdcde3de16ca4d16af3c802d25c93bffb245ea015497d95b` | 7,894 B | 2.4.1, 2.4.2 |
| `7bbd4d1b7d560aa99754e7efedb71366d23c3702d64b757bb9a7f0511a55d5c2` | 8,030 B | 2.4.3 |
| `efb4d66e40addbfe65a713a8d08c3d857b3906749bb83a1747985cfa8afe69fa` | 8,030 B | 2.5.0 |
| `6511ec769e8b91dd8946d01fc361d4fb427de50b0c4f39513138f5776336c28d` | 8,040 B | 2.5.1 |
| `6d30f2db787aa0f61b0b77287e73de714018c6814625bda6d2cb9dea564c0d4f` | 8,336 B | **2.6.0, 2.6.1, 2.6.2, 2.6.2.1, 2.6.3** |

The 2.6.x line is byte-identical across all five releases, which is why the 2.6.3 "security release"
(extensionless upload + content sniffing documentation) had no effect on this defect.

Verify any version with:

```bash
V=2.6.3
curl -fsSL -o /tmp/ck.zip \
  "https://download.cksource.com/CKFinder/CKFinder%20for%20Java/$V/ckfinder_java_$V.zip"
unzip -p /tmp/ck.zip '*/ImageResizeCommad.java' | sha256sum
```

## Release archives used for the runtime tests

| Version | WAR SHA-256 | Size |
|---|---|---|
| 2.0.2 | `f301d4c2a205183c41d0cc8112253dfccc85a44d743977705a7147b465c1f7a7` | 1,335,765 B |
| 2.1 | `4856551ede93e720eb1b7f4a83e118547563b137832ed553620414b41a52b2c9` | 2,641,033 B |
| 2.3.1 | `41f6bcbc9acfeff7a9dfb0becc07090c9102dd47480777badeb9377fda4587f4` | 2,759,479 B |
| 2.5.1 | `d83ced2cc56c0384c9aea5703a06fd5b30cc1e7b75482b2daa8afc5109035009` | 3,352,444 B |
| 2.6.0 | `23016d1a33a551e4d39505a14f35c86b5b1f785242b3a519726d31a9d54d56f4` | 3,592,201 B |
| 2.6.2 | `e17ab903aff78efaa88fa252a1708b785c871c1ae0db94f6100644dcd1995a0c` | 3,592,381 B |

`lab/setup.sh` downloads the release archive at build time and aborts if the WAR hash does not match
`EXPECT_WAR_SHA256`. Select a version with:

```bash
docker build --build-arg WAR_VERSION=2.1 \
             --build-arg EXPECT_WAR_SHA256=<hash above> \
             -t ckfinder-lab:2.1 ./lab
```

Note the WAR filename differs by release: 2.0.x–2.3.1 use `CKFinderJava.war`, 2.4+ use
`CKFinderJava-<version>.war`.

## CKFinder 3.x

| Version | SHA-256 | Size |
|---|---|---|
| 3.5.1 jar | `f3135dd103ae2e2beb7b0c299e88a30216b75f9ad5d0030ceabdb2029be96fb8` | 3,463,703 B |

Download: `https://maven.cksource.com/com/cksource/ckfinder3/3.5.1/ckfinder3-3.5.1.jar`

`ImageResize` was rewritten in 3.x: it takes only `fileName` and `size`, and the output name is
derived internally, so the defect does not apply.

## Cross-platform sources

The comparison in the advisory uses these files from the respective 2.6.3 distributions:
`plugins/imageresize/plugin.php`, `ImageResize.cs`, `ImageResize.cfc`, `plugin.asp` and each
platform's `FileSystem`/`Connector` filename check.

## Lab configuration

The sample `WEB-INF/config.xml` ships with `<enabled>false</enabled>` and a warning against
enabling it without session validation. The lab sets `<enabled>true</enabled>`, points `baseDir`
and `baseURL` at a local directory, and leaves `checkAuthentication` unoverridden. Everything
else is the vendor's original configuration.
