import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booknest/config/theme.dart';
import 'package:booknest/presentation/screens/discover/school_cbt_common.dart';

void main() {
  group('Brand theme', () {
    test('dark theme: near-black background, navy primary, cyan secondary', () {
      final theme = BookNestTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, BookNestColors.darkBackground);
      expect(theme.colorScheme.primary, const Color(0xFF102A56));
      expect(theme.colorScheme.secondary, const Color(0xFF00E5FF));
    });

    test('light theme: white background, same brand colours', () {
      final theme = BookNestTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(theme.colorScheme.primary, const Color(0xFF102A56));
      expect(theme.colorScheme.secondary, const Color(0xFF00E5FF));
    });
  });

  group('CBT import (Excel / CSV paste)', () {
    test('tab-separated rows from Excel, header skipped', () {
      final r = parseCbtCsv(
          'subject\ttopic\tyear\tquestion\tA\tB\tC\tD\tanswer\texplanation\tmarks\n'
          'Maths\tAlgebra\t2024\tSolve 2x = 8\t2\t4\t6\t8\tB\tDivide by 2\t2\n');
      expect(r.errors, isEmpty);
      expect(r.questions, hasLength(1));
      final q = r.questions.single;
      expect(q['type'], 'mcq');
      expect(q['options'], ['2', '4', '6', '8']);
      expect(q['answer'], 1);
      expect(q['marks'], 2);
      expect(q['subject'], 'Maths');
    });

    test('CSV with quotes, commas inside a cell, answer given as text', () {
      final r = parseCbtCsv(
          'English,,2023,"Pick the odd one out, carefully",cat,dog,"car, red",cow,"car, red",\n');
      expect(r.errors, isEmpty);
      expect(r.questions.single['answer'], 2);
      expect(r.questions.single['text'], 'Pick the odd one out, carefully');
    });

    test('empty options + empty answer = theory question', () {
      final r = parseCbtCsv('Biology,Plants,,Explain photosynthesis.,,,,,,Light → sugar,5\n');
      expect(r.questions.single['type'], 'theory');
      expect(r.questions.single['marks'], 5);
    });

    test('bad rows are reported, good rows kept', () {
      final r = parseCbtCsv('Maths,,,1+1?,1,2,,,Z,\n'
          'Maths,,,2+2?,4,5,,,A,\n'
          'Maths,,,,1,2,,,A,\n');
      expect(r.questions, hasLength(1));
      expect(r.errors, hasLength(2));
    });
  });

  test('countdown formatting', () {
    expect(cbtCountdown(const Duration(minutes: 4, seconds: 5)), '04:05');
    expect(cbtCountdown(const Duration(hours: 2, minutes: 3)), '2h 03m');
    expect(cbtCountdown(const Duration(days: 3, hours: 5)), '3d 5h');
    expect(cbtCountdown(const Duration(seconds: -1)), '00:00');
  });
}
