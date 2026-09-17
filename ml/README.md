# Energy prediction

What the app predicts, how it was measured, and what it honestly cannot do.

## The short version

The model predicts **whether today is better or worse than your own normal**, not an
absolute energy score. It is your own running average plus a small ridge regression on
three sleep features. It needs about two weeks of your own data before it says anything.

Measured with leave-one-person-out evaluation on PMData (16 people, 1,747 labelled days):

| Target | Within-person correlation | People improved | Wilcoxon p |
|---|---|---|---|
| Fatigue (1–5) | −0.054 → **+0.128** | 12/16 | 0.008 |
| Readiness (0–10) | +0.051 → **+0.188** | 14/16 | 0.001 |

Mean gain +0.181 (95% CI +0.090 to +0.273) for fatigue, +0.111 (+0.057 to +0.171) for
readiness. Absolute error barely moves (readiness MAE 1.152 → 1.151), which is why the
app talks about direction, never a number out of ten.

## What did not work

- **LifeSnaps** (71 people, Fitbit Sense, HRV and SpO2 included): no usable signal. Its
  mood items are yes/no ticks rather than ratings. Daily "tired" gave per-user AUC 0.509
  (chance). Hourly, the clock alone scored 0.622 and the clock plus wearable 0.619, so the
  sensors added nothing. Within a person, tiredness tracked hour of day (+0.175) and
  nothing else (heart rate −0.013, steps −0.018, sleep duration −0.050, HRV −0.018).
- **LightGBM** on 16 or 52 features was worse than the ridge *and* worse than the baseline
  on error: 16 people cannot support that many features.
- **Cold start** (a new user, no personal history) was worse than guessing the group
  average. Hence the two-week warm-up.

## Reproducing it

```bash
python3 -m venv .venv && ./.venv/bin/pip install pandas numpy scikit-learn scipy lightgbm
./.venv/bin/python download_pmdata.py     # ~84 MB from the Hugging Face mirror
./.venv/bin/python train_final.py         # writes model/energy_model.json
```

`data/pmdata_features.csv` is the derived table (1,747 rows) the results come from, so
`train_final.py` runs without downloading anything.

| Script | What it does |
|---|---|
| `download_pmdata.py` | Fetches the PMData files used here, skipping food photos and minute-level heart rate |
| `train_pmdata.py` | Builds the feature table and compares baselines against LightGBM |
| `ridge_pmdata.py` | The ridge model that won |
| `significance.py` | Per-person paired test behind the numbers above |
| `assoc_pmdata.py` | Which signals track fatigue/readiness within a person |
| `audit_pmdata.py` | Join validation and feature coverage |
| `train_lifesnaps.py`, `train_hourly.py`, `diagnose.py`, `graded.py` | The LifeSnaps investigation |
| `train_final.py` | Fits the shipped model and exports plain coefficients |

## Method notes worth keeping

- Always compare against **each person's own running average**, not the group average.
  Published papers reporting R² ≈ 0.79 often use k-fold splits with the same people in
  train and test, which inflates results.
- Validate joins before believing a null result. Self-reported sleep hours versus Fitbit
  minutes asleep gave r = +0.678 at zero day shift, against +0.011 and +0.042 at ±1 day,
  proving nights were matched to the right morning reports.
- A silent bug to watch for: `sleep_score.csv` and `resting_heart_rate.json` both contain
  a `resting_heart_rate` column, so a naive merge collides and leaves it 1.9% populated.

## Data and licences

- **PMData** — 16 people, 5 months, Fitbit Versa 2 plus daily self-reports.
  <https://datasets.simula.no/pmdata/>. The dataset page states **CC BY-NC 4.0**
  (non-commercial); the Hugging Face mirror `aai530-group6/pmdata` states CC BY 4.0.
  Treat it as non-commercial and attribute the authors. Raw data is **not** committed here;
  `download_pmdata.py` fetches it.
- **LifeSnaps** — CC BY 4.0, <https://doi.org/10.5281/zenodo.6826682>. Tested and rejected;
  not required to reproduce the shipped model.
