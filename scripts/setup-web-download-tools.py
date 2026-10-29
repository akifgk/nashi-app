#!/usr/bin/env python3
"""Fetch pinned official web-download executables; no system installation."""
import hashlib, io, os, platform, urllib.request, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
ASSETS=[
 ('yt-dlp','https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos','0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202',None),
 ('deno','https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip','5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c','deno')]
if platform.system()!='Darwin' or platform.machine()!='arm64':
 raise SystemExit('This app distribution targets Apple Silicon macOS. Use matching pinned runtimes for another architecture.')
(ROOT/'Tools').mkdir(exist_ok=True)
for name,url,digest,member in ASSETS:
 print(f'Downloading {name} from its official release…',flush=True)
 with urllib.request.urlopen(url,timeout=180) as response: data=response.read()
 if hashlib.sha256(data).hexdigest()!=digest: raise SystemExit(f'{name}: SHA256 mismatch; nothing installed')
 if member:
  with zipfile.ZipFile(io.BytesIO(data)) as archive: data=archive.read(member)
 target=ROOT/'Tools'/name;temporary=target.with_suffix('.download')
 temporary.write_bytes(data);temporary.chmod(0o755);os.replace(temporary,target)
 print(f'Installed Tools/{name}')
