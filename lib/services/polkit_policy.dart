// Pure-Dart polkit policy XML and constants. No Flutter imports — usable
// by both the runtime PolkitService (Flutter app) and the standalone CLI
// `tool/dump_polkit_policy.dart` used by scripts/install_helper.sh.

/// Filesystem path the privileged helper binary is installed to. Hardcoded
/// so the polkit action's `org.freedesktop.policykit.exec.path` annotation
/// can pin it.
const String kClamfoxHelperBinaryPath = '/usr/lib/clamfox/clamfox-helper';

/// Polkit action id for the helper-launch authorization.
const String kClamfoxHelperActionId = 'com.glassfoxowo.clamfox.helper';

/// Polkit action id for legacy ad-hoc admin tasks (sudo/pkexec wrappers).
const String kClamfoxAdminActionId = 'com.glassfoxowo.clamfox.admin';

/// Filesystem path the policy file is installed to.
const String kClamfoxPolicyFilePath =
    '/usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy';

String buildClamfoxPolkitPolicy() {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>GlassFoxOwo</vendor>
  <vendor_url>https://github.com/foxderin/ClamFox</vendor_url>

  <action id="$kClamfoxAdminActionId">
    <description>Run ClamFox administrative tasks</description>
    <description xml:lang="zh_CN">运行 ClamFox 管理任务</description>
    <message>Authentication is required to run ClamFox administrative tasks</message>
    <message xml:lang="zh_CN">需要验证身份以运行 ClamFox 管理任务</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
  </action>

  <action id="$kClamfoxHelperActionId">
    <description>Launch ClamFox privileged mode service</description>
    <description xml:lang="zh_CN">启动 ClamFox 特权模式服务</description>
    <message>Authentication is required to scan the system and manage engines</message>
    <message xml:lang="zh_CN">需要管理员权限以扫描系统并管理引擎</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$kClamfoxHelperBinaryPath</annotate>
  </action>
</policyconfig>''';
}
