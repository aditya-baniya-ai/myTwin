"""Is the improvement real, or 16 people's worth of noise?
Paired comparison per person: your own running average vs running average + sleep features."""
import warnings, numpy as np, pandas as pd
from scipy.stats import spearmanr, wilcoxon
from sklearn.linear_model import RidgeCV
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
warnings.filterwarnings("ignore")
import train_pmdata as T
df = T.df
rng = np.random.default_rng(0)
COLS = ["overall_score_z", "asleep_z", "efficiency"]

for target in ["fatigue", "readiness"]:
    d = df[df[target].notna()].copy()
    d["run_mean"] = d.groupby("person")[target].transform(
        lambda s: s.shift(1).expanding(min_periods=7).mean())
    y, g, base = d[target].values, d.person.values, d.run_mean.values
    X = d[[c for c in COLS if c in d]].apply(pd.to_numeric, errors="coerce")

    pred = np.full(len(d), np.nan)
    for u in np.unique(g):
        te, tr = g == u, g != u
        dev = y[tr] - base[tr]; ok = ~np.isnan(dev)
        m = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(),
                          RidgeCV(alphas=[1, 10, 100, 1000]))
        m.fit(X[tr][ok], dev[ok]); pred[te] = base[te] + m.predict(X[te])

    rows = []
    for u in np.unique(g):
        m = (g == u) & ~np.isnan(pred) & ~np.isnan(base) & ~np.isnan(y)
        if m.sum() < 20 or np.std(y[m]) == 0: continue
        r_base = spearmanr(y[m], base[m]).statistic if np.std(base[m]) > 1e-9 else np.nan
        r_model = spearmanr(y[m], pred[m]).statistic if np.std(pred[m]) > 1e-9 else np.nan
        rows.append(dict(person=u, days=int(m.sum()), baseline=r_base, model=r_model,
                         mae_base=np.mean(np.abs(y[m]-base[m])), mae_model=np.mean(np.abs(y[m]-pred[m]))))
    t = pd.DataFrame(rows).dropna()
    diff = (t.model - t.baseline).values

    print(f"\n=== {target}: per-person correlation with what they actually reported ===")
    print(t.round(3).to_string(index=False))
    better = int((diff > 0).sum())
    stat, p = wilcoxon(t.model, t.baseline)
    boot = [rng.choice(diff, len(diff), replace=True).mean() for _ in range(5000)]
    lo, hi = np.percentile(boot, [2.5, 97.5])
    print(f"\n  improved for {better}/{len(t)} people | mean gain {diff.mean():+.3f} "
          f"(95% CI {lo:+.3f} to {hi:+.3f}) | Wilcoxon p = {p:.3f}")
    print(f"  MAE: baseline {t.mae_base.mean():.3f} -> model {t.mae_model.mean():.3f}")
