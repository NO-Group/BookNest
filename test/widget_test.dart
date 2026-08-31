import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booknest/config/router.dart';
import 'package:booknest/config/theme.dart';

void main() {
  test('BookNest dark theme uses the dark background and cyan accent', () {
    final theme = BookNestTheme.darkTheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0A0A));
    expect(theme.colorScheme.primary, const Color(0xFF00D4FF));
  });

  test('Router boots to the splash screen', () {
    expect(appRouter.initialLocation, '/splash');
  });
}
