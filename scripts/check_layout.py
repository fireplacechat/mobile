#!/usr/bin/env python3
"""Enforce the layer rules of lib/src/ (feature and layer layout). Exit 1 on a violation.

  crypto/   pure cryptography: no Flutter, no Firebase, no other app layer
  utils/    small pure helpers: no Flutter widgets, no Firebase, no other app layer
  db/       local storage (encrypted history, secret store): no widgets, no view/, widgets/, styles/, model/
  model/    logic, state and Firebase access per feature: no widgets, no view/, widgets/, styles/
  styles/   colours, spacing, text styles, brand drawing: no model/, view/, db/
  widgets/  shared widgets: styles/ and utils/ only; never model/, view/, db/
  view/     screens, per feature: may use everything above; a feature must not import files inside another feature's folder
  (top-level app.dart, init: may use anything)

Also warns (does not fail) for a source file over 500 lines.
"""
import os, re, sys
root = sys.argv[1] if len(sys.argv) > 1 else '.'
lib = os.path.join(root, 'lib', 'src')
if not os.path.isdir(lib):
    raise SystemExit(f'Missing source tree: {lib}')
FLUTTER_UI = ['package:flutter/material', 'package:flutter/widgets', 'package:flutter/cupertino']
FIREBASE = ['package:cloud_firestore', 'package:firebase']
APP = ['/model/', '/view/', '/widgets/', '/styles/', '/db/']
FORBID = {
 'crypto':  ['package:flutter/'] + FIREBASE + APP + ['/utils/'],
 'utils':   FLUTTER_UI + FIREBASE + APP + ['/crypto/'],
 'db':      FLUTTER_UI + ['/model/', '/view/', '/widgets/', '/styles/'],
 'model':   FLUTTER_UI + ['/view/', '/widgets/', '/styles/'],
 'styles':  ['/model/', '/view/', '/db/'] + FIREBASE,
 'widgets': ['/model/', '/view/', '/db/'] + FIREBASE,
 'view':    FIREBASE,
}
imp = re.compile(r"""^\s*(?:import|export)\s+'([^']+)'""")
bad = 0; big = []
for retired in ('ui', 'services'):
    if os.path.exists(os.path.join(lib, retired)):
        print(f'VIOLATION retired directory: {retired}/ must not exist'); bad += 1
for dp, _, fs in os.walk(lib):
    for f in fs:
        if not f.endswith('.dart'): continue
        p = os.path.join(dp, f); rel = os.path.relpath(p, lib); layer = rel.split(os.sep)[0]
        lines = open(p).read().split('\n')
        if len(lines) > 500: big.append((len(lines), rel))
        for i, l in enumerate(lines, 1):
            m = imp.match(l)
            if not m: continue
            if not m.group(1).startswith(('package:', 'dart:')):
                print(f'VIOLATION {rel}:{i}: use a package import for {m.group(1)}'); bad += 1
            for bad_s in FORBID.get(layer, []):
                if bad_s in m.group(1):
                    print(f'VIOLATION {rel}:{i}: {layer}/ must not import {m.group(1)}'); bad += 1
        if layer == 'view':  # reach into another feature's private files
            mine = rel.split(os.sep)[1]
            for i, l in enumerate(lines, 1):
                m = imp.match(l)
                if m and 'package:fireplace/src/view/' in m.group(1):
                    other = m.group(1).split('/view/')[1].split('/')[0]
                    if other != mine and '/' in m.group(1).split('/view/')[1].split('/', 1)[1]:
                        print(f'VIOLATION {rel}:{i}: imports inside another feature ({m.group(1)}); use its public file'); bad += 1
for n, r in sorted(big, reverse=True): print(f'WARN {r}: {n} lines (over 500)')
print('layout OK' if not bad else f'{bad} violation(s)')
sys.exit(1 if bad else 0)
