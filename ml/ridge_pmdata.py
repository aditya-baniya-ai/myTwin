"""Last honest attempt: a strongly regularized linear model on a few sleep features,
added to each person's running average. Fewer knobs than LightGBM, so less room to overfit."""
import warnings, numpy as np, pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import RidgeCV
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
warnings.filterwarnings("ignore")
import train_pmdata as T
df = T.df

SETS = {
    "sleep score only":      ["overall_score_z"],
    "3 sleep features":      ["overall_score_z", "asleep_z", "efficiency"],
    "5 features + resting HR": ["overall_score_z", "revitalization_score", "asleep_z",
                                "efficiency", "resting_heart_rate_z"],
}

for target in ["readiness", "fatigue"]:
    d = df[df[target].notna()].copy()
    d["run_mean"] = d.groupby("person")[target].transform(
        lambda s: s.shift(1).expanding(min_periods=7).mean())
    y, g = d[target].values, d.person.values
    base = d.run_mean.values

    def report(name, p):
        m = ~np.isnan(p) & ~np.isnan(y)
        rs = [spearmanr(y[(g == u) & m], p[(g == u) & m]).statistic for u in np.unique(g)
              if ((g == u) & m).sum() > 10 and np.std(p[(g == u) & m]) > 1e-9]
        rs = [r for r in rs if np.isfinite(r)]
        print(f"  {name:32s} MAE {np.mean(np.abs(y[m] - p[m])):.3f} | "
              f"within-person Spearman {np.mean(rs):+.3f}")

    print(f"\n=== {target} (n={len(d)}, {d.person.nunique()} people) ===")
    report("your own running average", base)

    for name, cols in SETS.items():
        cols = [c for c in cols if c in d.columns]
        if not cols: continue
        X = d[cols].apply(pd.to_numeric, errors="coerce")
        pred = np.full(len(d), np.nan)
        for u in np.unique(g):
            te, tr = g == u, g != u
            dev = y[tr] - base[tr]
            ok = ~np.isnan(dev)
            if ok.sum() < 50: continue
            model = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(),
                                  RidgeCV(alphas=[1, 10, 100, 1000]))
            model.fit(X[tr][ok], dev[ok])
            pred[te] = base[te] + model.predict(X[te])
        report(f"running avg + {name}", pred)
