import 'dart:ui_web' as ui_web;

void useBrowserHistory() {
  // The workspace reads URL links directly and has no Flutter routes to sync.
  ui_web.urlStrategy = null;
}
