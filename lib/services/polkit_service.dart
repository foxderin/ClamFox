import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'polkit_policy.dart';

class PolkitService {
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final available = await isPolkitAvailable();
      if (!available) {
        throw Exception('系统授权工具 (pkexec) 不可用');
      }
      _isInitialized = true;
      debugPrint('系统授权服务初始化成功');
    } catch (e) {
      debugPrint('系统授权服务初始化失败: $e');
      throw Exception('系统授权初始化失败: $e');
    }
  }

  /// 使用系统授权获取管理员权限并执行命令
  Future<ProcessResult> executeWithPrivileges(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('使用系统授权执行命令: $executable ${arguments.join(' ')}');

      final result = await Process.run('pkexec', [
        executable,
        ...arguments,
      ], workingDirectory: workingDirectory);

      debugPrint('命令执行完成，退出码: ${result.exitCode}');
      return result;
    } catch (e) {
      debugPrint('执行特权命令失败: $e');
      rethrow;
    }
  }

  /// 启动特权进程
  Future<Process> startPrivilegedProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('使用系统授权启动进程: $executable ${arguments.join(' ')}');

      final process = await Process.start('pkexec', [
        executable,
        ...arguments,
      ], workingDirectory: workingDirectory);

      return process;
    } catch (e) {
      debugPrint('启动特权进程失败: $e');
      rethrow;
    }
  }

  /// 检查pkexec是否可用
  static Future<bool> isPolkitAvailable() async {
    try {
      final result = await Process.run('which', ['pkexec']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 测试系统授权权限
  Future<bool> testPolkitAuth() async {
    try {
      final result = await executeWithPrivileges('true', []);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('系统授权权限测试失败: $e');
      return false;
    }
  }

  /// Path the privileged helper binary is installed to.
  static const String helperBinaryPath = kClamfoxHelperBinaryPath;

  /// 创建系统授权策略文件内容
  static String getPolkitPolicyContent() => buildClamfoxPolkitPolicy();

  /// 安装系统授权策略文件
  static Future<bool> installPolkitPolicy() async {
    try {
      final policyContent = getPolkitPolicyContent();
      final tempFile = File('/tmp/clamfox.policy');
      await tempFile.writeAsString(policyContent);

      final result = await Process.run('pkexec', [
        'cp',
        '/tmp/clamfox.policy',
        kClamfoxPolicyFilePath,
      ]);

      if (result.exitCode == 0) {
        await tempFile.delete();
        debugPrint('系统授权策略文件安装成功');
        return true;
      } else {
        debugPrint('系统授权策略文件安装失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('安装系统授权策略文件时出错: $e');
      return false;
    }
  }
}
