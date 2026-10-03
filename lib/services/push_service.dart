import 'package:flutter/foundation.dart';

import 'backend_api.dart';

/// Push, the BookNest way: no third-party push vendor. Alerts are
/// delivered in-app (polling + local notifications), which cannot break
/// when an external service is down and costs nothing. FCM was deferred
/// by product decision and is now fully removed — this class keeps the
/// same surface so callers never changed.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _configured = false;

  /// Push kept its old name for compatibility. In-app delivery is
  /// always available.
  bool get available => _configured;

  Future<void> warmUp() async {
    // Nothing external to initialize — in-app notifications are wired
    // by NotificationService at startup.
    _configured = true;
  }

  /// Kept for the account-deletion flow; nothing external to undo.
  Future<void> tearDown() async {}

  @visibleForTesting
  void debugConfigure() => _configured = true;
}
