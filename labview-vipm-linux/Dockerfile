# syntax=docker/dockerfile:1.7
# =============================================================================
# LabVIEW Linux + VIPM, with local .vip packages baked in
# =============================================================================
# Standalone, fresh build -- NOT wired into this repo's GitHub Actions worker
# pipeline under .github/. Starts from the official NI LabVIEW Linux
# container, installs native VIPM, then installs every *.vip file found in
# ./packages directly into the image.
# =============================================================================
FROM nationalinstruments/labview:latest-linux

ARG VIPM_DEB_URL=https://traffic.libsyn.com/secure/jkinc/vipm_26.3.0-3954_amd64.deb
ARG LABVIEW_VERSION=2026

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl xvfb \
      fonts-dejavu-core fonts-liberation fonts-noto-core xfonts-base xfonts-75dpi xfonts-100dpi fontconfig; \
    fc-cache -f >/dev/null 2>&1 || true; \
    curl -fL --retry 3 --retry-delay 2 -o /tmp/vipm.deb "${VIPM_DEB_URL}"; \
    dpkg -i /tmp/vipm.deb || apt-get install -f -y --no-install-recommends; \
    rm -f /tmp/vipm.deb; \
    rm -rf /var/lib/apt/lists/*; \
    command -v vipm; \
    vipm --version || true

COPY packages/ /opt/vipm/packages/
COPY install-packages.sh /opt/vipm/install-packages.sh

RUN chmod +x /opt/vipm/install-packages.sh \
 && LABVIEW_VERSION="${LABVIEW_VERSION}" /opt/vipm/install-packages.sh

LABEL labview-vipm.platform=linux
