"""LifeSnaps: predict how tired someone feels from wearable signals.

Honest evaluation: leave-one-subject-out, compared against baselines that need no model.
"""
import numpy as np, pandas as pd, warnings
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
import lightgbm as lgb

warnings.filterwarnings("ignore")
BASE = "data/lifesnaps/rais_anonymized/csv_rais_anonymized/"
MOOD = ['ALERT','HAPPY','NEUTRAL','RESTED/RELAXED','SAD','TENSE/ANXIOUS','TIRED']

RAW = ["sleep_duration","minutesAsleep","minutesAwake","minutesToFallAsleep","sleep_efficiency",
       "sleep_deep_ratio","sleep_rem_ratio","sleep_light_ratio","sleep_wake_ratio",
       "resting_hr","nremhr","rmssd","spo2","full_sleep_breathing_rate","nightly_temperature",
       "stress_score","steps","calories","distance","lightly_active_minutes",
       "moderately_active_minutes","very_active_minutes","sedentary_minutes","bpm"]

def build(df):
    df = df.copy()
    df["date"] = pd.to_datetime(df["date"])
    df = df.sort_values(["id","date"])
    feats = []
    for col in RAW:
        if col not in df: continue
        g = df.groupby("id")[col]
        # how today compares with this person's own recent normal
        base = g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).mean())
        sd = g.transform(lambda s: s.shift(1).rolling(14, min_periods=3).std())
        df[col + "_z"] = (df[col] - base) / sd.replace(0, np.nan)
        df[col + "_yday"] = g.shift(1)
        feats += [col, col + "_z", col + "_yday"]
    df["dow"] = df["date"].dt.dayofweek
    for c in ["age","bmi"]:
        if c in df: feats.append(c)
    feats.append("dow")
    return df, [f for f in feats if f in df.columns]

def evaluate(name, y, p, groups):
    per = []
    for u in np.unique(groups):
        m = groups == u
        if len(np.unique(y[m])) == 2:
            per.append(roc_auc_score(y[m], p[m]))
    return dict(model=name, global_auc=roc_auc_score(y, p),
                per_user_auc=float(np.mean(per)), users_scored=len(per))

def run(target):
    raw = pd.read_csv(BASE + "daily_fitbit_sema_df_unprocessed.csv", low_memory=False)
    df, feats = build(raw)
    df = df[df[MOOD].notna().any(axis=1)].copy()
    counts = df.groupby("id").size()
    df = df[df.id.isin(counts[counts >= 20].index)]          # enough days to score a person
    y = df[target].fillna(0).astype(int).values
    groups = df.id.values
    X = df[feats].apply(pd.to_numeric, errors="coerce")  # age/bmi arrive as text bands

    print(f"\n=== target: {target} ===")
    print(f"rows {len(df)} | users {df.id.nunique()} | positives {100*y.mean():.1f}%")

    preds = {k: np.zeros(len(df)) for k in ["personal_rate","sleep_only","lightgbm"]}
    for u in np.unique(groups):
        te, tr = groups == u, groups != u
        # baseline 1: this person's own historical rate (no wearable data at all)
        preds["personal_rate"][te] = y[tr].mean() if te.sum() == len(y) else df.loc[te, target].fillna(0).mean()
        # baseline 2: sleep duration + resting HR only, logistic regression
        cols = [c for c in ["sleep_duration","resting_hr","sleep_duration_z","resting_hr_z"] if c in feats]
        lr = make_pipeline(SimpleImputer(strategy="median"), StandardScaler(), LogisticRegression(max_iter=1000))
        lr.fit(X.loc[tr, cols], y[tr])
        preds["sleep_only"][te] = lr.predict_proba(X.loc[te, cols])[:, 1]
        # the model under test
        m = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=15,
                               min_child_samples=30, subsample=0.8, colsample_bytree=0.7,
                               class_weight="balanced", verbose=-1)
        m.fit(X[tr], y[tr])
        preds["lightgbm"][te] = m.predict_proba(X[te])[:, 1]

    rows = [evaluate(k, y, v, groups) for k, v in preds.items()]
    print(pd.DataFrame(rows).round(3).to_string(index=False))

    m = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.05, num_leaves=15,
                           min_child_samples=30, class_weight="balanced", verbose=-1).fit(X, y)
    imp = pd.Series(m.feature_importances_, index=feats).sort_values(ascending=False).head(12)
    print("\ntop features:", ", ".join(f"{k}" for k in imp.index))

for t in ["TIRED", "RESTED/RELAXED"]:
    run(t)
