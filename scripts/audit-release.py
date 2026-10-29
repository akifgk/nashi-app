#!/usr/bin/env python3
"""Fail a public macOS bundle on accidental credentials or builder identity."""
import os, re, sys, plistlib
from pathlib import Path
root=Path(sys.argv[1]).resolve()
info=plistlib.loads((root/'Contents/Info.plist').read_bytes())
assert info.get('NashiPublicUpdateRepository')=='orkunisitmak/nashi-app'
assert info.get('SUFeedURL')=='https://github.com/orkunisitmak/nashi-app/releases/latest/download/appcast.xml'
assert info.get('NashiExternalTools') is True
assert not (root/'Contents/XPCServices').exists(), 'Public archive must not include a private credential broker'
assert not (root/'Contents/Resources/Tools/ffmpeg').exists(), 'Upstream media tools use direct first-use acquisition'
assert not (root/'Contents/Resources/Tools/LibreOffice.app').exists()
username=os.environ.get('USER','').encode()
issues=[];count=0
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink(): continue
    count+=1;data=path.read_bytes()
    if path.name.startswith('.env') or path.suffix.lower() in {'.p12','.pfx','.key','.mobileprovision'}:issues.append(str(path.relative_to(root)))
    patterns=[rb'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----',rb'github_pat_[A-Za-z0-9_]{20,}',rb'gh[pousr]_[A-Za-z0-9]{20,}']
    if any(re.search(pattern,data) for pattern in patterns) or username and len(username)>5 and username in data:issues.append(str(path.relative_to(root)))
if issues:sys.exit('Release audit failed: '+', '.join(sorted(set(issues))))
print(f'PASS public app boundary: {count} files; no local account, signing artifacts or token patterns')
