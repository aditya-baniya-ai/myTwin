"""Last chance for LifeSnaps: a graded target (share of the day's check-ins marked tired)
instead of a yes/no flag. Compared against predicting each person's own average."""
import numpy as np, pandas as pd, warnings
from scipy.stats import spearmanr
from sklearn.impute import SimpleImputer
import lightgbm as lgb
warnings.filterwarnings("ignore")

B = "data/lifesnaps/rais_anonymized/csv_rais_anonymized/"
MOOD = ['ALERT','HAPPY','NEUTRAL','RESTED/RELAXED','SAD','TENSE/ANXIOUS','TIRED']
h = pd.read_csv(B + "hourly_fitbit_sema_df_unprocessed.csv", low_memory=False)
d = pd.read_csv(B + "daily_fitbit_sema_df_unprocessed.csv", low_memory=False)

lab = h[h[MOOD].notna().any(axis=1)].copy()
per_day = lab.groupby(["id","date"]).agg(n_ema=("TIRED","size"),
                                         tired_frac=("TIRED", lambda s: s.fillna(0).mean())).reset_index()
print("=== how many check-ins per day? (graded target only works if >1) ===")
print(per_day.n_ema.value_counts().sort_index().head(6).to_string())
print(f"days {len(per_day)} | users {per_day.id.nunique()} | mean tired share {per_day.tired_frac.mean():.2f}")

RAW = ["sleep_duration","sleep_efficiency","sleep_deep_ratio","sleep_rem_ratio","minutesAsleep",
       "minutesAwake","resting_hr","nremhr","rmssd","spo2","stress_score","nightly_temperature",
       "steps","calories","very_active_minutes","lightly_active_minutes","sedentary_minutes","bpm"]
d["date_dt"] = pd.to_datetime(d.date); d = d.sort_values(["id","date_dt"])
for c in RAW:
    if c in d:
        g = d.groupby("id")[c]
        d[c+"_z"] = (d[c] - g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).mean())) / \
                     g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).std()).replace(0, np.nan)
        d[c+"_yday"] = g.shift(1)
FEATS = [c for c in d.columns if any(c.startswith(r) for r in RAW)]

m = per_day.merge(d, on=["id","date"], how="left")
m = m[m.n_ema >= 2]                       # only days with a real graded value
cnt = m.groupby("id").size(); m = m[m.id.isin(cnt[cnt >= 20].index)]
y = m.tired_frac.values; groups = m.id.values
X = m[FEATS].apply(pd.to_numeric, errors="coerce")
print(f"\nmodelling rows {len(m)} | users {m.id.nunique()}")

pred_model, pred_base = np.zeros(len(m)), np.zeros(len(m))
for u in np.unique(groups):
    te, tr = groups == u, groups != u
    pred_base[te] = y[tr].mean()
    gb = lgb.LGBMRegressor(n_estimators=400, learning_rate=0.05, num_leaves=15,
                           min_child_samples=30, subsample=0.8, colsample_bytree=0.7, verbose=-1)
    gb.fit(X[tr], y[tr]); pred_model[te] = gb.predict(X[te])

def report(name, p):
    mae = np.mean(np.abs(y - p))
    rs = [spearmanr(y[groups==u], p[groups==u]).statistic for u in np.unique(groups)
          if np.std(p[groups==u]) > 1e-9 and np.std(y[groups==u]) > 1e-9]
    rs = [r for r in rs if np.isfinite(r)]
    print(f"  {name:22s} MAE {mae:.3f} | within-person Spearman {np.mean(rs):+.3f} (n={len(rs)})")

print("\n=== graded target results ===")
report("everyone's average", np.full(len(m), y.mean()))
report("this person's average", pred_base)
report("lightgbm on wearable", pred_model)
