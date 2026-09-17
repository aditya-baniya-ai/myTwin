"""Hourly LifeSnaps: does the wearable predict feeling tired at a given hour,
beyond simply knowing what time of day it is?"""
import numpy as np, pandas as pd, warnings
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
import lightgbm as lgb
warnings.filterwarnings("ignore")

B = "data/lifesnaps/rais_anonymized/csv_rais_anonymized/"
MOOD = ['ALERT','HAPPY','NEUTRAL','RESTED/RELAXED','SAD','TENSE/ANXIOUS','TIRED']

h = pd.read_csv(B + "hourly_fitbit_sema_df_unprocessed.csv", low_memory=False)
d = pd.read_csv(B + "daily_fitbit_sema_df_unprocessed.csv", low_memory=False)

# last night's sleep and today's overnight vitals, attached to each hour of that day
night = d[["id","date","sleep_duration","sleep_efficiency","sleep_deep_ratio","sleep_rem_ratio",
           "minutesAsleep","minutesAwake","resting_hr","rmssd","spo2","nightly_temperature",
           "full_sleep_breathing_rate","stress_score"]].copy()
h = h.merge(night, on=["id","date"], how="left", suffixes=("","_night"))

h["date"] = pd.to_datetime(h["date"])
h = h.sort_values(["id","date","hour"])
h["steps"] = pd.to_numeric(h["steps"], errors="coerce")
h["bpm"] = pd.to_numeric(h["bpm"], errors="coerce")

g = h.groupby("id")
h["bpm_z"] = (h.bpm - g.bpm.transform("mean")) / g.bpm.transform("std")
h["steps_3h"] = g.steps.transform(lambda s: s.rolling(3, min_periods=1).sum())
h["steps_today"] = h.groupby(["id","date"]).steps.cumsum()
h["dow"] = h.date.dt.dayofweek
for c in ["sleep_duration","resting_hr","rmssd"]:
    gg = h.groupby("id")[c]
    h[c + "_z"] = (h[c] - gg.transform("mean")) / gg.transform("std")

FEATS = ["hour","dow","bpm","bpm_z","steps","steps_3h","steps_today","scl_avg",
         "sleep_duration","sleep_duration_z","sleep_efficiency","sleep_deep_ratio","sleep_rem_ratio",
         "minutesAsleep","minutesAwake","resting_hr","resting_hr_z","rmssd","rmssd_z","spo2",
         "nightly_temperature","full_sleep_breathing_rate","stress_score"]
FEATS = [f for f in FEATS if f in h.columns]

lab = h[MOOD].notna().any(axis=1)
h = h[lab].copy()
counts = h.groupby("id").size()
h = h[h.id.isin(counts[counts >= 30].index)]
y = h["TIRED"].fillna(0).astype(int).values
groups = h.id.values
X = h[FEATS].apply(pd.to_numeric, errors="coerce")

print(f"labelled hours {len(h)} | users {h.id.nunique()} | tired {100*y.mean():.1f}%")

preds = {k: np.zeros(len(h)) for k in ["personal_rate","hour_only","lightgbm"]}
for u in np.unique(groups):
    te, tr = groups == u, groups != u
    preds["personal_rate"][te] = y[tr].mean()
    lr = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(), LogisticRegression(max_iter=1000))
    lr.fit(X.loc[tr, ["hour"]], y[tr]); preds["hour_only"][te] = lr.predict_proba(X.loc[te, ["hour"]])[:,1]
    m = lgb.LGBMClassifier(n_estimators=400, learning_rate=0.05, num_leaves=31, min_child_samples=20,
                           subsample=0.8, colsample_bytree=0.7, class_weight="balanced", verbose=-1)
    m.fit(X[tr], y[tr]); preds["lightgbm"][te] = m.predict_proba(X[te])[:,1]

rows = []
for k, p in preds.items():
    per = [roc_auc_score(y[groups==u], p[groups==u]) for u in np.unique(groups)
           if len(np.unique(y[groups==u])) == 2]
    rows.append(dict(model=k, global_auc=roc_auc_score(y,p), per_user_auc=np.mean(per), users=len(per)))
print(pd.DataFrame(rows).round(3).to_string(index=False))

m = lgb.LGBMClassifier(n_estimators=400, learning_rate=0.05, num_leaves=31,
                       class_weight="balanced", verbose=-1).fit(X, y)
print("\ntop features:", ", ".join(pd.Series(m.feature_importances_, index=FEATS)
                                   .sort_values(ascending=False).head(10).index))
