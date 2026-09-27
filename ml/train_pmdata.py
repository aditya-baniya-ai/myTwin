"""PMData: predict next-morning readiness/fatigue from the night and day before.

Two settings, because they answer different questions:
  cold start  - a brand new user, model trained only on other people
  personal    - the app knows your own running average; does the wearable add anything on top?
"""
import json, pathlib, warnings
import numpy as np, pandas as pd
from scipy.stats import spearmanr
import lightgbm as lgb
warnings.filterwarnings("ignore")

ROOT = pathlib.Path(__file__).resolve().parent / "data/pmdata_hf"

def load_json(p):
    return json.loads(p.read_text()) if p.exists() else []

def person_frame(d):
    """One row per day for this participant."""
    w = pd.read_csv(d / "pmsys" / "wellness.csv")
    w["date"] = pd.to_datetime(w.effective_time_frame, format="mixed", utc=True).dt.date
    w["report_hour"] = pd.to_datetime(w.effective_time_frame, format="mixed", utc=True).dt.hour
    w = w[["date","report_hour","fatigue","mood","readiness","sleep_quality","stress","sleep_duration_h"]]

    # last night's sleep (Fitbit dates a session by the morning you woke up)
    rows = []
    for s in load_json(d / "fitbit" / "sleep.json"):
        lv = (s.get("levels") or {}).get("summary") or {}
        rows.append(dict(date=pd.to_datetime(s["dateOfSleep"]).date(),
                         asleep=s.get("minutesAsleep"), awake=s.get("minutesAwake"),
                         to_fall_asleep=s.get("minutesToFallAsleep"), in_bed=s.get("timeInBed"),
                         efficiency=s.get("efficiency"),
                         deep=(lv.get("deep") or {}).get("minutes"),
                         rem=(lv.get("rem") or {}).get("minutes"),
                         light=(lv.get("light") or {}).get("minutes"),
                         wake_min=(lv.get("wake") or {}).get("minutes"),
                         bed_hour=pd.to_datetime(s["startTime"]).hour,
                         wake_hour=pd.to_datetime(s["endTime"]).hour))
    sleep = pd.DataFrame(rows)
    if len(sleep):
        sleep = sleep.sort_values("asleep").groupby("date", as_index=False).last()  # main sleep

    ss = pd.DataFrame()
    f = d / "fitbit" / "sleep_score.csv"
    if f.exists():
        ss = pd.read_csv(f)
        ss["date"] = pd.to_datetime(ss.timestamp, format="mixed", utc=True).dt.date
        ss = ss[["date","overall_score","composition_score","revitalization_score",
                 "duration_score","resting_heart_rate","restlessness"]].rename(
                 columns={"resting_heart_rate": "sleep_rhr"})
        ss = ss.groupby("date", as_index=False).last()

    daily = {}
    for name in ["resting_heart_rate","lightly_active_minutes","moderately_active_minutes",
                 "very_active_minutes","sedentary_minutes"]:
        recs = load_json(d / "fitbit" / f"{name}.json")
        if not recs: continue
        vals = [(pd.to_datetime(r["dateTime"]).date(),
                 float(r["value"]["value"]) if isinstance(r["value"], dict) else float(r["value"]))
                for r in recs]
        daily[name] = pd.DataFrame(vals, columns=["date", name]).groupby("date", as_index=False).last()

    steps = load_json(d / "fitbit" / "steps.json")
    if steps:
        sdf = pd.DataFrame([(pd.to_datetime(r["dateTime"]).date(), float(r["value"])) for r in steps],
                           columns=["date","steps"])
        daily["steps"] = sdf.groupby("date", as_index=False).sum()

    load = pd.DataFrame()
    f = d / "pmsys" / "srpe.csv"
    if f.exists():
        s = pd.read_csv(f)
        s["date"] = pd.to_datetime(s.end_date_time, format="mixed", utc=True).dt.date
        s["load"] = s.perceived_exertion * s.duration_min
        load = s.groupby("date", as_index=False).agg(load=("load","sum"), sessions=("load","size"))

    out = w
    for part in [sleep, ss, load] + list(daily.values()):
        if len(part): out = out.merge(part, on="date", how="left")
    out["person"] = d.name
    return out

frames = [person_frame(d) for d in sorted(ROOT.glob("p*")) if (d / "pmsys" / "wellness.csv").exists()]
if not frames:
    raise SystemExit("No PMData files. Run download_pmdata.py first.")
df = pd.concat(frames, ignore_index=True)
df["date"] = pd.to_datetime(df.date)
df = df.sort_values(["person","date"]).reset_index(drop=True)

SAME_NIGHT = ["asleep","awake","to_fall_asleep","in_bed","efficiency","deep","rem","light","wake_min",
              "bed_hour","wake_hour","overall_score","composition_score","revitalization_score",
              "duration_score","sleep_rhr","resting_heart_rate","restlessness"]
PRIOR_DAY = ["steps","very_active_minutes","moderately_active_minutes","lightly_active_minutes",
             "sedentary_minutes","load","sessions"]

feats = []
for c in SAME_NIGHT:
    if c in df: feats.append(c)
for c in PRIOR_DAY:                      # yesterday's effort, known before this morning's report
    if c in df:
        df[c + "_yday"] = df.groupby("person")[c].shift(1); feats.append(c + "_yday")
for c in [c for c in SAME_NIGHT + [p + "_yday" for p in PRIOR_DAY] if c in df]:
    g = df.groupby("person")[c]
    base = g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).mean())
    sd = g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).std()).replace(0, np.nan)
    df[c + "_z"] = (df[c] - base) / sd; feats.append(c + "_z")
df["dow"] = df.date.dt.dayofweek; feats.append("dow")
feats.append("report_hour")

def evaluate(target, use_feats=None, label=''):
    d = df[df[target].notna()].copy()
    d["run_mean"] = d.groupby("person")[target].transform(lambda s: s.shift(1).expanding(min_periods=7).mean())
    X = d[(use_feats or feats)].apply(pd.to_numeric, errors="coerce")
    y = d[target].values
    g = d.person.values

    cold = np.zeros(len(d)); pers = np.zeros(len(d))
    for p in np.unique(g):
        te, tr = g == p, g != p
        m = lgb.LGBMRegressor(n_estimators=400, learning_rate=0.05, num_leaves=15,
                              min_child_samples=30, subsample=0.8, colsample_bytree=0.7, verbose=-1)
        m.fit(X[tr], y[tr]); cold[te] = m.predict(X[te])
        dev = y[tr] - d.run_mean.values[tr]
        ok = ~np.isnan(dev)
        m2 = lgb.LGBMRegressor(n_estimators=400, learning_rate=0.05, num_leaves=15,
                               min_child_samples=30, subsample=0.8, colsample_bytree=0.7, verbose=-1)
        m2.fit(X[tr][ok], dev[ok]); pers[te] = d.run_mean.values[te] + m2.predict(X[te])

    def report(name, p):
        m = ~np.isnan(p) & ~np.isnan(y)
        rs = [spearmanr(y[(g==u)&m], p[(g==u)&m]).statistic for u in np.unique(g)
              if ((g==u)&m).sum() > 10 and np.std(p[(g==u)&m]) > 1e-9]
        rs = [r for r in rs if np.isfinite(r)]
        print(f"  {name:34s} MAE {np.mean(np.abs(y[m]-p[m])):.3f} | within-person Spearman {np.mean(rs):+.3f}")

    print(f"\n=== {target}{label} (n={len(d)}, {d.person.nunique()} people, SD {y.std():.2f}, {len(use_feats or feats)} features) ===")
    report("everyone's average", np.full(len(d), y.mean()))
    report("your own running average", d.run_mean.values)
    report("cold start: model, no history", cold)
    report("personal: your average + model", pers)

LEAN = [c for c in ["asleep","efficiency","deep","rem","overall_score","revitalization_score",
        "restlessness","sleep_rhr","resting_heart_rate","steps_yday","very_active_minutes_yday",
        "dow","asleep_z","overall_score_z","resting_heart_rate_z","steps_yday_z"] if c in feats]

if __name__ == "__main__":
    df.to_csv(ROOT.parent / "pmdata_features.csv", index=False)
    print("Exported data/pmdata_features.csv")
    for t in ["readiness", "fatigue"]:
        evaluate(t, label=" [all features]")
        evaluate(t, LEAN, label=" [lean]")
