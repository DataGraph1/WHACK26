"""Render the versioned field guide as a self-contained page for printing."""
from html import escape
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = root / 'docs/PLAYER_MANUAL.md'
target = root / 'docs/PLAYER_MANUAL_print.html'


def inline(value):
    value = escape(value.strip())
    return re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', value)


lines = source.read_text(encoding='utf-8').splitlines()
parts = []
i = 0
while i < len(lines):
    line = lines[i].strip()
    if not line:
        i += 1
        continue
    if line.startswith('#'):
        level = len(line) - len(line.lstrip('#'))
        parts.append(f'<h{level}>{inline(line[level:])}</h{level}>')
        i += 1
        continue
    if line.startswith('|'):
        cells = [v.strip() for v in line.strip('|').split('|')]
        parts.append('<table><thead><tr>' + ''.join(f'<th>{inline(c)}</th>' for c in cells) + '</tr></thead><tbody>')
        i += 2  # Markdown column separator
        while i < len(lines) and lines[i].startswith('|'):
            cells = [v.strip() for v in lines[i].strip('|').split('|')]
            parts.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in cells) + '</tr>')
            i += 1
        parts.append('</tbody></table>')
        continue
    if re.match(r'^\d+\. ', line):
        parts.append('<ol>')
        while i < len(lines) and re.match(r'^\d+\. ', lines[i].strip()):
            parts.append('<li>' + inline(re.sub(r'^\d+\. ', '', lines[i].strip())) + '</li>')
            i += 1
        parts.append('</ol>')
        continue
    paragraph = [line]
    i += 1
    while i < len(lines) and lines[i].strip() and not lines[i].startswith(('#', '|')):
        paragraph.append(lines[i].strip())
        i += 1
    parts.append('<p>' + inline(' '.join(paragraph)) + '</p>')

style = '''
@page { size: A4; margin: 12mm; }
body { font: 10.5pt/1.35 -apple-system, BlinkMacSystemFont, Arial, sans-serif; color: #17243a; max-width: 800px; margin: auto; }
h1 { font-size: 24pt; margin: 0 0 4mm; color: #123f59; }
h2 { font-size: 15pt; margin: 7mm 0 2mm; color: #174f67; break-after: avoid; }
p { margin: 2mm 0 3mm; }
ol { padding-left: 7mm; margin: 2mm 0 4mm; }
li { margin: 1mm 0; }
table { width: 100%; border-collapse: collapse; margin: 3mm 0 5mm; font-size: 9pt; break-inside: avoid; }
th,td { border: 1px solid #a4b6bd; padding: 1.6mm; text-align: left; }
th { background: #d9eaf0; }
@media screen { body { padding: 20px; } }
'''
target.write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Bot Defusal field guide, revision 7</title><style>' + style + '</style><body>' + '\n'.join(parts) + '</body></html>\n', encoding='utf-8')
print(target)
