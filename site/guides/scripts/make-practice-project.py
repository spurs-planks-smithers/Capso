#!/usr/bin/env python3
"""Build the local, editable exercise from the hosted fictional demo."""
from pathlib import Path
import re
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
html = (root / "public/demo.html").read_text()
html = re.sub(r"@font-face\{[^}]+\}", "", html)
html = html.replace('/guides/demo/lemon-glass.svg', 'lemon-glass.svg')
html = html.replace('<a href="/guides/first-handoff/">', '<a href="https://nextshot.dev/guides/first-handoff/">')
readme = """Nextshot practice project

1. Unzip this folder in a place where your coding agent can read it.
2. Open this folder as the agent's project.
3. Open index.html in your browser.
4. Capture and mark the title, price, and Buy button with Nextshot.
5. Give the agent your three notes through the Nextshot round prompt.

Example requests:
1. Change Lemonaid to Lemonade.
2. Change $9 a cup to $3 a cup.
3. Make the Buy button larger and easier to click.

The editable page and its styles are both in index.html.
The glass illustration is lemon-glass.svg.
This is fictional demo content, with no real account or payment data.
"""
destination = root / "public/resources/nextshot-practice-project.zip"
destination.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
    for name, data in {
        "index.html": html.encode(),
        "lemon-glass.svg": (root / "public/demo/lemon-glass.svg").read_bytes(),
        "README.txt": readme.encode(),
    }.items():
        info = ZipInfo("nextshot-practice/" + name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, data)
print(destination)
