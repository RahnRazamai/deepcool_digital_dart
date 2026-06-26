import 'dart:convert';
import 'dart:io';

import 'mode.dart';

// Shared GUI/daemon config stored in the user's XDG config directory.
final class AppConfig {
  final String daemonPath;
  final bool autostartUser;
  final DisplayMode displayMode;

  const AppConfig({
    required this.daemonPath,
    this.autostartUser = false,
    this.displayMode = DisplayMode.cpuFrequency,
  });

  Map<String, dynamic> toJson() => {
    'daemonPath': daemonPath,
    'autostartUser': autostartUser,
    'displayMode': displayMode.symbol,
  };

  static Future<AppConfig> load() async {
    final cfgFile = File('${_configDirPath()}/config.json');
    try {
      if (await cfgFile.exists()) {
        final text = await cfgFile.readAsString();
        final m = jsonDecode(text) as Map<String, dynamic>;
        return AppConfig(
          daemonPath: m['daemonPath'] ?? '/usr/bin/deepcool-digital-dart',
          autostartUser: m['autostartUser'] ?? false,
          displayMode:
              DisplayModeSymbols.parse(m['displayMode']?.toString() ?? '') ??
              DisplayMode.cpuFrequency,
        );
      }
    } catch (_) {}
    return const AppConfig(daemonPath: '/usr/bin/deepcool-digital-dart');
  }

  Future<void> save() async {
    final dir = Directory(_configDirPath());
    await dir.create(recursive: true);
    final cfgFile = File('${dir.path}/config.json');
    await cfgFile.writeAsString(jsonEncode(toJson()));
  }
}

String _configDirPath() {
  final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
  if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
    return '$xdgConfigHome/deepcool-desktop';
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return '$home/.config/deepcool-desktop';
  }

  return '${Directory.current.path}/.config/deepcool-desktop';
}
