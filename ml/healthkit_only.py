"""What is the model worth using only signals ANY watch can deliver via HealthKit?

Fitbit's sleep score is proprietary: Apple Watch and Garmin users cannot provide it.
So compare three feature sets, all against each person's own running average.
"""
import warnings, numpy as np, pandas as pd
from scipy.stats import spearmanr, wilcoxon
from sklearn.linear_model import RidgeCV
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
warnings.filterwarnings("ignore")

df = pd.read_csv("data/pmdata_features.csv")

SETS = {
    "shipped (uses Fitbit sleep score)": ["overall_score_z", "asleep_z", "efficiency"],
    "HealthKit only (any watch)":        ["asleep_z", "efficiency", "deep_z", "rem_z",
                                          "resting_heart_rate_z"],
    "HealthKit, minimal":                ["asleep_z", "efficiency"],
}

for target in ["fatigue", "readiness"]:
    d = df[df[target].notna()].copy()
    d["run_mean"] = d.groupby("person")[target].transform(
        lambda s: s.shift(1).expanding(min_periods=7).mean())
    y, g, base = d[target].values, d.person.values, d.run_mean.values
    print(f"\n=== {target} ===")

    for name, cols in SETS.items():
        cols = [c for c in cols if c in d.columns]
        X = d[cols].apply(pd.to_numeric, errors="coerce")
        pred = np.full(len(d), np.nan)
        for u in np.unique(g):
            te, tr = g == u, g != u
            dev = y[tr] - base[tr]; ok = ~np.isnan(dev)
            m = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(),
                              RidgeCV(alphas=[1, 10, 100, 1000]))
            m.fit(X[tr][ok], dev[ok]); pred[te] = base[te] + m.predict(X[te])

        gains, rs = [], []
        for u in np.unique(g):
            m_ = (g == u) & ~np.isnan(pred) & ~np.isnan(base)
            if m_.sum() < 20 or np.std(y[m_]) == 0: continue
            if np.std(base[m_]) > 1e-9 and np.std(pred[m_]) > 1e-9:
                r_model = spearmanr(y[m_], pred[m_]).statistic
                r_base = spearmanr(y[m_], base[m_]).statistic
                rs.append(r_model); gains.append(r_model - r_base)
        gains = np.array(gains)
        p = wilcoxon(gains).pvalue if len(gains) > 5 else float("nan")
        print(f"  {name:36s} correlation {np.mean(rs):+.3f} | "
              f"gain {gains.mean():+.3f} | helped {int((gains>0).sum())}/{len(gains)} | p {p:.3f}")
