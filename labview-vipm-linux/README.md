# LabVIEW Linux + VIPM image

A standalone Dockerfile that builds a LabVIEW Linux image with native VIPM
installed, plus any `.vip` packages you drop into [packages/](packages/)
baked in at build time.

This is **not** wired into this repo's GitHub Actions worker pipeline under
`.github/` — it's a self-contained build you can run locally with a plain
`docker build`.

## What it does

1. Starts from the official `nationalinstruments/labview:latest-linux` image.
2. Installs native VIPM from JKI's `.deb` package.
3. Copies everything in [packages/](packages/) into the image and runs
   [install-packages.sh](install-packages.sh), which installs every `.vip`
   file found there via `vipm install`.

If `packages/` has no `.vip` files, the build still succeeds — you just get
LabVIEW + VIPM with nothing extra installed.

## Prerequisites

- Docker, with the daemon set to **Linux containers** (this base image is
  Linux-only; on Windows/Docker Desktop, switch out of Windows container
  mode first).
- Enough disk space for the NI LabVIEW base image (several GB).

## Usage

1. Drop your `.vip` file(s) into [packages/](packages/).
2. Build the image from inside this folder (so `packages/` is in the build
   context):

   ```bash
   cd labview-vipm-linux
   docker build -t labview-vipm-linux:dev .
   ```

3. Watch the build logs — each package install step prints
   `Installing package: /opt/vipm/packages/<name>.vip`, and the final step
   prints the full `vipm list --installed` output so you can confirm what
   made it into the image.

To build without Docker BuildKit's newer syntax features, drop the
`# syntax=` line at the top of the [Dockerfile](Dockerfile); it's optional
and only pins a Dockerfile frontend version.

### Overriding the VIPM version or LabVIEW version

Both are build args:

```bash
docker build \
  --build-arg VIPM_DEB_URL=https://example.com/path/to/vipm.deb \
  --build-arg LABVIEW_VERSION=2025 \
  -t labview-vipm-linux:dev .
```

`LABVIEW_VERSION` controls where the script looks for the LabVIEW
executable (`/usr/local/natinst/LabVIEW-<version>-64/labview`) and which
`--labview-version` flag it passes to `vipm install`. It falls back to
searching `/usr/local/natinst`, `/usr`, and `/opt` if the expected path
isn't found, so it's usually safe to leave at the default.

## Publishing to GHCR

[publish.ps1](publish.ps1) builds this folder and pushes it straight to
`ghcr.io/<Owner>/<ImageName>` from your machine — no GitHub Actions involved.

```powershell
cd labview-vipm-linux
./publish.ps1 -Owner <your-github-username-or-org>
```

That pushes `:latest` and `:dev`. Pass `-Tag v1` to publish under a
different tag, or `-Login` on the first run to be prompted for a GitHub PAT
(needs the `write:packages` scope) and log in to `ghcr.io` before building —
skip `-Login` on later runs once you're already authenticated. `-VipmDebUrl`
and `-LabviewVersion` forward to the matching Dockerfile build args. See the
script's header comment (`Get-Help ./publish.ps1 -Full`) for every option.

New GHCR packages are private by default; manage visibility from your
GitHub profile/org **Packages** tab.

## Troubleshooting

- **`VIPM CLI was not found on PATH.`** — the `.deb` install step earlier in
  the Dockerfile failed silently; check the `apt-get`/`dpkg` output higher
  in the build log.
- **A specific `.vip` fails to install** — the build fails fast on the first
  failing package so you can see exactly which one and why. Re-run with only
  that package in `packages/` to isolate it.
- **VIPM can't reach a running LabVIEW instance** — the script starts
  LabVIEW headless (`labview --headless`) and Xvfb automatically before each
  install; if this still fails, check `/tmp/labview-headless.log` and
  `/tmp/xvfb.log` inside a debug container (`docker build --target` isn't
  available here since this is a single-stage build — instead, comment out
  the failing `RUN` temporarily and `docker run -it <partial-image> bash` to
  poke around).

## Notes

- This mirrors the VIPM-install pattern used elsewhere in this repo (see
  [.github/docker/labview-ci-linux.Dockerfile](../.github/docker/labview-ci-linux.Dockerfile)
  and [.github/labview/vipm/install-vipc-linux.sh](../.github/labview/vipm/install-vipc-linux.sh)),
  simplified to install raw `.vip` files directly instead of resolving a
  `.vipc` dependency list.
- VIPM Community Edition only needs a `.vip` file itself to install it — no
  license activation or network index lookup required for local files. If
  you're installing packages that require a VIPM Pro license, you'll need to
  add an activation step (see the `vipm activate` handling in
  [install-vipc-linux.sh](../.github/labview/vipm/install-vipc-linux.sh) for
  the pattern).
