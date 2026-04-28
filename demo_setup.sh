#!/bin/bash

# ClamFox 演示脚本
# 用于设置和测试 ClamAV 功能

echo "=== ClamFox 演示脚本 ==="
echo ""

# 检查 ClamAV 是否已安装
if ! command -v clamscan &> /dev/null; then
    echo "❌ ClamAV 未安装"
    echo "请运行以下命令安装 ClamAV："
    echo ""
    echo "Ubuntu/Debian:"
    echo "  sudo apt update"
    echo "  sudo apt install clamav clamav-daemon"
    echo ""
    echo "Arch Linux:"
    echo "  sudo pacman -S clamav"
    echo ""
    echo "Fedora/CentOS:"
    echo "  sudo dnf install clamav clamav-update"
    echo ""
    exit 1
fi

echo "✅ ClamAV 已安装"

# 检查数据库
if [ ! -f "/var/lib/clamav/main.cvd" ] && [ ! -f "/var/lib/clamav/main.cld" ]; then
    echo "❌ ClamAV 数据库未安装"
    echo "正在更新数据库..."
    echo "注意：首次下载可能需要较长时间"

    sudo freshclam

    if [ $? -eq 0 ]; then
        echo "✅ 数据库更新成功"
    else
        echo "❌ 数据库更新失败"
        echo "请手动运行: sudo freshclam"
        exit 1
    fi
else
    echo "✅ ClamAV 数据库已安装"
fi

# 创建测试目录和文件
TEST_DIR="$HOME/clamfox_test"
mkdir -p "$TEST_DIR"

echo "创建测试文件..."
echo "This is a normal text file." > "$TEST_DIR/normal.txt"
echo "Another safe file." > "$TEST_DIR/safe.txt"

# 创建 EICAR 测试文件 (标准的无害病毒测试文件)
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$TEST_DIR/eicar.com"

echo ""
echo "✅ 演示环境设置完成"
echo ""
echo "测试目录: $TEST_DIR"
echo "- normal.txt (正常文件)"
echo "- safe.txt (安全文件)"
echo "- eicar.com (EICAR 测试病毒文件)"
echo ""
echo "您现在可以在 ClamFox 中扫描 $TEST_DIR 目录来测试应用功能。"
echo "EICAR 文件是一个标准的无害测试文件，应该会被检测为病毒。"
echo ""
