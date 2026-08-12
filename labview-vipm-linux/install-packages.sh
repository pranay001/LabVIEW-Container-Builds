#!/usr/bin/env bash
set -euo pipefail

PACKAGES_DIR="${PACKAGES_DIR:-/opt/vipm/packages}"
LABVIEW_VERSION="${LABVIEW_VERSION:-2026}"
export VIPM_NONINTERACTIVE="${VIPM_NONINTERACTIVE:-1}"
export VIPM_ASSUME_YES="${VIPM_ASSUME_YES:-1}"
export NO_COLOR="${NO_COLOR:-1}"

setup_display() {
  export DISPLAY="${DISPLAY:-:99}"
  if command -v Xvfb >/dev/null 2>&1 && ! pgrep -x Xvfb >/dev/null 2>&1; then
    Xvfb "$DISPLAY" -screen 0 1280x720x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
  fi
  mkdir -p /tmp/natinst
  echo "1" > /tmp/natinst/LVContainer.txt
}

find_labview() {
  local candidate="/usr/local/natinst/LabVIEW-${LABVIEW_VERSION}-64/labview"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  find /usr/local/natinst /usr /opt -type f -name labview -perm -111 2>/dev/null | head -n 1
}

start_labview() {
  local labview_bin
  labview_bin="$(find_labview || true)"
  if [ -z "$labview_bin" ]; then
    echo "LabVIEW executable was not found; VIPM may fail to install packages." >&2
    return 0
  fi
  if ! pgrep -f "$labview_bin" >/dev/null 2>&1; then
    echo "Starting LabVIEW headless: $labview_bin"
    "$labview_bin" --headless >/tmp/labview-headless.log 2>&1 &
  fi
}

if ! command -v vipm >/dev/null 2>&1; then
  echo "VIPM CLI was not found on PATH." >&2
  exit 1
fi

vip_files=()
while IFS= read -r vip_file; do
  vip_files+=("$vip_file")
done < <(find "$PACKAGES_DIR" -maxdepth 1 -type f -iname '*.vip' | sort)

if [ "${#vip_files[@]}" -eq 0 ]; then
  echo "No .vip files found in $PACKAGES_DIR; nothing to install."
  exit 0
fi

vipm --version || true
setup_display
vipm refresh || vipm update || true

for vip_file in "${vip_files[@]}"; do
  echo "Installing package: $vip_file"
  start_labview
  if vipm install -y "$vip_file" --labview-version "$LABVIEW_VERSION"; then
    continue
  fi
  if vipm install -y "$vip_file"; then
    continue
  fi
  if vipm install "$vip_file" --labview-version "$LABVIEW_VERSION" --yes; then
    continue
  fi
  echo "Failed to install package: $vip_file" >&2
  exit 1
done

vipm list --installed || true
echo "All local .vip packages installed successfully."
