"""Does a longer baseline window hurt? People who wear a watch irregularly have few
recent nights, so a 14-day window may find nothing to compare against."""
import warnings, numpy as np, pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import RidgeCV
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
warnings.filterwarnings("ignore")

RAW = {"asleep_z": "asleep", "deep_z": "deep", "rem_z": "rem",
       "resting_heart_rate_z": "resting_heart_rate"}
FEATURES = ["asleep_z", "efficiency", "deep_z", "rem_z", "resting_heart_rate_z"]

base = pd.read_csv("data/pmdata_features.csv")
base["date"] = pd.to_datetime(base["date"])
base = base.sort_values(["person", "date"])

def rebuild(window):
    d = base.copy()
    for zname, raw in RAW.items():
        g = d.groupby("person")[raw]
        mean = g.transform(lambda s: s.shift(1).rolling(window, min_periods=3).mean())
        sd = g.transform(lambda s: s.shift(1).rolling(window, min_periods=3).std()).replace(0, np.nan)
        d[zname] = (d[raw] - mean) / sd
    return d

print(f"{'window':>8} {'usable days':>12} {'fatigue gain':>14} {'readiness gain':>16}")
for window in [7, 14, 30, 45, 60]:
    d = rebuild(window)
    line = [f"{window:>6}d"]
    usable = None
    for target in ["fatigue", "readiness"]:
        f = d[d[target].notna()].copy()
        f["run_mean"] = f.groupby("person")[target].transform(
            lambda s: s.shift(1).expanding(min_periods=7).mean())
        y, g, bs = f[target].values, f.person.values, f.run_mean.values
        X = f[FEATURES].apply(pd.to_numeric, errors="coerce")
        if usable is None:
            usable = int(X.notna().all(axis=1).sum())
        pred = np.full(len(f), np.nan)
        for u in np.unique(g):
            te, tr = g == u, g != u
            dev = y[tr] - bs[tr]; ok = ~np.isnan(dev)
            m = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(),
                              RidgeCV(alphas=[1, 10, 100, 1000]))
            m.fit(X[tr][ok], dev[ok]); pred[te] = bs[te] + m.predict(X[te])
        gains = []
        for u in np.unique(g):
            mask = (g == u) & ~np.isnan(pred) & ~np.isnan(bs)
            if mask.sum() < 20 or np.std(y[mask]) == 0: continue
            if np.std(bs[mask]) > 1e-9 and np.std(pred[mask]) > 1e-9:
                gains.append(spearmanr(y[mask], pred[mask]).statistic
                             - spearmanr(y[mask], bs[mask]).statistic)
        line.append(f"{np.mean(gains):+.3f}")
    print(f"{line[0]:>8} {usable:>12} {line[1]:>14} {line[2]:>16}")
