import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../ui/dialogs.dart';

/// Google Play in-app updates. Play also auto-updates the app; this tells users
/// who opened the app that a new version is ready and installs it in place.
/// Does nothing for installs that did not come from Google Play.
class Updates {
  static bool _checking = false;

  static Future<void> check({bool manual = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        if (manual) toast('You are on the latest version');
        return;
      }
      if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) {
          messengerKey.currentState?.showSnackBar(SnackBar(
            content: const Text('Update downloaded'),
            duration: const Duration(days: 1),
            action: SnackBarAction(
              label: 'RESTART',
              onPressed: InAppUpdate.completeFlexibleUpdate,
            ),
          ));
        }
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      if (manual) toast('Updates are delivered through Google Play');
    } finally {
      _checking = false;
    }
  }
}
