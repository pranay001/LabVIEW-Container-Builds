# LabVIEW Windows + VIPM image

A standalone Dockerfile that builds a LabVIEW Windows image with VIPM
installed, plus any `.vip` packages you drop into [packages/](packages/)
baked in at build time. Windows counterpart of
[../labview-vipm-linux/](../labview-vipm-linux/).

This is **not** wired into this repo's GitHub Actions worker pipeline under
`.github/` — it's a self-contained build you run locally with a plain
`docker build`.

## What it does

1. Starts from `nationalinstruments/labview:latest-windows`.
2. Downloads and silently installs VIPM (`/exenoui /qn`).
3. Copies everything in [packages/](packages/) into the image and runs
   [install-packages.ps1](install-packages.ps1), which installs every `.vip`
   file found there.

If `packages/` has no `.vip` files, the build still succeeds — you just get
LabVIEW + VIPM with nothing extra installed.

## Prerequisites

- Docker Desktop set to **Windows containers** (switch out of Linux
  container mode first).
- Enough disk space for the NI LabVIEW base image (the finished image is
  ~20 GB).

## Usage

1. Drop your `.vip` file(s) into [packages/](packages/).
2. Build from inside this folder (so `packages/` is in the build context):

   ```powershell
   cd labview-vipm-windows
   docker build -t labview-vipm-windows:dev .
   ```

A successful build ends with:

```
=== Installing: your_package-1.2.3.4.vip ===
Adding 1 local package to VIPM library...
Using LabVIEW 2026 (64-bit)
Installing 1 package...
Successfully installed 1 package:
  your_package (your_package v1.2.3.4)

=== Installed packages ===
Installed packages (1):
  your_package v1.2.3.4
```

### Build args

```powershell
docker build `
  --build-arg VIPM_INSTALLER_URL=https://example.com/vipm-setup.exe `
  --build-arg LABVIEW_VERSION=2025 `
  --build-arg LABVIEW_BITNESS=64 `
  -t labview-vipm-windows:dev .
```

`LABVIEW_VERSION` must match the LabVIEW year actually in the base image.

## Publishing to GHCR

[publish.ps1](publish.ps1) builds this folder and pushes it straight to
`ghcr.io/<Owner>/<ImageName>` from your machine — no GitHub Actions involved.

```powershell
cd labview-vipm-windows
./publish.ps1 -Owner <your-github-username-or-org>
```

That pushes `:latest` and `:dev`. Pass `-Tag v1` to publish under a
different tag, or `-Login` on the first run to be prompted for a GitHub PAT
(needs the `write:packages` scope) and log in to `ghcr.io` before building —
skip `-Login` on later runs once you're already authenticated.
`-VipmInstallerUrl`, `-LabviewVersion`, and `-LabviewBitness` forward to the
matching Dockerfile build args. See the script's header comment
(`Get-Help ./publish.ps1 -Full`) for every option.

Checks up front that Docker Desktop is in **Windows** container mode and
fails with a clear message if not. New GHCR packages are private by
default; manage visibility from your GitHub profile/org **Packages** tab.

## How headless VIPM installs actually work here

Getting `vipm install` to work non-interactively in a fresh Windows
container needs these four steps **in this order**. This was established by
testing against the real image (VIPM 26.3.0 + LabVIEW 2026, Server Core),
not from documentation:

1. **Seed `C:\ProgramData\JKI\VIPM\Settings.ini`** — a fresh image never
   launched VIPM interactively, so the file doesn't exist and `vipm.exe`
   aborts with `IO error: Failed to load ...Settings.ini ... (os error 2)`.
2. **Run one `vipm list --installed` *before* launching VIPM Desktop.**
   This is the non-obvious one. It initializes the VIPM database — you'll
   see it report `No VIPM database found for LabVIEW <ver>` the first time,
   which is the call doing its job. **If VIPM Desktop starts without this,
   it never completes its startup handshake and every install hangs** at
   `Adding N local package(s) to VIPM library...` until the timeout:
   ```
   error: Failed to add packages to VIPM library:
          Operation 'wait for VIPM startup' timed out after 899.99s
   ```
   Verified: the identical script minus this one call fails every time;
   with it, the install succeeds.
3. **Launch LabVIEW headless** and wait for VI Server on port 3363 —
   packages install *into* a running LabVIEW.
4. **Launch VIPM Desktop** (`VI Package Manager.exe`) and give it time —
   `vipm.exe` delegates the actual install to it.

Then install with `--labview-version` / `--labview-bitness`, which are
**global** options and must **precede** the `install` subcommand.

### What is NOT needed

Verified unnecessary for installing local `.vip` files — don't add these
chasing a hang:

- `git` on `PATH`
- a public-Git-repository working directory
- `vipm refresh --force`
- `GITHUB_*` / `CI` environment variables
- VIPM **Pro** activation — Community Edition installs local `.vip` files
  fine, with no serial number

(Several of these *are* required by
[.github/labview/vipm/install-vipc.ps1](../.github/labview/vipm/install-vipc.ps1),
but that script resolves `.vipc` dependency lists **by name against public
indexes**, which is a different code path. Installing a local `.vip` file
by path doesn't touch package discovery or the Community Edition
public-repo gate.)

## Troubleshooting

- **Hangs at `Adding 1 local package to VIPM library...`** — almost always
  step 2 above being skipped or having failed. Check the build log for the
  `[2/4] Initializing the VIPM database` line and the
  `No VIPM database found` warning right after it.
- **`VIPM CLI (vipm.exe) was not found...`** — the VIPM installer layer
  failed; check its output higher in the build log.
- **A `.vip` fails to install** — the build stops at the first failure. The
  script runs with `-v`, so VIPM prints live status; re-run with only that
  package in `packages/` to isolate it.
- **Transient wedge** — if an install fails, the script kills and relaunches
  the LabVIEW + VIPM Desktop stack (re-running step 2 first) and retries, up
  to `VIPM_MAX_ENGINE_RESTARTS` (default 2). Set it to `0` to fail fast.
- **`VIPM_TIMEOUT`** (default 600s) bounds each `vipm` operation. Lower it
  while debugging so a wedge surfaces in a minute instead of ten.

## Notes

- Unlike the Linux image, Windows has no `labview` vs `labviewprofull`
  binary-path gotcha — `LabVIEW.exe` under
  `C:\Program Files\National Instruments\LabVIEW <year>\` is the real
  executable, used directly by `LabVIEWCLI -LabVIEWPath`.
- The `vipm.exe` shipped by VIPM 26.3 lives at
  `C:\Program Files\JKI\VI Package Manager\support\vipm.exe`. Despite the
  legacy-looking path, it is the modern Rust CLI (`vipm 26.3.0`).
