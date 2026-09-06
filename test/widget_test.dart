import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booknest/config/router.dart';
import 'package:booknest/config/theme.dart';

void main() {
  test('BookNest dark theme: black background, navy primary, cyan secondary', () {
    final theme = BookNestTheme.darkTheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, BookNestColors.darkBackground);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(theme.colorScheme.primary, BookNestColors.navy);
    expect(theme.colorScheme.primary, const Color(0xFF102A56));
    expect(theme.colorScheme.secondary, BookNestColors.cyan);
    expect(theme.colorScheme.secondary, const Color(0xFF00E5FF));
  });

  test('BookNest light theme: white background, same brand colors', () {
    final theme = BookNestTheme.lightTheme;

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, BookNestColors.lightBackground);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.primary, const Color(0xFF102A56));
    expect(theme.colorScheme.secondary, const Color(0xFF00E5FF));
  });

  test('Router boots to the splash screen', () {
    expect(appRouter.initialLocation, '/splash');
  });
}
