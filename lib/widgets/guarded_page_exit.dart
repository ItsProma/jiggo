import 'package:flutter/material.dart';

/// Send the system back button through the same confirmation as the app bar.
mixin GuardedPageExit<T extends StatefulWidget> on State<T> {
  bool _exitAllowed = false, _backPending = false;
  Future<void> guardedBack(Future<void> Function() back) async {
    if (_backPending) return;
    _backPending = true;
    try {
      await back();
    } finally {
      _backPending = false;
    }
  }

  Future<void> finishPageExit() async {
    if (!mounted) return;
    setState(() => _exitAllowed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Widget guardPageExit(Widget child, Future<void> Function() back) => PopScope(
    canPop: _exitAllowed,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) guardedBack(back);
    },
    child: child,
  );
}
