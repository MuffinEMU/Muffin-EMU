#!/usr/bin/env python3
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team (Void).
# SPDX-License-Identifier: GPL-3.0-only
"""Lists every English string the app shows, the keys of App/Localization/*.lproj/Localizable.strings.

A string counts when it is a plain literal (no interpolation) in a place SwiftUI looks up on its own
(Text("..."), Label("...", ...), Button("..."), .navigationTitle("..."), ...), or a literal followed
by .localized, or String(localized: "..."). Everything else stays as written.

    extract.py                 writes l10n/keys.json (sorted keys) and prints the count
    extract.py --check         also lists UI literals with interpolation, which can't be looked up
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "App")

# A Swift string literal, single-line: "..." with escapes.
LIT = r'"((?:[^"\\\n]|\\.)*)"'
SWIFTUI = (r'(?:\bText|\bLabel|\bButton|\bToggle|\bPicker|\bSection|\bMenu|\bDisclosureGroup|\bTextField|'
           r'\bSecureField|\bLink|\bStepper|\bProgressView|\bNavigationLink|\bGroupBox|\bLocalizedStringKey|'
           r'\.navigationTitle|\.alert|\.confirmationDialog|\.accessibilityLabel|\.accessibilityHint|'
           r'\.accessibilityValue|\.help|\.searchable)')
UI_CALL = re.compile(SWIFTUI + r'\s*\(\s*' + LIT)
PROMPT = re.compile(r'\b(?:prompt|placeholder):\s*Text\(\s*' + LIT)
DOT_LOCALIZED = re.compile(LIT + r'\s*\.localized\b')
STRING_LOCALIZED = re.compile(r'String\(\s*localized:\s*' + LIT)
# A multi-line literal followed by .localized.
MULTILINE_LOCALIZED = re.compile(r'"""[ \t]*\n(.*?)\n([ \t]*)"""\s*\.localized\b', re.S)
# Helpers that localize the Strings passed to them: every plain literal argument counts.
HELPERS = re.compile(r'(?:\bSettingsSectionHeader|\bInfoButton\.footer|\bInfoButton|\bDestructiveSettingsLabel|'
                     r'\bSettingsRow|\bGameOverrideRow|\bScreenEmptyState|\bScreenStatusCallout|\bScreenChip|'
                     r'\bsameAsSettings|\bPanelToggle|\bPanelCaption|\bLayoutPanelFooter|\bsubPageLink|\bsubPage)\s*\(')

def call_args(src, start):
    """The text between the parenthesis at start-1 and its match, skipping strings."""
    depth, i, in_str = 1, start, False
    while i < len(src) and depth:
        c = src[i]
        if in_str:
            if c == '\\': i += 2; continue
            if c == '"': in_str = False
        elif c == '"': in_str = True
        elif c == '(': depth += 1
        elif c == ')': depth -= 1
        i += 1
    return src[start:i - 1]

def multiline_value(body, indent):
    lines = [l[len(indent):] if l.startswith(indent) else l.lstrip() for l in body.split('\n')]
    text = '\n'.join(lines)
    text = re.sub(r'\\\n', '', text)  # line-continuation backslash
    return text

def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n == 'u' and s[i + 2:i + 3] == '{':
                j = s.index('}', i)
                out.append(chr(int(s[i + 3:j], 16))); i = j + 1; continue
            out.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0'}.get(n, n)); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)

def is_text(s):
    return re.search(r'[A-Za-z]{2,}', s) is not None

def strip_comments(src):
    # Line comments only (block comments are rare in this code); keeps strings containing // intact.
    lines = []
    for line in src.split('\n'):
        out, in_str, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == '\\' and in_str: out.append(line[i:i + 2]); i += 2; continue
            if c == '"': in_str = not in_str
            if not in_str and line.startswith('//', i): break
            out.append(c); i += 1
        lines.append(''.join(out))
    return '\n'.join(lines)

# The controls package's own display text (style summaries, preset and display-mode names), which the
# app shows through .localized. Literals after `summary:` and in `return "..."` of title/summary.
PACKAGE = os.path.join(ROOT, 'Packages', 'MuffinTouchLab', 'Sources', 'TouchLabCore')
PACKAGE_SUMMARY = re.compile(r'\bsummary:\s*' + LIT)
PACKAGE_PROP = re.compile(r'\bvar\s+(?:title|summary)\s*:\s*String\s*\{')

def package_keys(keys):
    for dirpath, _, files in os.walk(PACKAGE):
        for name in sorted(files):
            if not name.endswith('.swift'): continue
            path = os.path.join(dirpath, name)
            src = strip_comments(open(path, encoding='utf-8').read())
            rel = os.path.relpath(path, ROOT)
            found = [m.group(1) for m in PACKAGE_SUMMARY.finditer(src)]
            for m in PACKAGE_PROP.finditer(src):
                found += re.findall(r'return\s+' + LIT, call_args(src.replace('{', '(').replace('}', ')'), m.end()))
            for raw in found:
                text = unescape(raw)
                if '\\(' not in raw and is_text(text): keys.setdefault(text, rel)

def main():
    keys, interpolated = {}, []
    if os.path.isdir(PACKAGE): package_keys(keys)
    for dirpath, _, files in os.walk(APP):
        for name in sorted(files):
            if not name.endswith('.swift'): continue
            path = os.path.join(dirpath, name)
            src = strip_comments(open(path, encoding='utf-8').read())
            rel = os.path.relpath(path, ROOT)
            for m in MULTILINE_LOCALIZED.finditer(src):
                body = m.group(1)
                if '\\(' in body: interpolated.append(f'{rel}: multi-line literal with interpolation'); continue
                text = unescape(multiline_value(body, m.group(2)))
                if is_text(text): keys.setdefault(text, f'{rel}:{src.count(chr(10), 0, m.start()) + 1}')
            for m in HELPERS.finditer(src):
                for lm in re.finditer(LIT, call_args(src, m.end())):
                    raw = lm.group(1)
                    if '\\(' in raw: continue
                    text = unescape(raw)
                    if is_text(text): keys.setdefault(text, f'{rel}:{src.count(chr(10), 0, m.start()) + 1}')
            for rx in (UI_CALL, PROMPT, DOT_LOCALIZED, STRING_LOCALIZED):
                for m in rx.finditer(src):
                    raw = m.group(1)
                    rel = os.path.relpath(path, ROOT)
                    line = src.count('\n', 0, m.start()) + 1
                    if '\\(' in raw:
                        if rx is not DOT_LOCALIZED: interpolated.append(f'{rel}:{line}: {raw}')
                        continue
                    text = unescape(raw)
                    if is_text(text): keys.setdefault(text, f'{rel}:{line}')
    with open(os.path.join(ROOT, 'l10n', 'keys.json'), 'w', encoding='utf-8') as f:
        json.dump(dict(sorted(keys.items())), f, ensure_ascii=False, indent=1)
    print(f'{len(keys)} keys')
    if '--check' in sys.argv:
        for line in interpolated: print('interpolated:', line)

if __name__ == '__main__':
    main()
