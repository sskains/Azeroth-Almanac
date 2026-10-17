"""
Azeroth Almanac - build the CurseForge description from its Markdown master.

    python tools/build_description.py

Reads  CurseForge/description.md
Writes CurseForge/description.html   the fragment to paste into CurseForge's source view
       CurseForge/preview.html       the same, wrapped and styled, to open in a browser

CurseForge's editor does not read Markdown: pasting the .md leaves "##" on the page. Paste the
fragment into the editor's source view (the <> button), or open preview.html in a browser and copy
the rendered page - either carries real headings, bold, lists and the table.

The fragment deliberately has no <html>, <head> or <style>: anything of that sort is stripped or
fought with by CurseForge's own styling. preview.html wraps the very same fragment, so the two
cannot drift.

The only hand step left is the image: CurseForge will not resolve a relative path, so upload
WildGambit-icon.png on the project's Images tab and replace the src on the marked line.
"""
import io
import os
import re
import html as html_mod

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "CurseForge", "description.md")
FRAGMENT = os.path.join(ROOT, "CurseForge", "description.html")
PREVIEW = os.path.join(ROOT, "CurseForge", "preview.html")

IMAGE_NOTE = (
    "<!-- Upload WildGambit-icon.png on the project's Images tab first, then replace the src\n"
    "     below with the URL CurseForge gives it. A relative path will not resolve. -->"
)

PAGE_HEAD = """<!DOCTYPE html>
<meta charset="utf-8">
<title>Azeroth Almanac - CurseForge description</title>
<style>
  body { max-width: 52rem; margin: 2rem auto; padding: 0 1rem;
         font: 16px/1.6 "Segoe UI", system-ui, sans-serif; color: #ddd; background: #1b1b1f; }
  h1 { font-size: 2rem; border-bottom: 1px solid #444; padding-bottom: .3rem; }
  h2 { font-size: 1.5rem; margin-top: 2rem; color: #f0c674; }
  h3 { font-size: 1.15rem; margin-top: 1.5rem; color: #cfd8a0; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { border: 1px solid #444; padding: .4rem .6rem; text-align: left; vertical-align: top; }
  th { background: #2a2a30; }
  code { background: #2a2a30; padding: .1rem .3rem; border-radius: 3px; }
  hr { border: 0; border-top: 1px solid #444; margin: 2rem 0; }
  img { vertical-align: middle; }
</style>
<!-- A browser view of description.html, for the select-all-and-copy route.
     The file CurseForge wants pasted into its source view is description.html, not this one. -->
"""


def inline(text):
    """The inline Markdown this document uses, and no more."""
    t = html_mod.escape(text, quote=False)
    t = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)",
               lambda m: '<img src="%s" alt="%s" width="128" height="128" />' % (m.group(2), m.group(1)), t)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: '<a href="%s">%s</a>' % (m.group(2), m.group(1)), t)
    t = re.sub(r"\*\*([^*]+)\*\*", lambda m: "<strong>%s</strong>" % m.group(1), t)
    t = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", lambda m: "<em>%s</em>" % m.group(1), t)
    t = re.sub(r"`([^`]+)`", lambda m: "<code>%s</code>" % m.group(1), t)
    return t


def build(lines):
    out, i = [], 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line.strip():
            i += 1
            continue
        if line.startswith("---"):
            out.append("<hr />")
            i += 1
            continue
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            n = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (n, inline(m.group(2)), n))
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append("<table>")
            out.append("<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in rows[0]) + "</tr></thead>")
            out.append("<tbody>")
            for r in rows[2:]:
                out.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
            out.append("</tbody></table>")
            continue
        if line.startswith("- "):
            out.append("<ul>")
            while i < len(lines) and lines[i].startswith("- "):
                out.append("<li>%s</li>" % inline(lines[i][2:].strip()))
                i += 1
            out.append("</ul>")
            continue
        para = []
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|\||- |---)", lines[i]):
            para.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % inline(" ".join(para)))
    return out


def main():
    lines = io.open(SRC, encoding="utf-8").read().split("\n")
    out = build(lines)
    fragment = "\n".join(out) + "\n"
    # the one line a human has to edit after pasting gets a comment above it
    fragment = re.sub(r'(<p><img src="WildGambit-icon\.png"[^>]*/></p>)',
                      lambda m: IMAGE_NOTE + "\n" + m.group(1), fragment, count=1)
    io.open(FRAGMENT, "w", encoding="utf-8", newline="\n").write(fragment)
    io.open(PREVIEW, "w", encoding="utf-8", newline="\n").write(PAGE_HEAD + fragment)
    print("%s  (%d blocks)" % (FRAGMENT, len(out)))
    print(PREVIEW)


if __name__ == "__main__":
    main()
