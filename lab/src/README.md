# Optional: offline / air-gapped build

This directory is empty by design. CKFinder is commercial software by CKSource and is
not redistributed in this repository.

By default, `lab/setup.sh` downloads the official archive during `docker build` and verifies
the WAR against a pinned SHA-256 (see [`../../ADVISORY-hashes.md`](../../ADVISORY-hashes.md)):

```
https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2/ckfinder_java_2.6.2.zip
```

## If you cannot reach download.cksource.com

Download the official archive yourself, extract the WAR, and place it here as
`CKFinderJava-2.6.2.war` before building:

```bash
curl -fsSL -o ckfinder_java_2.6.2.zip \
  "https://download.cksource.com/CKFinder/CKFinder%20for%20Java/2.6.2/ckfinder_java_2.6.2.zip"

unzip -j ckfinder_java_2.6.2.zip '*/CKFinderJava-2.6.2.war' -d .

sha256sum CKFinderJava-2.6.2.war
# expected: e17ab903aff78efaa88fa252a1708b785c871c1ae0db94f6100644dcd1995a0c
```

Then build normally — `setup.sh` will pick up the local file:

```bash
docker build -t ckfinder-lab:2.6.2 .
```

Alternatively, mount a directory containing the WAR at `/opt/ckfinder-pkgs/` in the container.

Anything placed here other than this README is ignored by `.gitignore` (`lab/src/*` with
`!lab/src/README.md`), so the WAR cannot be committed by accident.
