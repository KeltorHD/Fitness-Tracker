#!/usr/bin/env python3
"""Syntax parsing only: no SDK imports, macro expansion, type checking or linking."""
from pathlib import Path
import subprocess
import sys

compiler = sys.argv[1] if len(sys.argv) > 1 else 'swiftc'
for paths, flags in [
    (['App', 'Design', 'Features', 'Persistence', 'Services', 'Shared'], ['-D', 'FITNESS_TRACKER_APP']),
    (['Watch'], []), (['Widgets', 'Shared'], []), (['Tests'], []), (['UITests'], []),
]:
    sources = sorted(str(file) for path in paths for file in Path('Apple', path).rglob('*.swift'))
    subprocess.run([compiler, '-frontend', '-parse', *flags, *sources], check=True)
print('Apple sources: syntax parsed only; requires Xcode validation.')
