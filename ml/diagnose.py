"""Is there any within-person signal, and does the wearable add anything on top of the clock?"""
import numpy as np, pandas as pd, warnings
from scipy.stats import spearmanr
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
warnings.filterwarnings("ignore")

B = "data/lifesnaps/rais_anonymized/csv_rais_anonymized/"
MOOD = ['ALERT','HAPPY','NEUTRAL','RESTED/RELAXED','SAD','TENSE/ANXIOUS','TIRED']
h = pd.read_csv(B + "hourly_fitbit_sema_df_unprocessed.csv", low_memory=False)
d = pd.read_csv(B + "daily_fitbit_sema_df_unprocessed.csv", low_memory=False)
night = d[["id","date","sleep_duration","sleep_efficiency","resting_hr","rmssd"]]
h = h.merge(night, on=["id","date"], how="left")
h["date"] = pd.to_datetime(h.date); h = h.sort_values(["id","date","hour"])
for c in ["steps","bpm","scl_avg"]: h[c] = pd.to_numeric(h[c], errors="coerce")
g = h.groupby("id")
h["bpm_z"] = (h.bpm - g.bpm.transform("mean")) / g.bpm.transform("std")
h["steps_3h"] = g.steps.transform(lambda s: s.rolling(3, min_periods=1).sum())
for c in ["sleep_duration","resting_hr","rmssd"]:
    gg = h.groupby("id")[c]
    h[c+"_z"] = (h[c] - gg.transform("mean")) / gg.transform("std")

h = h[h[MOOD].notna().any(axis=1)].copy()
cnt = h.groupby("id").size(); h = h[h.id.isin(cnt[cnt>=30].index)]
h["TIRED"] = h.TIRED.fillna(0).astype(int)

print("=== within-person association with feeling tired ===")
print("(mean Spearman r across people, and how many people show a real association)")
sig = ["hour","bpm_z","steps_3h","sleep_duration_z","resting_hr_z","rmssd_z","scl_avg"]
for c in sig:
    rs = []
    for u, grp in h.groupby("id"):
        s = grp[[c,"TIRED"]].dropna()
        if len(s) >= 25 and s.TIRED.nunique() == 2 and s[c].nunique() > 3:
            rs.append(spearmanr(s[c], s.TIRED).statistic)
    rs = np.array([r for r in rs if np.isfinite(r)])
    if len(rs):
        print(f"  {c:18s} mean r {rs.mean():+.3f} | |r|>0.2 in {100*np.mean(np.abs(rs)>0.2):4.0f}% of {len(rs)} people")

print("\n=== fair nested test: clock alone vs clock + wearable (same simple model) ===")
y = h.TIRED.values; groups = h.id.values
sets = {"hour only": ["hour"],
        "hour + wearable": ["hour","bpm_z","steps_3h","sleep_duration_z","resting_hr_z"],
        "wearable only": ["bpm_z","steps_3h","sleep_duration_z","resting_hr_z"]}
for name, cols in sets.items():
    X = h[cols].apply(pd.to_numeric, errors="coerce")
    p = np.zeros(len(h))
    for u in np.unique(groups):
        te, tr = groups==u, groups!=u
        lr = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(),
                           LogisticRegression(max_iter=2000, class_weight="balanced"))
        lr.fit(X[tr], y[tr]); p[te] = lr.predict_proba(X[te])[:,1]
    per = [roc_auc_score(y[groups==u], p[groups==u]) for u in np.unique(groups)
           if len(np.unique(y[groups==u]))==2]
    print(f"  {name:18s} per-user AUC {np.mean(per):.3f}   global AUC {roc_auc_score(y,p):.3f}")
