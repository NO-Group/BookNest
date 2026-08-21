import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booknest/config/router.dart';
import 'package:booknest/config/theme.dart';

void main() {
  test('BookNest dark theme uses the N.O deep-blue background and primary', () {
    final theme = BookNestTheme.darkTheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, BookNestColors.bgDark);
    expect(theme.colorScheme.primary, BookNestColors.deepBlueBright);
  });

  test('BookNest light theme uses the N.O white background and deep blue', () {
    final theme = BookNestTheme.lightTheme;

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, BookNestColors.bgLight);
    expect(theme.colorScheme.primary, BookNestColors.deepBlue);
  });

  test('Router boots to the splash screen', () {
    expect(appRouter.initialLocation, '/splash');
  });
}
