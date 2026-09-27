"""Fit/evaluate the five-feature research model; export coefficients and imputation.

Run from any directory: python3 ml/train_final.py
Requires ml/data/pmdata_features.csv. Evaluation fits imputation on training people only.
The hourly illustration is preserved separately from the learned sleep model.
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, wilcoxon
from sklearn.linear_model import RidgeCV

FEATURES = ["asleep_z", "efficiency", "deep_z", "rem_z", "resting_heart_rate_z"]
TARGETS = ["fatigue", "readiness"]
MIN_HISTORY = 7
BASELINE_WINDOW = 14
HERE = Path(__file__).resolve().parent


def load_data():
    path = HERE / "data/pmdata_features.csv"
    if not path.exists():
        raise SystemExit("Missing ml/data/pmdata_features.csv. Download PMData and run train_pmdata.py first (see ml/README.md).")
    return pd.read_csv(path).sort_values(["person", "date"])


def running_mean(frame, target):
    return frame.groupby("person")[target].transform(
        lambda s: s.shift(1).expanding(min_periods=MIN_HISTORY).mean())


def evaluate(frame, target):
    y, people, base = frame[target].values, frame.person.values, frame.run_mean.values
    X = frame[FEATURES].apply(pd.to_numeric, errors="coerce")
    pred = np.full(len(frame), np.nan)
    for person in np.unique(people):
        test = people == person
        train = ~test & np.isfinite(y - base)
        medians = X.loc[train].median().fillna(0)
        model = RidgeCV(alphas=[1, 10, 100, 1000]).fit(X.loc[train].fillna(medians), (y-base)[train])
        pred[test] = base[test] + model.predict(X.loc[test].fillna(medians))
    rows = []
    for person in np.unique(people):
        mask = (people == person) & np.isfinite(pred) & np.isfinite(base) & np.isfinite(y)
        if mask.sum() < 20 or min(np.std(y[mask]), np.std(base[mask]), np.std(pred[mask])) < 1e-9:
            continue
        rows.append(dict(person=person, days=int(mask.sum()),
                         baseline=float(spearmanr(y[mask], base[mask]).statistic),
                         model=float(spearmanr(y[mask], pred[mask]).statistic),
                         mae_base=float(np.abs(y[mask]-base[mask]).mean()),
                         mae_model=float(np.abs(y[mask]-pred[mask]).mean())))
    return pd.DataFrame(rows)


def summary(rows):
    gains = (rows.model - rows.baseline).to_numpy()
    rng = np.random.default_rng(0)
    boot = rng.choice(gains, (5000, len(gains)), replace=True).mean(axis=1)
    return dict(people_helped=f"{int((gains > 0).sum())}/{len(gains)}",
                mean_correlation_gain=float(gains.mean()),
                baseline_correlation=float(rows.baseline.mean()), model_correlation=float(rows.model.mean()),
                gain_ci95=np.percentile(boot, [2.5, 97.5]).tolist(),
                wilcoxon_p=float(wilcoxon(gains).pvalue),
                mae_baseline=float(rows.mae_base.mean()), mae_model=float(rows.mae_model.mean()))


def main():
    df = load_data()
    export = {"baseline_window_days": BASELINE_WINDOW, "min_history_days": MIN_HISTORY, "targets": {}}
    # This curve is an illustration derived in a separate historical experiment.
    shipped = json.loads((HERE.parent / "Shared/energy_model.json").read_text())
    for key in ("hourly_charge", "hourly_charge_source"):
        if key in shipped:
            export[key] = shipped[key]
    metrics = {}
    for target in TARGETS:
        frame = df[df[target].notna()].copy()
        frame["run_mean"] = running_mean(frame, target)
        result = summary(evaluate(frame, target))
        metrics[target] = result
        print(f"{target}: {json.dumps(result, sort_keys=True)}")
        X = frame[FEATURES].apply(pd.to_numeric, errors="coerce")
        deviation = frame[target] - frame.run_mean
        usable = deviation.notna()
        medians = X.loc[usable].median().fillna(0)
        filled = X.fillna(medians)
        model = RidgeCV(alphas=[1, 10, 100, 1000]).fit(filled.loc[usable], deviation[usable])
        predictions = model.predict(filled.loc[usable])
        export["targets"][target] = {
            "intercept": float(model.intercept_),
            "weights": dict(zip(FEATURES, map(float, model.coef_))),
            "feature_stats": {c: {"mean": float(filled.loc[usable,c].mean()),
                                   "std": float(filled.loc[usable,c].std() or 1),
                                   "median": float(medians[c])} for c in FEATURES},
            "scale": {"min": float(df[target].min()), "max": float(df[target].max())},
            "bands": {"low": float(np.percentile(predictions,33)), "high": float(np.percentile(predictions,67))},
            "people": int(frame.person.nunique()), "days": len(frame), **result}
    out = HERE / "model/energy_model.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(export, indent=2)+"\n")
    (HERE / "model/evaluation.json").write_text(json.dumps(metrics, indent=2)+"\n")
    print(f"Wrote {out}. Copy to Shared/energy_model.json after reviewing the evaluation.")


if __name__ == "__main__":
    main()
