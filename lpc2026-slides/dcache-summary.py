#!/usr/bin/env python3
"""Slide 26's numbers -> data/dcache-summary{.csv,-points.csv,-macros.tex}.

The dentry-cache slide is a slide-sized cut of the benchmark tree's one-page
summary, figures/dcache_bucketlock_summary.png: the bucket lock + SW txn
engine's throughput ÷ the kernel-faithful seqlock baseline's, one row per
benchmark, one point per measured x of that benchmark's sweep.

The rows and their ratios are NOT recomputed here: this runs the benchmark
tree's own plot script (scripts/plot_dcache_bucketlock_summary.py) up to its
drawing code and takes its ROWS, so the slide cannot disagree with the figure
it summarizes. What this file owns is the slide's selection, order and
vertical layout (LAYOUT); the wording of each row is fig-dcache.tex's. The
macros file gives the deck's text the same ranges (\\dcrange{key}) and the
sweep's provenance id, so no ratio is typed by hand.

Unlike P1's CSVs, which the deck reads in place, the output is committed: the
benchmark tree is another repository and the laptop may not have it.

Usage: dcache-summary.py [benchmark tree, default ~/git/efficios-trie-benchmark]
"""
import csv, os, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1
                           else "~/git/efficios-trie-benchmark")
PLOT = os.path.join(BENCH, "scripts", "plot_dcache_bucketlock_summary.py")
OUT = os.path.join(HERE, "data")

# (key, the benchmark figure's row label). A key is what fig-dcache.tex words;
# a header's key names its group. Order is top to bottom, and both rows the
# figure files under "bucket lock slower" are here: the cut drops rows that
# repeat a point, never the ones that go against the engine.
LAYOUT = [
    ("hdr-par", None),
    ("lookup-low", "Lookups, 10k-30k renames/s (184 readers)"),
    ("lookup-rest", "Lookups at rest, 2-184 readers"),
    ("churn-alloc", "Create/delete, allocating, private dirs, 1-192 writers"),
    ("hdr-faster", None),
    ("lookup-high", "Lookups under heavy renames, 100k-300k renames/s"),
    ("dpath", "Reverse walk (d_path) under renames"),
    ("readdir", "readdir under renames"),
    ("churn-inplace", "Create/delete in place, private dirs, 1-48 writers"),
    ("hdr-slower", None),
    ("hit", "Positive hits on objects being renamed (100k/s)"),
    ("hit-rest", "Positive hits at rest"),
    ("hdr-capacity", None),
    ("cap-leaf", "Leaf renames and exchanges (8 writers + 184 readers)"),
    ("cap-dir", "Directory rename / move / exchange"),
]
GROUPS = ("par", "faster", "slower", "capacity")
ROW_PITCH, HDR_PITCH = 1.0, 1.25	# a header sits a little clear of the row above

# Run the benchmark's script up to its drawing code. It has no main(): the
# split point is the table of groups that follows ROWS.
src = open(PLOT).read()
cut = src.find("\nGROUPS = [")
if cut < 0:
    sys.exit(f"{PLOT}: no 'GROUPS = [' after ROWS; the script changed shape")
env = {"__file__": PLOT, "__name__": "dcache_summary_rows"}
exec(compile(src[:cut], PLOT, "exec"), env)
rows = {label: (group, vals) for group, label, _fig, vals in env["ROWS"]}
srcs = sorted(env["srcs"])
if len(srcs) != 1:
    sys.exit(f"the sweep CSVs carry {len(srcs)} provenance ids, want 1: {srcs}")
bench = subprocess.run(["git", "-C", BENCH, "rev-parse", "--short", "HEAD"],
                       capture_output=True, text=True, check=True).stdout.strip()
if subprocess.run(["git", "-C", BENCH, "status", "--porcelain", "--", "scripts"],
                  capture_output=True, text=True, check=True).stdout.strip():
    sys.exit(f"{BENCH}/scripts has uncommitted changes: the commit id written "
             "next to the numbers would not name the data they came from")

summary, points, y = [], [], 0.0
for key, label in LAYOUT:
    if label is None:
        group = key[len("hdr-"):]
        assert group in GROUPS, key
        y -= HDR_PITCH
        summary.append(dict(y=y, hdr=1, key=key, group=group, n=0, lo="nan",
                            med="nan", hi="nan"))
        continue
    if label not in rows:
        sys.exit(f"the benchmark figure has no row {label!r}")
    rgroup, vals = rows[label]
    if rgroup != group:
        sys.exit(f"{label!r} is filed under {rgroup!r} there, {group!r} here")
    if not vals:
        sys.exit(f"no data for {label!r}")
    y -= ROW_PITCH
    summary.append(dict(y=y, hdr=0, key=key, group=group, n=len(vals),
                        lo=f"{min(vals):.4f}",
                        med=f"{statistics.median(vals):.4f}",
                        hi=f"{max(vals):.4f}"))
    for v in sorted(vals):
        pt = dict(y=y, key=key, **{g: "nan" for g in GROUPS})
        pt[group] = f"{v:.4f}"
        points.append(pt)

os.makedirs(OUT, exist_ok=True)
head = (f"# Written by lpc2026-slides/dcache-summary.py; do not edit.\n"
        f"# efficios-trie-benchmark {bench}, sweep {srcs[0]}:\n"
        f"# bucket lock + SW txn / seqlock baseline, as that tree's\n"
        f"# scripts/plot_dcache_bucketlock_summary.py computes it.\n")


def write(name, fields, recs):
    path = os.path.join(OUT, name)
    with open(path, "w", newline="") as f:
        f.write(head)
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        w.writerows(recs)
    print("wrote", path)


for r in summary:
    r.update(sweep=srcs[0], bench=bench)
write("dcache-summary.csv",
      ["y", "hdr", "key", "group", "n", "lo", "med", "hi", "sweep", "bench"],
      summary)
write("dcache-summary-points.csv", ["y", "key", *GROUPS], points)

path = os.path.join(OUT, "dcache-summary-macros.tex")
with open(path, "w") as f:
    f.write(head.replace("#", "%"))
    f.write(f"\\def\\dcacheSweep{{{srcs[0]}}}\n\\def\\dcacheBench{{{bench}}}\n")
    for r in summary:
        if not r["hdr"]:
            for col in ("lo", "med", "hi"):
                f.write(f"\\expandafter\\def\\csname dcv/{r['key']}/{col}"
                        f"\\endcsname{{{float(r[col]):.2f}}}\n")
print("wrote", path)
