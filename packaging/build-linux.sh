#!/usr/bin/env bash
# Build ClamFox Linux release artifacts: tar.gz, .deb, .rpm and .AppImage.
#
# Usage:
#   packaging/build-linux.sh <version>
#
# Prerequisites (all installed by the GitHub workflow that calls this script):
#   - flutter build linux --release    (already produced build/linux/x64/release/bundle)
#   - dart build cli                   (already produced build/clamfox-helper-cli/bundle/bin/clamfox_helper)
#   - dart run tool/dump_polkit_policy.dart > dist/com.glassfoxowo.clamfox.policy
#   - host tools: dpkg-deb, rpmbuild, curl, file, fakeroot

set -euo pipefail

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/dist"
PKG="${ROOT}/packaging"

NAME="clamfox-${VERSION}-linux-x64"
STAGE="${DIST}/stage/${NAME}"

BUNDLE_SRC="${ROOT}/build/linux/x64/release/bundle"
HELPER_BIN="${ROOT}/build/clamfox-helper-cli/bundle/bin/clamfox_helper"
POLICY_FILE="${DIST}/com.glassfoxowo.clamfox.policy"
ICON_SRC="${ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"

[[ -d "${BUNDLE_SRC}" ]] || { echo "missing Flutter bundle: ${BUNDLE_SRC}" >&2; exit 1; }
[[ -x "${HELPER_BIN}" ]] || { echo "missing helper binary: ${HELPER_BIN}" >&2; exit 1; }
[[ -f "${POLICY_FILE}" ]] || { echo "missing polkit policy: ${POLICY_FILE}" >&2; exit 1; }
[[ -f "${ICON_SRC}" ]] || { echo "missing icon: ${ICON_SRC}" >&2; exit 1; }

echo "==> Staging payload at ${STAGE}"
rm -rf "${DIST}/stage" "${DIST}/deb" "${DIST}/rpm" "${DIST}/AppDir"
mkdir -p "${STAGE}"

cp -a "${BUNDLE_SRC}/." "${STAGE}/bundle/"
install -m 0755 "${HELPER_BIN}"  "${STAGE}/clamfox-helper"
install -m 0644 "${POLICY_FILE}" "${STAGE}/com.glassfoxowo.clamfox.policy"
install -m 0644 "${PKG}/clamfox.desktop" "${STAGE}/clamfox.desktop"
install -m 0644 "${ICON_SRC}" "${STAGE}/clamfox.png"

cat > "${STAGE}/install.sh" <<'EOF'
#!/usr/bin/env bash
# Manual installer for the tar.gz release. Use the .deb/.rpm where possible.
set -euo pipefail
cd "$(dirname "$0")"
sudo install -d -m 755 /usr/lib/clamfox
sudo cp -a bundle/. /usr/lib/clamfox/
sudo install -m 755 clamfox-helper /usr/lib/clamfox/clamfox-helper
sudo install -d /usr/share/applications /usr/share/icons/hicolor/512x512/apps /usr/share/polkit-1/actions
sudo install -m 644 clamfox.desktop /usr/share/applications/clamfox.desktop
sudo install -m 644 clamfox.png /usr/share/icons/hicolor/512x512/apps/clamfox.png
sudo install -m 644 com.glassfoxowo.clamfox.policy /usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy
sudo ln -sf /usr/lib/clamfox/clamfox /usr/bin/clamfox
command -v gtk-update-icon-cache >/dev/null && sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
command -v update-desktop-database >/dev/null && sudo update-desktop-database -q || true
echo "Installed. Launch via 'clamfox' or your application menu."
EOF
chmod +x "${STAGE}/install.sh"

cat > "${STAGE}/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo rm -rf /usr/lib/clamfox
sudo rm -f /usr/bin/clamfox
sudo rm -f /usr/share/applications/clamfox.desktop
sudo rm -f /usr/share/icons/hicolor/512x512/apps/clamfox.png
sudo rm -f /usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy
echo "Uninstalled."
EOF
chmod +x "${STAGE}/uninstall.sh"

cat > "${STAGE}/README" <<EOF
ClamFox ${VERSION} (linux-x64)

Quick install (system-wide):
  ./install.sh

Run without installing:
  ./bundle/clamfox

Uninstall:
  ./uninstall.sh

For Debian/Ubuntu, prefer the .deb. For Fedora/RHEL/openSUSE, prefer the .rpm.
The .AppImage is a single self-contained file that does not require install.
EOF

###############################################################################
# tar.gz
###############################################################################
echo "==> Building tar.gz"
TARBALL="${DIST}/${NAME}.tar.gz"
( cd "${DIST}/stage" && tar -czf "${TARBALL}" "${NAME}" )

###############################################################################
# .deb
###############################################################################
echo "==> Building .deb"
DEB_ROOT="${DIST}/deb/clamfox_${VERSION}_amd64"
mkdir -p "${DEB_ROOT}/DEBIAN" \
         "${DEB_ROOT}/usr/lib/clamfox" \
         "${DEB_ROOT}/usr/bin" \
         "${DEB_ROOT}/usr/share/applications" \
         "${DEB_ROOT}/usr/share/icons/hicolor/512x512/apps" \
         "${DEB_ROOT}/usr/share/polkit-1/actions"

cp -a "${STAGE}/bundle/." "${DEB_ROOT}/usr/lib/clamfox/"
install -m 0755 "${STAGE}/clamfox-helper" "${DEB_ROOT}/usr/lib/clamfox/clamfox-helper"
install -m 0644 "${STAGE}/clamfox.desktop" "${DEB_ROOT}/usr/share/applications/clamfox.desktop"
install -m 0644 "${STAGE}/clamfox.png" "${DEB_ROOT}/usr/share/icons/hicolor/512x512/apps/clamfox.png"
install -m 0644 "${STAGE}/com.glassfoxowo.clamfox.policy" \
        "${DEB_ROOT}/usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy"
ln -sf /usr/lib/clamfox/clamfox "${DEB_ROOT}/usr/bin/clamfox"

INSTALLED_SIZE=$(du -sk "${DEB_ROOT}" | cut -f1)
cat > "${DEB_ROOT}/DEBIAN/control" <<EOF
Package: clamfox
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, libc6, policykit-1 | polkit
Recommends: clamav, clamav-daemon, clamav-freshclam, rkhunter, chkrootkit
Installed-Size: ${INSTALLED_SIZE}
Maintainer: ClamFox Contributors <noreply@github.com>
Homepage: https://github.com/foxderin/ClamFox
Description: Modern ClamAV GUI for Linux
 ClamFox is a Flutter-based desktop graphical interface for the ClamAV
 antivirus engine, with optional rkhunter and chkrootkit integration.
 It provides multi-engine scanning, threat handling, scan history,
 signature updates and a privileged-mode helper backed by polkit.
EOF

cat > "${DEB_ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q || true
fi
EOF
chmod 0755 "${DEB_ROOT}/DEBIAN/postinst"

cat > "${DEB_ROOT}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q /usr/share/icons/hicolor || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q || true
    fi
fi
EOF
chmod 0755 "${DEB_ROOT}/DEBIAN/postrm"

DEB_OUT="${DIST}/clamfox_${VERSION}_amd64.deb"
fakeroot dpkg-deb --build --root-owner-group "${DEB_ROOT}" "${DEB_OUT}"

###############################################################################
# .rpm
###############################################################################
echo "==> Building .rpm"
RPM_TOP="${DIST}/rpm"
mkdir -p "${RPM_TOP}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp "${TARBALL}" "${RPM_TOP}/SOURCES/"

DATE_RPM="$(LC_ALL=C date +'%a %b %d %Y')"
sed -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@DATE@/${DATE_RPM}/g" \
    "${PKG}/clamfox.spec.in" > "${RPM_TOP}/SPECS/clamfox.spec"

rpmbuild --define "_topdir ${RPM_TOP}" \
         --define "_binary_payload w9.gzdio" \
         -bb "${RPM_TOP}/SPECS/clamfox.spec"

# rpm dist tag varies per host (.fc40, .el9, plain). Match anything between
# release number and .x86_64.rpm suffix.
shopt -s nullglob
for rpm in "${RPM_TOP}/RPMS/x86_64/"clamfox-"${VERSION}"-1*.x86_64.rpm; do
  cp "${rpm}" "${DIST}/clamfox-${VERSION}-1.x86_64.rpm"
done
shopt -u nullglob

###############################################################################
# AppImage
###############################################################################
echo "==> Building AppImage"
APPDIR="${DIST}/AppDir"
mkdir -p "${APPDIR}/usr/bin" \
         "${APPDIR}/usr/lib/clamfox" \
         "${APPDIR}/usr/share/applications" \
         "${APPDIR}/usr/share/icons/hicolor/512x512/apps" \
         "${APPDIR}/usr/share/polkit-1/actions"

cp -a "${STAGE}/bundle/." "${APPDIR}/usr/lib/clamfox/"
install -m 0755 "${STAGE}/clamfox-helper" "${APPDIR}/usr/lib/clamfox/clamfox-helper"
install -m 0644 "${STAGE}/com.glassfoxowo.clamfox.policy" \
        "${APPDIR}/usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy"

# AppImage entrypoint visible on PATH inside the image.
cat > "${APPDIR}/usr/bin/clamfox" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/../lib/clamfox/clamfox" "$@"
EOF
chmod +x "${APPDIR}/usr/bin/clamfox"

install -m 0644 "${STAGE}/clamfox.desktop" "${APPDIR}/usr/share/applications/clamfox.desktop"
install -m 0644 "${STAGE}/clamfox.png"     "${APPDIR}/usr/share/icons/hicolor/512x512/apps/clamfox.png"
# linuxdeploy expects the desktop file and icon at the AppDir root too.
cp "${APPDIR}/usr/share/applications/clamfox.desktop" "${APPDIR}/clamfox.desktop"
cp "${APPDIR}/usr/share/icons/hicolor/512x512/apps/clamfox.png" "${APPDIR}/clamfox.png"

LINUXDEPLOY="${DIST}/linuxdeploy-x86_64.AppImage"
GTK_PLUGIN_DIR="${DIST}/linuxdeploy-plugin-gtk"
GTK_PLUGIN="${GTK_PLUGIN_DIR}/linuxdeploy-plugin-gtk.sh"
if [[ ! -x "${LINUXDEPLOY}" ]]; then
  curl -fL --retry 3 -o "${LINUXDEPLOY}" \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x "${LINUXDEPLOY}"
fi
if [[ ! -x "${GTK_PLUGIN}" ]]; then
  mkdir -p "${GTK_PLUGIN_DIR}"
  curl -fL --retry 3 -o "${GTK_PLUGIN}" \
    https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
  chmod +x "${GTK_PLUGIN}"
fi

# Make the GTK plugin discoverable on PATH for linuxdeploy.
export PATH="${GTK_PLUGIN_DIR}:${PATH}"
# Force AppImage tools to extract instead of relying on FUSE in CI.
export APPIMAGE_EXTRACT_AND_RUN=1

(
  cd "${DIST}"
  ARCH=x86_64 \
  OUTPUT="clamfox-${VERSION}-x86_64.AppImage" \
  VERSION="${VERSION}" \
  "${LINUXDEPLOY}" --appdir AppDir \
                   --executable AppDir/usr/lib/clamfox/clamfox \
                   --desktop-file AppDir/clamfox.desktop \
                   --icon-file AppDir/clamfox.png \
                   --plugin gtk \
                   --output appimage
)

echo
echo "==> Built artifacts:"
ls -lh "${DIST}"/*.tar.gz "${DIST}"/*.deb "${DIST}"/*.rpm "${DIST}"/*.AppImage 2>/dev/null || true
