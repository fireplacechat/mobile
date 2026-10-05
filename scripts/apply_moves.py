#!/usr/bin/env python3
"""Apply the one-to-one `move` rows of lib-map.csv and test-map.csv to a checkout.

Usage: apply_moves.py REPO_DIR [--dry-run]

One-shot migration from the parent of the feature-layout PR. The adjacent CSV
maps describe that source tree, not the tree after applying the moves.

- git mv each file whose action is `move` and whose new path is a single file.
- rewrite every import/export in lib/, test/, integration_test/ and scripts/ so it still points
  at the right file. Imports of lib files become `package:fireplace/...` (the
  always_use_package_imports lint); imports between test files stay relative.
- `split` rows are NOT touched here: each split is its own reviewed PR (see SPLIT-*.md).
Run flutter analyze and the full serial suite afterwards; nothing else changes.
"""
import csv, os, re, subprocess, sys
repo = os.path.abspath(sys.argv[1]); dry = '--dry-run' in sys.argv
plan = os.path.dirname(os.path.abspath(__file__))
moves = {}
mapped = set()
for name in ('lib-map.csv', 'test-map.csv'):
    for r in csv.DictReader(open(os.path.join(plan, name))):
        mapped.add(r['current_path'])
        if r['action'] == 'move' and ' ' not in r['new_path'] and r['new_path'].endswith('.dart'):
            moves[r['current_path']] = r['new_path']
def final(p): return moves.get(p, p)
pat = re.compile(r"""^(\s*)(import|export)\s+'([^']+)'(.*)$""")
files = []
for top in ('lib', 'test', 'integration_test', 'scripts', 'tool'):
    for dp, _, fs in os.walk(os.path.join(repo, top)):
        files += [os.path.relpath(os.path.join(dp, f), repo) for f in fs if f.endswith('.dart')]
unmapped = sorted(p for p in files if p.startswith(('lib/', 'test/', 'integration_test/')) and p not in mapped)
missing = sorted(p for p in mapped if not os.path.isfile(os.path.join(repo, p)))
if unmapped or missing:
    raise SystemExit(f'Map mismatch: unmapped={unmapped}, missing={missing}')
if len(set(moves.values())) != len(moves):
    raise SystemExit('Move destinations must be unique')
for old, new in moves.items():
    if os.path.exists(os.path.join(repo, new)):
        raise SystemExit(f'Move destination already exists: {new}')
edits = {}
for old in files:
    new = final(old); src = open(os.path.join(repo, old)).read(); out = []; changed = False
    for line in src.split('\n'):
        m = pat.match(line)
        if m:
            ind, kw, target, rest = m.groups(); tgt = None
            if target.startswith('package:fireplace/'): tgt = 'lib/' + target[len('package:fireplace/'):]
            elif not target.startswith(('package:', 'dart:')): tgt = os.path.normpath(os.path.join(os.path.dirname(old), target))
            if tgt:
                t2 = final(tgt)
                if t2.startswith('lib/'): nt = 'package:fireplace/' + t2[4:]
                else: nt = os.path.relpath(t2, os.path.dirname(new))
                if nt != target: line = f"{ind}{kw} '{nt}'{rest}"; changed = True
        out.append(line)
    edits[old] = ('\n'.join(out), changed)
print(len(moves), 'files to move;', sum(1 for v in edits.values() if v[1]), 'files with rewritten imports')
if dry: sys.exit(0)
for old, (txt, changed) in edits.items():
    if changed: open(os.path.join(repo, old), 'w').write(txt)
for old, new in sorted(moves.items()):
    if not os.path.exists(os.path.join(repo, old)): print('missing', old); continue
    os.makedirs(os.path.dirname(os.path.join(repo, new)), exist_ok=True)
    subprocess.check_call(['git', 'mv', old, new], cwd=repo)
