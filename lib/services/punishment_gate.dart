import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend_api.dart';

/// The moderator's live hand: when this holds a punishment, the whole
/// app yields to the appeal gate. Checked at startup and re-checked by
/// the notification sweep, so a mid-session suspension lands without a
/// restart — and clears itself the moment it expires or is lifted.
final ValueNotifier<Map<String, dynamic>?> punishmentGate =
    ValueNotifier<Map<String, dynamic>?>(null);

DateTime? _lastCheck;
Timer? _pending;

/// Asks the edge whether the signed-in reader is banned or suspended
/// and updates the gate. Throttled to one call every three minutes;
/// [force] bypasses the throttle (used at startup).
Future<void> refreshPunishmentGate({bool force = false}) async {
  if (!force) {
    final now = DateTime.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < const Duration(minutes: 3)) {
      // Already asked recently — a due re-check is already scheduled.
      return;
    }
    _lastCheck = now;
  } else {
    _lastCheck = DateTime.now();
  }
  try {
    final res = await BackendApi.instance.myStatus();
    final punishment = res?['punishment'];
    punishmentGate.value =
        punishment is Map ? Map<String, dynamic>.from(punishment) : null;
  } catch (_) {
    // Unreachable cloud never locks a reader out on its own.
  } finally {
    // Keep the schedule honest: one re-check lands within the window.
    _pending?.cancel();
    _pending = Timer(const Duration(minutes: 3), () {
      refreshPunishmentGate(force: true);
    });
  }
}
