# Energy-model research

The shipped app uses five inputs: relative sleep duration, sleep efficiency, relative
deep sleep, relative REM sleep, and relative resting heart rate. It predicts deviation
from usual readiness. It requires today's sleep and seven usable prior nights within
14 calendar days. Missing features use exported training medians. Ten daily ratings
allow a separate personal fit to start blending in.

## Current reproducible evaluation

Leave-one-person-out evaluation on the locally available PMData derived table (16
people, 1,747 labelled days). Imputation is fitted on training people only. Coefficients
are fitted on all eligible rows after evaluation. Exact outputs are in
`model/evaluation.json`; these replace the earlier three-feature Fitbit-score results.

| Target | Mean within-person correlation | People improved | Wilcoxon p |
|---|---|---|---|
| Fatigue | -0.054 → +0.103 | 12/16 | 0.0034 |
| Readiness | +0.051 → +0.124 | 14/16 | 0.0021 |

Readiness MAE: **1.152 baseline, 1.155 model**. Fatigue MAE: **0.502 baseline,
0.497 model**. Mean correlation gains are +0.157 (bootstrap 95% CI +0.081 to +0.236)
for fatigue and +0.073 (+0.031 to +0.122) for readiness. These small exploratory
results do not establish individual accuracy, clinical validity, or causal benefits
from suggested activities. Confidence intervals resample participants, not days.

The evaluation adds predicted deviations to each participant's expanding prior
self-report mean. The app shows a direction band rather than that absolute score.
The historical feature table uses 14 prior report rows for normalization; the app
uses 14 calendar days. Missing-report and cross-device effects remain unvalidated.
The same held-out folds informed model selection, so this is exploratory evaluation,
not an untouched external test set.

## Reproduce

From the repository root:

```sh
python3 -m venv .venv
.venv/bin/pip install numpy pandas scipy scikit-learn lightgbm requests
# If you do not already have the derived table:
cd ml
../.venv/bin/python download_pmdata.py
../.venv/bin/python train_pmdata.py  # exports data/pmdata_features.csv, then runs legacy comparisons
cd ..
.venv/bin/python ml/train_final.py
.venv/bin/python ml/significance.py
# After reviewing the evaluation:
cp ml/model/energy_model.json Shared/energy_model.json
```

Raw data and the derived CSV are **not committed**. `train_final.py` and
`significance.py` use the local derived table and do not download data. The raw-data
rebuild was not repeated in this verification because those files are absent.

The exporter preserves the checked-in `hourly_charge` illustration from Shared.
That curve is separate from the sleep regression: historical LifeSnaps tiredness
reports were smoothed and rescaled, with hand-set overnight/morning behavior. The
percentages are not validated battery measurements. To rebuild that curve with your
own local LifeSnaps file:

```sh
python3 ml/drain_curve.py /path/to/hourly_fitbit_sema_df_unprocessed.csv
```

`healthkit_only.py`, `window_test.py`, and other scripts are historical exploratory
experiments and may require running from `ml/` or access to the original datasets.
Their numbers must not be substituted for the current exporter evaluation.

## Data provenance

PMData: https://datasets.simula.no/pmdata/ — 16 participants, Fitbit and self-reports.
The source page identifies a non-commercial licence; resolve usage rights before
commercial model distribution. Raw participant records are not included here.
LifeSnaps: https://doi.org/10.5281/zenodo.6826682 — the source of the historical
illustrative hourly pattern, not a validated personal energy predictor.
