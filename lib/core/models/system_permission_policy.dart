enum SystemPermissionPolicy {
  bypass, // 免审批 / 自动允许
  ask,    // 提示审批 / 每次询问
  deny;   // 禁用 / 禁止使用

  static SystemPermissionPolicy fromString(String? val) {
    switch (val) {
      case 'bypass':
        return SystemPermissionPolicy.bypass;
      case 'deny':
        return SystemPermissionPolicy.deny;
      case 'ask':
      default:
        return SystemPermissionPolicy.ask;
    }
  }

  String toStorageString() => name;
}
