#!/usr/bin/env python3
"""Render an image manifest into a self-contained HTML report.

Offline and deterministic: reads JSON produced by roles/manifest and writes one
HTML file with no external assets. That matters because the report is published
beside the image and may be opened years later from a bucket, long after any CDN
reference would have rotted.

  render-docs.py --manifest M [--declared D] [--out docs.html]
  render-docs.py --diff OLD.json NEW.json [--out diff.html]
"""
import argparse
import html
import json
from datetime import datetime, timezone
from pathlib import Path

# Palette roles from the design system's reference instance. Light and dark are
# separately chosen steps validated against their own surface, not an automatic
# inversion of each other.
CSS = """
:root{
  --surface-0:#ffffff; --surface-1:#fcfcfb; --surface-2:#f4f4f2; --border:#e2e2dd;
  --text-primary:#0b0b0b; --text-secondary:#52514e; --text-muted:#78776f;
  --series-1:#2a78d6;
  --good:#0ca30c; --warning:#fab219; --serious:#ec835a; --critical:#d03b3b;
}
@media (prefers-color-scheme:dark){
  :root{
    --surface-0:#111110; --surface-1:#1a1a19; --surface-2:#232322; --border:#33332f;
    --text-primary:#ffffff; --text-secondary:#c3c2b7; --text-muted:#8f8e85;
    --series-1:#3987e5;
  }
}
*{box-sizing:border-box}
body{margin:0;background:var(--surface-0);color:var(--text-primary);
  font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1100px;margin:0 auto;padding:32px 20px 72px}
h1{font-size:26px;margin:0 0 4px} h2{font-size:17px;margin:40px 0 12px;
  padding-bottom:6px;border-bottom:1px solid var(--border)}
.sub{color:var(--text-secondary);font-size:14px;margin:0 0 24px}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px}

/* Status banner: colour never carries the meaning alone -- icon + label do. */
.banner{display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:8px;
  border:1px solid var(--border);background:var(--surface-1);margin:0 0 26px}
.banner .icon{font-weight:700;line-height:1.4}
.banner.good .icon{color:var(--good)} .banner.bad .icon{color:var(--critical)}
.banner .label{font-weight:600}

.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px}
.tile{background:var(--surface-1);border:1px solid var(--border);border-radius:8px;padding:12px 14px}
.tile .v{font-size:22px;font-weight:650;letter-spacing:-.02em}
.tile .k{font-size:12px;color:var(--text-secondary);margin-top:2px}

/* Single-series magnitude bars. Capped thickness, 4px rounded data-end,
   square at the baseline, all growing from one baseline. */
.bars{display:grid;gap:7px}
.bar-row{display:grid;grid-template-columns:220px 1fr 78px;gap:12px;align-items:center}
.bar-name{color:var(--text-secondary);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bar-track{background:var(--surface-2);border-radius:2px;height:18px;position:relative}
.bar-fill{background:var(--series-1);height:18px;max-height:24px;
  border-radius:0 4px 4px 0;min-width:2px}
.bar-val{text-align:right;color:var(--text-secondary);font-variant-numeric:tabular-nums}

.filters{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:0 0 12px}
input[type=search]{flex:1;min-width:200px;padding:7px 10px;border-radius:7px;
  border:1px solid var(--border);background:var(--surface-1);color:var(--text-primary);font-size:14px}
.chip{padding:5px 11px;border-radius:999px;border:1px solid var(--border);
  background:var(--surface-1);color:var(--text-secondary);cursor:pointer;font-size:13px}
.chip[aria-pressed=true]{background:var(--series-1);border-color:var(--series-1);color:#fff}

.tablewrap{overflow-x:auto;border:1px solid var(--border);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th{position:sticky;top:0;background:var(--surface-2);text-align:left;padding:8px 10px;
  font-weight:600;font-size:12px;color:var(--text-secondary);white-space:nowrap}
td{padding:6px 10px;border-top:1px solid var(--border);vertical-align:top}
td.num{text-align:right;font-variant-numeric:tabular-nums;color:var(--text-secondary)}
.tag{display:inline-block;padding:1px 7px;border-radius:999px;font-size:11px;
  border:1px solid var(--border);color:var(--text-secondary);white-space:nowrap}
.tag.declared{border-color:var(--series-1);color:var(--series-1)}
.miss{color:var(--critical);font-weight:600}
.empty{color:var(--text-muted);padding:14px 10px}
footer{margin-top:48px;padding-top:14px;border-top:1px solid var(--border);
  color:var(--text-muted);font-size:12.5px}
"""

JS = """
(function(){
  var q=document.getElementById('q'), rows=[].slice.call(
    document.querySelectorAll('#pkgs tbody tr')), mode='all';
  function apply(){
    var t=(q.value||'').toLowerCase(); var shown=0;
    rows.forEach(function(r){
      var okMode = mode==='all'
        || (mode==='declared' && r.dataset.declared==='1')
        || (mode==='auto'     && r.dataset.manual==='0')
        || (mode==='vendor'   && r.dataset.vendor==='1');
      var okText = !t || r.dataset.search.indexOf(t)>-1;
      var vis = okMode && okText;
      r.style.display = vis ? '' : 'none';
      if(vis) shown++;
    });
    document.getElementById('count').textContent = shown + ' shown';
  }
  q.addEventListener('input', apply);
  [].forEach.call(document.querySelectorAll('.chip'), function(c){
    c.addEventListener('click', function(){
      [].forEach.call(document.querySelectorAll('.chip'), function(o){
        o.setAttribute('aria-pressed', o===c ? 'true':'false'); });
      mode=c.dataset.mode; apply();
    });
  });
  apply();
})();
"""


def esc(s):
    return html.escape(str(s if s is not None else ""))


def human_kb(kb):
    if kb >= 1048576:
        return f"{kb / 1048576:.1f} GB"
    if kb >= 1024:
        return f"{kb / 1024:.1f} MB"
    return f"{kb} kB"


def tile(value, label):
    return f'<div class="tile"><div class="v">{esc(value)}</div><div class="k">{esc(label)}</div></div>'


def render(manifest, declared_doc):
    img = manifest.get("image", {})
    counts = manifest.get("counts", {})
    apt = manifest.get("packages", {}).get("apt", [])
    snaps = manifest.get("packages", {}).get("snap", [])
    flats = manifest.get("packages", {}).get("flatpak", [])
    satisfied = set(manifest.get("satisfied_names", []))

    declared = set(declared_doc.get("declared", []))
    absent = set(declared_doc.get("absent", []))
    missing = sorted(declared - satisfied)
    not_removed = sorted(absent & satisfied)
    undeclared = sorted(p["name"] for p in apt
                        if p.get("manual") and p["name"] not in declared)

    ok = not missing and not not_removed
    if declared:
        if ok:
            banner = (f'<div class="banner good"><span class="icon">&#10003;</span><div>'
                      f'<div class="label">Image matches its declaration</div>'
                      f'<div>All {len(declared)} packages declared in <code>group_vars/all.yml</code> '
                      f'are installed.</div></div></div>')
        else:
            parts = []
            if missing:
                parts.append("Declared but missing: <span class='miss'>"
                             + ", ".join(esc(m) for m in missing) + "</span>.")
            if not_removed:
                parts.append("Declared absent but present: <span class='miss'>"
                             + ", ".join(esc(m) for m in not_removed) + "</span>.")
            banner = ('<div class="banner bad"><span class="icon">&#10007;</span><div>'
                      '<div class="label">Image does not match its declaration</div>'
                      '<div>' + " ".join(parts) + "</div></div></div>")
    else:
        banner = ('<div class="banner"><span class="icon">&#8212;</span><div>'
                  '<div class="label">No declaration supplied</div>'
                  '<div>Rendered without <code>workstation-declared.json</code>, so nothing '
                  'was cross-checked against <code>group_vars</code>.</div></div></div>')

    tiles = "".join([
        tile(counts.get("apt_total", len(apt)), "apt packages"),
        tile(counts.get("apt_manual", 0), "explicitly installed"),
        tile(counts.get("apt_auto", 0), "pulled in as deps"),
        tile(len(snaps), "snaps"),
        tile(len(flats), "flatpaks"),
        tile(f'{img.get("root_used_mb", 0):,} MB', "installed size"),
    ])

    # Single series (installed size), so no legend -- the heading names it.
    top = sorted(apt, key=lambda p: p.get("size_kb", 0), reverse=True)[:15]
    peak = max((p.get("size_kb", 0) for p in top), default=1) or 1
    bars = "".join(
        f'<div class="bar-row"><div class="bar-name" title="{esc(p["name"])}">{esc(p["name"])}</div>'
        f'<div class="bar-track"><div class="bar-fill" style="width:{max(2, round(p.get("size_kb",0)/peak*100))}%" '
        f'title="{esc(p["name"])} &mdash; {human_kb(p.get("size_kb",0))}"></div></div>'
        f'<div class="bar-val">{human_kb(p.get("size_kb", 0))}</div></div>'
        for p in top)

    vendor_hosts = ("downloads.claude.ai", "dl.google.com", "downloads.1password.com",
                    "download.docker.com", "apt.releases.hashicorp.com")
    rows = []
    for p in apt:
        name = p["name"]
        is_dec = name in declared
        origin = p.get("origin", "")
        is_vendor = any(h in origin for h in vendor_hosts)
        search = f'{name} {p.get("version","")} {origin} {p.get("summary","")}'.lower()
        tags = '<span class="tag declared">declared</span>' if is_dec else (
            '<span class="tag">dependency</span>' if not p.get("manual") else '')
        # Built outside the f-string: an f-string expression cannot contain a
        # backslash, and the fallback markup needs escaped quotes.
        origin_cell = esc(origin) if origin else '<span class="empty">&mdash;</span>' 
        rows.append(
            f'<tr data-search="{esc(search)}" data-declared="{1 if is_dec else 0}" '
            f'data-manual="{1 if p.get("manual") else 0}" data-vendor="{1 if is_vendor else 0}">'
            f'<td class="mono">{esc(name)}</td><td class="mono">{esc(p.get("version",""))}</td>'
            f'<td class="num">{human_kb(p.get("size_kb",0))}</td>'
            f'<td>{origin_cell}</td>'
            f'<td>{tags}</td></tr>')

    def simple_list(items, empty_msg):
        if not items:
            return f'<p class="empty">{esc(empty_msg)}</p>'
        return ('<div class="tablewrap"><table><tbody>'
                + "".join(f'<tr><td class="mono">{esc(i)}</td></tr>' for i in items)
                + "</tbody></table></div>")

    snap_rows = "".join(
        f'<tr><td class="mono">{esc(s["name"])}</td><td class="mono">{esc(s.get("version",""))}</td>'
        f'<td>{esc(s.get("channel",""))}</td></tr>' for s in snaps)
    flat_rows = "".join(
        f'<tr><td class="mono">{esc(f["id"])}</td><td class="mono">{esc(f.get("version",""))}</td>'
        f'<td>{esc(f.get("branch",""))}</td></tr>' for f in flats)

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    origins_resolved = manifest.get("tooling", {}).get("origins_resolved", 0)

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Workstation image {esc(img.get('version','unknown'))}</title>
<style>{CSS}</style></head><body><div class="wrap">

<h1>Workstation image contents</h1>
<p class="sub"><code>{esc(img.get('version','unknown'))}</code> &middot;
built {esc(img.get('build_date','unknown'))} &middot;
{esc(img.get('distribution',''))} ({esc(img.get('codename',''))}) &middot;
kernel {esc(img.get('kernel',''))}</p>

{banner}

<h2>Summary</h2>
<div class="tiles">{tiles}</div>

<h2>Largest packages by installed size</h2>
<div class="bars">{bars}</div>

<h2>Everything installed</h2>
<div class="filters">
  <input type="search" id="q" placeholder="Filter by name, version, repository or summary&hellip;">
  <button class="chip" data-mode="all" aria-pressed="true">All</button>
  <button class="chip" data-mode="declared" aria-pressed="false">Declared</button>
  <button class="chip" data-mode="auto" aria-pressed="false">Dependencies</button>
  <button class="chip" data-mode="vendor" aria-pressed="false">Vendor repos</button>
  <span class="bar-val" id="count"></span>
</div>
<div class="tablewrap"><table id="pkgs">
<thead><tr><th>Package</th><th>Version</th><th>Size</th><th>Repository</th><th></th></tr></thead>
<tbody>{"".join(rows)}</tbody></table></div>

<h2>Installed but never declared <span class="tag">{len(undeclared)}</span></h2>
<p class="sub">Explicitly-installed packages with no entry in <code>group_vars/all.yml</code>.
Mostly base-install components and <code>Recommends</code> pulled in by other packages &mdash;
this is where image growth comes from.</p>
{simple_list(undeclared[:80], "Nothing: every explicitly-installed package is declared.")}

<h2>Snaps</h2>
{'<div class="tablewrap"><table><thead><tr><th>Name</th><th>Version</th><th>Channel</th></tr></thead><tbody>' + snap_rows + '</tbody></table></div>' if snaps else '<p class="empty">None installed.</p>'}

<h2>Flatpaks</h2>
{'<div class="tablewrap"><table><thead><tr><th>Application</th><th>Version</th><th>Branch</th></tr></thead><tbody>' + flat_rows + '</tbody></table></div>' if flats else '<p class="empty">None installed.</p>'}

<h2>Enabled services</h2>
{simple_list(manifest.get('services_enabled', []), 'None recorded.')}

<h2>Firewall</h2>
{simple_list(manifest.get('firewall', []), 'No rules recorded (ufw inactive or unavailable at capture time).')}

<footer>
Generated {esc(generated)} by <code>scripts/render-docs.py</code> from
<code>/etc/workstation-manifest.json</code>, captured inside the image before sealing.
Package repository attributed for {origins_resolved} packages.
This report describes what was installed; it does not prove the image boots.
</footer>
</div><script>{JS}</script></body></html>
"""


def render_diff(old, new):
    def index(m):
        return {p["name"]: p for p in m.get("packages", {}).get("apt", [])}
    o, n = index(old), index(new)
    added = sorted(set(n) - set(o))
    removed = sorted(set(o) - set(n))
    changed = sorted(k for k in set(o) & set(n) if o[k]["version"] != n[k]["version"])
    ov, nv = old.get("image", {}).get("version", "?"), new.get("image", {}).get("version", "?")

    def sec(title, items, fmt):
        if not items:
            return f"<h2>{esc(title)}</h2><p class='empty'>None.</p>"
        return (f"<h2>{esc(title)} <span class='tag'>{len(items)}</span></h2>"
                "<div class='tablewrap'><table><tbody>"
                + "".join(fmt(i) for i in items) + "</tbody></table></div>")

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Image diff {esc(ov)} to {esc(nv)}</title><style>{CSS}</style></head>
<body><div class="wrap">
<h1>Image diff</h1>
<p class="sub"><code>{esc(ov)}</code> &rarr; <code>{esc(nv)}</code></p>
<div class="tiles">{tile(len(added), 'added')}{tile(len(removed), 'removed')}{tile(len(changed), 'version changed')}</div>
{sec('Added', added, lambda k: f'<tr><td class="mono">{esc(k)}</td><td class="mono">{esc(n[k]["version"])}</td></tr>')}
{sec('Removed', removed, lambda k: f'<tr><td class="mono">{esc(k)}</td><td class="mono">{esc(o[k]["version"])}</td></tr>')}
{sec('Version changed', changed, lambda k: f'<tr><td class="mono">{esc(k)}</td><td class="mono">{esc(o[k]["version"])} &rarr; {esc(n[k]["version"])}</td></tr>')}
<footer>Generated by <code>scripts/render-docs.py --diff</code>.</footer>
</div></body></html>
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest")
    ap.add_argument("--declared")
    ap.add_argument("--diff", nargs=2, metavar=("OLD", "NEW"))
    ap.add_argument("--out", "-o", default="docs.html")
    a = ap.parse_args()

    if a.diff:
        old = json.loads(Path(a.diff[0]).read_text())
        new = json.loads(Path(a.diff[1]).read_text())
        out = render_diff(old, new)
    elif a.manifest:
        manifest = json.loads(Path(a.manifest).read_text())
        declared = {}
        if a.declared and Path(a.declared).exists():
            declared = json.loads(Path(a.declared).read_text())
        out = render(manifest, declared)
    else:
        ap.error("need --manifest or --diff")

    Path(a.out).write_text(out, encoding="utf-8")
    print(f"wrote {a.out} ({len(out) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
