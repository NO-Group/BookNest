#!/usr/bin/env python3
"""BookNest static Dart audit — runs without the Flutter SDK.

Catches the error classes that slipped past brace-balance checks in Aug 2026:
  1. unbalanced brackets / unterminated strings
  2. `const BookNestColors.x` (tokens are static consts; const prefix is illegal)
  3. const expressions whose body contains runtime calls (Theme.of, .withOpacity, ...)
  4. missing imports (theme tokens, material, go_router, supabase, share_plus, kit)
  5. relative imports that don't resolve on disk
  6. package imports not declared in pubspec.yaml
  7. banned APIs: PostgREST `.in(`, Icons.format_header, removed CupertinoPageTransitionsBuilder
  8. CachedNetworkImage( called without a named `imageUrl:` first argument
  9. RefreshIndicator.onRefresh given a synchronous callback

Exit code 0 = clean, 1 = violations found. Usage: python3 tools/dart_static_audit.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = [os.path.join(ROOT, 'lib'), os.path.join(ROOT, 'test')]
DYNAMIC_IN_CONST = re.compile(
    r'\.of\(|withOpacity\(|withValues\(|withAlpha\(|DateTime\.now|\.now\(|\$\{')
# Icon names missing from the user's Flutter SDK — with safe replacements.
BANNED_ICONS = {
    'Icons.shelves_rounded': 'Icons.library_books_rounded',
}
BANNED = [
    (re.compile(r'\.in\('), 'PostgREST .in() does not exist — use .inFilter()'),
    (re.compile(r'Icons\.format_header\b'), 'Icons.format_header does not exist — use Icons.title'),
    (re.compile(r'CupertinoPageTransitionsBuilder'), 'removed from modern Flutter SDK'),
]
MATERIAL_NEED = re.compile(
    r'\b(BuildContext|Widget|StatefulWidget|StatelessWidget|ThemeData|Scaffold|SnackBar|'
    r'RefreshIndicator|TextEditingController|FocusNode|MaterialPageRoute)\b|'
    r'\bColors\.|\bIcons\.|Theme\.of\(|MediaQuery')
GOROUTER_NEED = re.compile(
    r'\b(GoRouter|GoRoute|GoRouterState|StatefulShellRoute|CustomTransitionPage)\b|'
    r'context\.(push|go|pop)\b')
SUPABASE_NEED = re.compile(
    r'\bSupabaseClient\b|\bSupabase\.|Postgrest|AuthException|FunctionsClient')
KIT_NEED = re.compile(
    r'\b(EmptyState|BookNestAvatar|BookCover|SectionHeader|StatTile|'
    r'GlassSheet|GradientButton|TagChip|kBookNestGenres)\b')
SHARE_NEED = re.compile(r'\bShare\.')


def strip_comments_and_strings(src):
    """Return code with comment/string contents blanked (structure preserved)."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                out[k] = '\n' if src[k] == '\n' else ' '
            i = j
        elif src[i] in ('"', "'"):
            q = src[i:i + 3] if src[i:i + 3] in ("'''", '"""') else src[i]
            j = i + len(q)
            while j < n:
                if src[j] == '\\':
                    out[j] = ' '
                    if j + 1 < n:
                        out[j + 1] = ' '
                    j += 2
                    continue
                if src.startswith(q, j):
                    break
                if out[j] != '\n':
                    out[j] = ' '
                j += 1
            for k in range(i, min(j + len(q), n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + len(q)
        else:
            i += 1
    return ''.join(out)


def brackets_balanced(code):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    for ch in code:
        if ch in '([{':
            stack.append(ch)
        elif ch in ')]}':
            if not stack or stack[-1] != pairs[ch]:
                return False
            stack.pop()
    return not stack


def pubspec_packages():
    deps = set()
    with open(os.path.join(ROOT, 'pubspec.yaml')) as f:
        content = f.read()
    own = re.search(r'^name:\s*(\S+)', content, re.M)
    if own:
        deps.add(own.group(1))
    for section in ('dependencies:', 'dev_dependencies:'):
        idx = content.find(section)
        if idx == -1:
            continue
        for line in content[idx:].split('\n')[1:]:
            if line and not line.startswith(' '):
                break
            m = re.match(r'\s{2}([a-z_0-9]+):', line)
            if m:
                deps.add(m.group(1))
    return deps | {'flutter'}


def theme_import_ok(path, src):
    for m in re.finditer(r"^import\s+'([^']+\.dart)'", src, re.M):
        imp = m.group(1)
        if imp.startswith('package:'):
            if imp.startswith('package:booknest/config/theme.dart'):
                return True
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(path), imp))
        if target == os.path.join(ROOT, 'lib', 'config', 'theme.dart'):
            return True
    return False


def ui_import_ok(path, src, suffix):
    for m in re.finditer(r"^import\s+'([^']+\.dart)'", src, re.M):
        imp = m.group(1)
        if imp.endswith(suffix):
            if imp.startswith('package:'):
                return True
            target = os.path.normpath(os.path.join(os.path.dirname(path), imp))
            if os.path.exists(target):
                return True
    return False


def check_file(path, packages, violations):
    rel = os.path.relpath(path, ROOT)
    with open(path) as f:
        src = f.read()
    code = strip_comments_and_strings(src)

    if not brackets_balanced(code):
        violations.append(f'{rel}: unbalanced brackets')

    if 'const BookNestColors.' in code:
        violations.append(f'{rel}: const BookNestColors.x is illegal (drop the const)')

    # const regions containing runtime calls
    for m in re.finditer(r'\bconst\b', code):
        j = m.end()
        while j < len(code) and code[j] in ' \t\n':
            j += 1
        m2 = re.match(r'[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*', code[j:])
        if m2 and j + m2.end() < len(code) and code[j + m2.end()] in '([':
            depth = 0
            k = j + m2.end()
            open_ch = code[k]
            close_ch = {'(': ')', '[': ']'}[open_ch]
            while k < len(code):
                if code[k] in '([{':
                    depth += 1
                elif code[k] in ')]}':
                    depth -= 1
                    if depth == 0 and code[k] == close_ch:
                        break
                k += 1
            region = code[j + m2.end():k + 1]
            if DYNAMIC_IN_CONST.search(region):
                line = src.count('\n', 0, m.start()) + 1
                violations.append(
                    f'{rel}:{line}: const region contains runtime calls '
                    f'(remove const)')

    for pattern, why in BANNED:
        for m in pattern.finditer(code):
            line = src.count('\n', 0, m.start()) + 1
            violations.append(f'{rel}:{line}: banned API — {why}')

    for icon, replacement in BANNED_ICONS.items():
        for m in re.finditer(re.escape(icon) + r'\b', code):
            line = src.count('\n', 0, m.start()) + 1
            violations.append(
                f'{rel}:{line}: {icon} does not exist in the target SDK — '
                f'use {replacement}')

    # import requirements (code only, comments/strings blanked)
    def need(cond, what, suffix=None):
        if not cond:
            return
        if suffix is None:
            if not material_imported:
                violations.append(f'{rel}: uses {what} without material import')
        elif not ui_import_ok(path, src, suffix):
            violations.append(f'{rel}: uses {what} without matching import')

    material_imported = re.search(r"^import\s+'package:flutter/material\.dart';", src, re.M)
    imports_all = re.findall(r"^import\s+'([^']+\.dart)'", src, re.M)
    need(MATERIAL_NEED.search(code), 'material widgets', None)
    need(GOROUTER_NEED.search(code), 'go_router', 'go_router.dart')
    need(SUPABASE_NEED.search(code), 'supabase', 'supabase_flutter.dart') if False else None
    if SUPABASE_NEED.search(code):
        if not any(imp.endswith('supabase_flutter.dart') for imp in imports_all):
            violations.append(f'{rel}: uses supabase without supabase_flutter import')
    if SHARE_NEED.search(code):
        if not any(imp.endswith('share_plus.dart') for imp in imports_all):
            violations.append(f'{rel}: uses Share without share_plus import')
    if 'SvgPicture' in code and not ui_import_ok(path, src, 'flutter_svg.dart'):
        violations.append(f'{rel}: uses SvgPicture without flutter_svg import')
    if 'CachedNetworkImage' in code and not ui_import_ok(path, src, 'cached_network_image.dart'):
        violations.append(f'{rel}: uses CachedNetworkImage without its import')
    if re.search(r'\bBookNestColors\b|\bBookNestTheme\b', code) and \
            os.path.basename(path) != 'theme.dart' and not theme_import_ok(path, src):
        violations.append(f'{rel}: uses BookNestColors without theme.dart import')
    if path != os.path.join(ROOT, 'lib', 'presentation', 'components', 'booknest_ui.dart') \
            and KIT_NEED.search(code) and not ui_import_ok(path, src, 'booknest_ui.dart'):
        violations.append(f'{rel}: uses UI kit without booknest_ui import')

    # relative imports must resolve
    for m in re.finditer(r"^import\s+'(\.[^']+)';", src, re.M):
        target = os.path.normpath(os.path.join(os.path.dirname(path), m.group(1)))
        if not os.path.exists(target):
            violations.append(f'{rel}: broken relative import {m.group(1)}')

    # package imports must be declared
    for m in re.finditer(r"^import\s+'package:([a-z_0-9]+)/", src, re.M):
        if m.group(1) not in packages:
            violations.append(f'{rel}: package {m.group(1)} not in pubspec.yaml')

    # await inside a sync arrow closure — setState(() => x = await y)
    for m in re.finditer(r'\(\(\) *=>[^;\n]*\bawait\b', code):
        line = src.count('\n', 0, m.start()) + 1
        violations.append(
            f'{rel}:{line}: await inside a sync arrow closure — hoist the '
            f'future above the closure')

    # switch case on a bare lowercase identifier — not a constant pattern
    for m in re.finditer(r'^[ \t]*case ([a-z_]\w*):', code, re.M):
        if m.group(1) not in ('true', 'false', 'null'):
            line = src.count('\n', 0, m.start()) + 1
            violations.append(
                f'{rel}:{line}: case {m.group(1)}: is not a constant — use '
                f'if/else with identical()')

    # .or(/.inFilter( AFTER .limit( in the same statement — PostgREST
    # transform builders are terminal; filters must come first
    for m in re.finditer(r'\.limit\(', code):
        end = min(m.start() + 140, len(code))
        semi = code.find(';', m.start(), end)
        if semi != -1:
            end = semi
        segment = code[m.start():end]
        if '.or(' in segment or '.inFilter(' in segment:
            line = src.count('\n', 0, m.start()) + 1
            violations.append(
                f'{rel}:{line}: filter after .limit( — .or()/.inFilter() '
                f'must precede terminal .limit()')

    # `x is Map && x[...]` on a typed nullable (maybeSingle result) —
    # promotion is unreliable there; use x != null &&
    for m in re.finditer(r'= await[^;]*\.maybeSingle\(\);', code):
        window = code[m.end():m.end() + 300]
        wm = re.search(r'\bis Map && \w+\[', window)
        if wm:
            line = src.count('\n', 0, m.start()) + 1
            violations.append(
                f'{rel}:{line}: use x != null && instead of is Map && for a '
                f'nullable maybeSingle result')

    # CachedNetworkImage positional guard
    for m in re.finditer(r'CachedNetworkImage\(', code):
        rest = code[m.end():m.end() + 40].lstrip()
        if not rest.startswith('imageUrl'):
            line = src.count('\n', 0, m.start()) + 1
            violations.append(f'{rel}:{line}: CachedNetworkImage needs named imageUrl:')

    # onRefresh must be async
    for m in re.finditer(r'onRefresh:\s*([^,\n]+)', code):
        expr = m.group(1).strip()
        if expr.startswith('('):
            continue
        if not re.search(r'Future<[^>]*>\s*' + re.escape(expr) + r'\b', code):
            line = src.count('\n', 0, m.start()) + 1
            violations.append(
                f'{rel}:{line}: onRefresh: {expr} is not Future-returning — wrap async')


def main():
    packages = pubspec_packages()
    violations = []
    for scan_dir in SCAN_DIRS:
        for root, _, files in os.walk(scan_dir):
            for f in sorted(files):
                if f.endswith('.dart'):
                    check_file(os.path.join(root, f), packages, violations)

    print(f'BookNest static audit — {len(violations)} violation(s)')
    for v in violations:
        print('  ✗ ' + v)
    if violations:
        sys.exit(1)
    print('  ✅ all checks passed')


if __name__ == '__main__':
    main()
