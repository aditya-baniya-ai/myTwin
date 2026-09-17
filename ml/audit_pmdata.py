"""Is my join correct? Self-reported sleep hours should track Fitbit's measured sleep.
If they don't, the negative result is my bug, not the data."""
import json, pathlib, warnings
import numpy as np, pandas as pd
from scipy.stats import spearmanr
warnings.filterwarnings("ignore")
ROOT = pathlib.Path("data/pmdata_hf")

def sleep_of(d):
    rows = []
    for s in json.loads((d / "fitbit" / "sleep.json").read_text()):
        rows.append(dict(date=pd.to_datetime(s["dateOfSleep"]).date(),
                         asleep=s.get("minutesAsleep"), eff=s.get("efficiency")))
    s = pd.DataFrame(rows)
    return s.sort_values("asleep").groupby("date", as_index=False).last() if len(s) else s

print("=== alignment check: self-reported sleep hours vs Fitbit minutes asleep ===")
print("(shift 0 should be strongest if the join is right)\n")
for shift in (-1, 0, 1):
    rs, pooled = [], []
    for d in sorted(ROOT.glob("p*")):
        w = pd.read_csv(d / "pmsys" / "wellness.csv")
        w["date"] = pd.to_datetime(w.effective_time_frame, format="mixed", utc=True).dt.date
        s = sleep_of(d)
        if not len(s): continue
        s = s.copy(); s["date"] = pd.to_datetime(s.date) + pd.Timedelta(days=shift)
        s["date"] = s.date.dt.date
        m = w.merge(s, on="date", how="inner").dropna(subset=["sleep_duration_h","asleep"])
        if len(m) > 20:
            rs.append(spearmanr(m.sleep_duration_h, m.asleep).statistic)
            pooled.append(m[["sleep_duration_h","asleep"]])
    allm = pd.concat(pooled)
    print(f"  shift {shift:+d} day: mean per-person r = {np.nanmean(rs):+.3f} | "
          f"pooled r = {spearmanr(allm.sleep_duration_h, allm.asleep).statistic:+.3f} | matched rows {len(allm)}")

print("\n=== feature coverage in the modelling table ===")
import train_pmdata as T   # reuse the same builder
df, feats = T.df, T.feats
print(f"rows {len(df)}")
cov = df[feats].apply(lambda c: pd.to_numeric(c, errors="coerce").notna().mean()).sort_values()
print("\nworst-covered features:")
for k, v in cov.head(10).items(): print(f"  {k:34s} {100*v:5.1f}%")
print("\nkey features:")
for k in ["asleep","efficiency","deep","rem","resting_heart_rate","overall_score",
          "steps_yday","very_active_minutes_yday","load_yday"]:
    if k in cov: print(f"  {k:34s} {100*cov[k]:5.1f}%")
