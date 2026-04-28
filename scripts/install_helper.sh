#!/usr/bin/env bash
# Install the ClamFox privileged-mode service + system authorization policy.
#
# Run from the repo root once after pulling in the privileged-mode change:
#   ./scripts/install_helper.sh
#
# Idempotent: re-running upgrades the binary and policy in place.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${EUID}" -eq 0 ]]; then
  echo "请以普通用户身份运行此脚本，脚本会在需要时调用 sudo。" >&2
  exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
  if [[ -x "${HOME}/.local/share/flutter/bin/dart" ]]; then
    export PATH="${HOME}/.local/share/flutter/bin:${PATH}"
  else
    echo "未找到 dart 命令，请先安装 Flutter / Dart SDK。" >&2
    exit 1
  fi
fi

mkdir -p build

echo "[1/3] 编译特权模式服务 ..."
dart pub get >/dev/null
# Some Flutter deps (objective_c via path_provider) ship build hooks, so use
# `dart build cli` instead of legacy `dart compile exe`. Output is a bundle
# directory containing a single self-contained binary.
rm -rf build/clamfox-helper-cli
dart build cli -o build/clamfox-helper-cli >/dev/null
HELPER_BIN="build/clamfox-helper-cli/bundle/bin/clamfox_helper"
if [[ ! -x "${HELPER_BIN}" ]]; then
  echo "构建失败：未找到 ${HELPER_BIN}" >&2
  exit 1
fi

echo "[2/3] 安装特权模式服务到 /usr/lib/clamfox/ ..."
sudo install -d -m 755 /usr/lib/clamfox
sudo install -m 755 "${HELPER_BIN}" /usr/lib/clamfox/clamfox-helper

echo "[3/3] 安装系统授权策略 ..."
TMP="$(mktemp /tmp/clamfox-policy.XXXXXX.policy)"
trap 'rm -f "${TMP}"' EXIT
dart run tool/dump_polkit_policy.dart >"${TMP}"
sudo install -m 644 "${TMP}" /usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy

echo
echo "完成。重新启动 ClamFox 后即可在「设置 -> 特权模式」启用。"
