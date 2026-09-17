"""Discover what PMData actually contains, without assuming its layout.

PMData is the dataset that matters most: unlike LifeSnaps' yes/no mood flags, it has
graded daily self-reports (fatigue 1-5, readiness 0-10) from 16 people over 5 months.
"""
import json
import pathlib
import pandas as pd

ROOT = pathlib.Path("data/pmdata")

if not ROOT.exists():
    raise SystemExit(f"{ROOT} not found - unzip pmdata.zip there first")

print("=== participants ===")
people = sorted(p for p in ROOT.rglob("*") if p.is_dir() and p.name.startswith("p"))
top = [p for p in people if p.parent == ROOT or p.parent.name in {"pmdata", "PMData"}]
print(f"folders that look like participants: {len(top)} -> {[p.name for p in top[:20]]}")

print("\n=== file types and sizes (whole dataset) ===")
sizes, counts = {}, {}
for f in ROOT.rglob("*"):
    if f.is_file():
        key = f.suffix.lower() or "(none)"
        sizes[key] = sizes.get(key, 0) + f.stat().st_size
        counts[key] = counts.get(key, 0) + 1
for k in sorted(sizes, key=lambda k: -sizes[k]):
    print(f"  {k:8s} {counts[k]:5d} files  {sizes[k]/1e6:9.1f} MB")

sample = top[0] if top else ROOT
print(f"\n=== layout of one participant ({sample.name}) ===")
for f in sorted(sample.rglob("*")):
    if f.is_file():
        print(f"  {f.stat().st_size/1024:9.1f} KB  {f.relative_to(sample)}")

print("\n=== self-report CSVs: columns, scales and coverage ===")
for csv in sorted(sample.rglob("*.csv")):
    try:
        df = pd.read_csv(csv)
    except Exception as exc:
        print(f"  {csv.name}: could not read ({exc})")
        continue
    print(f"\n  {csv.relative_to(sample)}  rows={len(df)}")
    print(f"    columns: {list(df.columns)}")
    for col in df.columns:
        if df[col].dtype.kind in "if":
            print(f"      {col:20s} min {df[col].min()} max {df[col].max()} "
                  f"mean {df[col].mean():.2f} non-null {df[col].notna().sum()}")

print("\n=== Fitbit JSON files: top-level shape of each ===")
for js in sorted(sample.rglob("*.json"))[:12]:
    try:
        with open(js) as fh:
            data = json.load(fh)
    except Exception as exc:
        print(f"  {js.name}: could not read ({exc})")
        continue
    if isinstance(data, list) and data:
        print(f"  {js.name:34s} list of {len(data)} | keys: {list(data[0])[:8]}")
    elif isinstance(data, dict):
        print(f"  {js.name:34s} dict | keys: {list(data)[:8]}")

print("\n=== how many labelled days per person (wellness reports) ===")
rows = []
for person in top:
    for csv in person.rglob("*.csv"):
        if "wellness" in csv.name.lower():
            try:
                df = pd.read_csv(csv)
                rows.append(dict(person=person.name, days=len(df),
                                 cols=";".join(df.columns[:8])))
            except Exception:
                pass
if rows:
    summary = pd.DataFrame(rows)
    print(summary.to_string(index=False))
    print(f"\ntotal labelled days across people: {summary.days.sum()}")
