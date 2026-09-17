"""Train the model the app ships, and export it as plain numbers.

The model is deliberately tiny: each person's own running average, plus a ridge
regression on three sleep features that nudges it up or down. A linear model needs
no Core ML runtime - the app can compute `intercept + sum(weight * feature)` directly.

Run:  python train_final.py
Reads data/pmdata_features.csv, writes model/energy_model.json
"""
import json
import pathlib
import warnings

import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import RidgeCV

warnings.filterwarnings("ignore")

FEATURES = ["overall_score_z", "asleep_z", "efficiency"]
TARGETS = ["fatigue", "readiness"]
MIN_HISTORY = 7          # days of your own reports before the app says anything
BASELINE_WINDOW = 14     # days used for the rolling "your normal"

here = pathlib.Path(__file__).parent
df = pd.read_csv(here / "data" / "pmdata_features.csv")


def running_mean(frame, target):
    return frame.groupby("person")[target].transform(
        lambda s: s.shift(1).expanding(min_periods=MIN_HISTORY).mean())


def leave_one_person_out(frame, target):
    """The honest check: never score a person using their own data in training."""
    y = frame[target].values
    people = frame.person.values
    base = frame["run_mean"].values
    X = frame[FEATURES].apply(pd.to_numeric, errors="coerce")
    pred = np.full(len(frame), np.nan)

    for person in np.unique(people):
        test, train = people == person, people != person
        deviation = y[train] - base[train]
        usable = ~np.isnan(deviation)
        model = build_model()
        model.fit(fill(X[train][usable]), deviation[usable])
        pred[test] = base[test] + model.predict(fill(X[test]))

    gains = []
    for person in np.unique(people):
        m = (people == person) & ~np.isnan(pred) & ~np.isnan(base)
        if m.sum() < 20 or np.std(y[m]) == 0:
            continue
        if np.std(base[m]) > 1e-9 and np.std(pred[m]) > 1e-9:
            gains.append(spearmanr(y[m], pred[m]).statistic - spearmanr(y[m], base[m]).statistic)
    return np.array(gains)


def fill(frame):
    return frame.fillna(frame.median(numeric_only=True)).fillna(0)


def build_model():
    return RidgeCV(alphas=[1, 10, 100, 1000])


export = {"baseline_window_days": BASELINE_WINDOW, "min_history_days": MIN_HISTORY, "targets": {}}

for target in TARGETS:
    frame = df[df[target].notna()].copy()
    frame["run_mean"] = running_mean(frame, target)

    gains = leave_one_person_out(frame, target)
    print(f"\n=== {target} ===")
    print(f"  leave-one-person-out: helped {int((gains > 0).sum())}/{len(gains)} people, "
          f"mean correlation gain {gains.mean():+.3f}")

    # Final fit uses everyone, because the shipped model has never met the user.
    X = fill(frame[FEATURES].apply(pd.to_numeric, errors="coerce"))
    deviation = frame[target].values - frame["run_mean"].values
    usable = ~np.isnan(deviation)
    model = build_model().fit(X[usable], deviation[usable])

    # The app standardises features the same way, using these stats.
    stats = {c: {"mean": float(X[c].mean()), "std": float(X[c].std() or 1.0)} for c in FEATURES}
    export["targets"][target] = {
        "intercept": float(model.intercept_),
        "weights": {c: float(w) for c, w in zip(FEATURES, model.coef_)},
        "feature_stats": stats,
        "scale": {"min": float(df[target].min()), "max": float(df[target].max())},
        "people": int(frame.person.nunique()),
        "days": int(len(frame)),
        "mean_correlation_gain": float(gains.mean()),
        "people_helped": f"{int((gains > 0).sum())}/{len(gains)}",
    }
    for name, weight in export["targets"][target]["weights"].items():
        print(f"  {name:20s} weight {weight:+.4f}")
    print(f"  intercept {model.intercept_:+.4f}")

out = here / "model" / "energy_model.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(export, indent=2))
print(f"\nwrote {out} ({out.stat().st_size} bytes)")
