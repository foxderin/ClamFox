# ClamFox

ClamFox 是一个面向 Linux 桌面的安全扫描图形界面。它用 Flutter 构建界面，通过 ClamAV、rkhunter 和 chkrootkit 执行病毒扫描、Rootkit 检查、签名更新和威胁处理。

项目当前以 Linux 为主要目标平台；仓库保留了 Flutter 生成的其他平台骨架，但特权扫描、系统包安装和 Polkit helper 主要针对 Linux 桌面环境。

## 功能

- 多引擎扫描：支持 ClamAV 文件/目录扫描，以及 rkhunter、chkrootkit 系统级 Rootkit 检查。
- 扫描配置：可配置递归扫描、压缩包、邮件、PUA 检测、符号链接、最大文件大小、排除路径和排除扩展名。
- 特权模式：通过 Polkit 启动受限 helper，减少反复输入 sudo 密码，并用白名单命令执行需要 root 的操作。
- 威胁处理：支持删除、隔离检测结果，并记录处理状态。
- 扫描历史：保留最近扫描会话、结果、Raw 日志、耗时和取消状态。
- 引擎管理：检测引擎安装状态，支持常见 Linux 发行版的一键安装和数据库/规则更新。
- 桌面体验：Material Design 3 界面、浅色/深色/跟随系统主题、窗口控制和实时扫描日志。

## 系统要求

- Flutter 3.8.1 或更高版本
- Dart SDK 3.8.1 或更高版本
- Linux 桌面环境和 GTK 3 开发运行环境
- 可选扫描引擎：`clamav`、`rkhunter`、`chkrootkit`
- 可选特权支持：`polkit` / `pkexec`

## 安装扫描引擎

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install clamav clamav-daemon clamav-freshclam rkhunter chkrootkit policykit-1
```

Arch Linux:

```bash
sudo pacman -S clamav rkhunter chkrootkit polkit
```

Fedora / RHEL:

```bash
sudo dnf install clamav clamav-update rkhunter chkrootkit polkit
```

openSUSE:

```bash
sudo zypper install clamav rkhunter chkrootkit polkit
```

首次使用前建议更新病毒库和 Rootkit 规则：

```bash
sudo freshclam
sudo rkhunter --update
sudo rkhunter --propupd
```

## 开发运行

```bash
flutter pub get
flutter test
flutter run -d linux
```

构建 Linux 发布包：

```bash
flutter build linux --release
```

Linux 构建会同时编译 `bin/clamfox_helper.dart`，并把 `clamfox-helper` 放到应用 bundle 中，供应用内“安装特权模式服务”流程使用。

## 特权模式 helper

开发环境可直接运行安装脚本：

```bash
./scripts/install_helper.sh
```

脚本会编译 helper，并安装：

- `/usr/lib/clamfox/clamfox-helper`
- `/usr/share/polkit-1/actions/com.glassfoxowo.clamfox.policy`

helper 通过 JSON Lines 与主进程通信，只接受预定义的检测、扫描、更新、安装、删除、移动和取消请求；外部输入会经过 schema 与路径校验，不执行任意命令字符串。

## 常用命令

```bash
flutter analyze
flutter test
dart run tool/dump_polkit_policy.dart
```

## 目录结构

```text
lib/
  data/       扫描引擎、输出解析器和历史记录持久化
  models/     扫描结果、扫描设置和扫描会话模型
  providers/  应用状态、引擎调度、特权模式和威胁处理
  screens/    仪表盘、扫描、历史和设置页面
  services/   Polkit、helper 客户端和窗口控制
  widgets/    可复用界面组件
bin/          ClamFox 特权 helper 入口
scripts/      开发/部署辅助脚本
test/         Widget、服务和解析器测试
```

## 注意事项

- ClamFox 是扫描引擎的图形前端，实际检测能力取决于本机安装的 ClamAV、rkhunter 和 chkrootkit。
- 删除和隔离操作会修改文件系统；在处理系统文件前建议先确认检测结果。
- rkhunter 第一次建立文件属性基线时应在可信、干净的系统状态下执行 `sudo rkhunter --propupd`。

## 许可证

本项目声明为 MIT License。正式发布前建议补充 `LICENSE` 文件。
