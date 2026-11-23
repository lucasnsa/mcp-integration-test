import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// Test-only platform implementations. No native dialogs or settings are opened.
class DemoPluginMocks {
  final sharePlatform = DemoSharePlatform();
  final permissions = DemoPermissionPlatform();
  PermissionHandlerPlatform? _previousPermissions;

  SharePlus get share => SharePlus.custom(sharePlatform);

  void install() {
    _previousPermissions = PermissionHandlerPlatform.instance;
    PermissionHandlerPlatform.instance = permissions;
    PackageInfo.setMockInitialValues(
      appName: 'MCP Playground',
      packageName: 'dev.example.mcp_playground',
      version: '2.3.4',
      buildNumber: '42',
      buildSignature: 'demo',
    );
  }

  void restore() {
    if (_previousPermissions != null) {
      PermissionHandlerPlatform.instance = _previousPermissions!;
      _previousPermissions = null;
    }
  }
}

class DemoSharePlatform extends SharePlatform {
  final requests = <ShareParams>[];
  final outcomes = <ShareResultStatus>[
    ShareResultStatus.success,
    ShareResultStatus.dismissed,
    ShareResultStatus.unavailable,
  ];

  @override
  Future<ShareResult> share(ShareParams params) async {
    requests.add(params);
    final status = outcomes[(requests.length - 1) % outcomes.length];
    return ShareResult('demo', status);
  }
}

class DemoPermissionPlatform extends PermissionHandlerPlatform {
  PermissionStatus status = PermissionStatus.denied;
  final outcomes = <PermissionStatus>[
    PermissionStatus.denied,
    PermissionStatus.granted,
    PermissionStatus.permanentlyDenied,
  ];
  final requests = <List<Permission>>[];
  int settingsOpened = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (permission != Permission.camera) {
      throw UnsupportedError('Only camera is configured in this demo');
    }
    return status;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    if (permissions.any((permission) => permission != Permission.camera)) {
      throw UnsupportedError('Only camera is configured in this demo');
    }
    requests.add(List.of(permissions));
    status = outcomes[(requests.length - 1) % outcomes.length];
    return {for (final permission in permissions) permission: status};
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}
