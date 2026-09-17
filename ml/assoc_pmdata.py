"""Within each person, does any wearable signal actually track readiness or fatigue?"""
import warnings, numpy as np, pandas as pd
from scipy.stats import spearmanr
warnings.filterwarnings("ignore")
import train_pmdata as T
df = T.df

SIGNALS = ["asleep","efficiency","deep","rem","wake_min","bed_hour","wake_hour","overall_score",
           "revitalization_score","resting_heart_rate","restlessness",
           "steps_yday","very_active_minutes_yday","sedentary_minutes_yday","load_yday",
           "asleep_z","resting_heart_rate_z","overall_score_z","steps_yday_z","load_yday_z"]

for target in ["readiness","fatigue"]:
    print(f"\n=== within-person association with {target} ===")
    print("(mean Spearman across people; |r|>0.2 share shows how many people it works for)")
    out = []
    for c in SIGNALS:
        if c not in df: continue
        rs = []
        for p, g in df.groupby("person"):
            s = g[[c, target]].apply(pd.to_numeric, errors="coerce").dropna()
            if len(s) >= 30 and s[c].nunique() > 3 and s[target].nunique() > 1:
                r = spearmanr(s[c], s[target]).statistic
                if np.isfinite(r): rs.append(r)
        if len(rs) >= 8:
            out.append((c, np.mean(rs), np.mean(np.abs(np.array(rs)) > 0.2), len(rs)))
    out.sort(key=lambda t: -abs(t[1]))
    for c, m, share, n in out:
        print(f"  {c:28s} mean r {m:+.3f} | |r|>0.2 in {100*share:3.0f}% of {n} people")

    # how much of the target is explained by the person alone
    g = df.dropna(subset=[target])
    within = g.groupby("person")[target].std().mean()
    print(f"  --> within-person SD {within:.2f} vs overall SD {g[target].std():.2f}")
