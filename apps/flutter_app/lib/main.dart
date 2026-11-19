import 'package:flutter/widgets.dart';

import 'app/browser_history_stub.dart'
    if (dart.library.js_interop) 'app/browser_history_web.dart';
import 'app/prepaid_guard_app.dart';

void main() {
  useBrowserHistory();
  runApp(const PrepaidGuardApp());
}
