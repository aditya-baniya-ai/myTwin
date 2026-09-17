"""How does energy actually fall through a day? Measured, not invented.

LifeSnaps has 4,737 check-ins where people said whether they felt tired, stamped with
the hour. That gives a real drain curve to shape the avatar with.
"""
import json, pathlib
import numpy as np, pandas as pd

SRC = "/private/tmp/claude-501/-Users-aadityabaniya-Documents-myTwin/face489d-9eff-4a04-87ec-a92333097c00/scratchpad/ml/data/lifesnaps/rais_anonymized/csv_rais_anonymized/hourly_fitbit_sema_df_unprocessed.csv"
MOOD = ['ALERT','HAPPY','NEUTRAL','RESTED/RELAXED','SAD','TENSE/ANXIOUS','TIRED']

h = pd.read_csv(SRC, low_memory=False)
lab = h[h[MOOD].notna().any(axis=1)]
by_hour = lab.groupby("hour").agg(n=("TIRED", "size"), tired=("TIRED", "mean"))
by_hour = by_hour[by_hour.n >= 30]          # ignore hours with too few check-ins
print("measured tiredness by hour (only hours with 30+ check-ins):")
print(by_hour.round(3).to_string())

# Fill the quiet night hours by interpolation, then smooth.
tired = pd.Series(index=range(24), dtype=float)
for hour, row in by_hour.iterrows():
    tired[int(hour)] = row.tired
tired = tired.interpolate(limit_direction="both")
smooth = tired.rolling(3, center=True, min_periods=1).mean()

# Charge: 1.0 at the freshest hour, falling as tiredness rises.
charge = 1 - (smooth - smooth.min()) / (smooth.max() - smooth.min())
charge = (0.35 + 0.65 * charge).round(3)     # never drains to nothing

# Nobody checks in while asleep, so the small hours interpolate to "fresh", which is
# wrong: 3am awake is drained, not rested. Carry the late-evening value through the
# night, and treat 6am as the reset after sleep.
for hour in range(0, 6):
    charge[hour] = min(charge[23], charge[hour])
for hour in range(6, 10):
    charge[hour] = 1.0
print("\nhourly charge multiplier (1.0 = freshest):")
print(" ".join(f"{hour:02d}:{value:.2f}" for hour, value in charge.items()))

path = pathlib.Path("model/energy_model.json")
model = json.loads(path.read_text())
model["hourly_charge"] = [float(charge[hour]) for hour in range(24)]
model["hourly_charge_source"] = f"LifeSnaps, {int(by_hour.n.sum())} check-ins across {len(by_hour)} hours"
path.write_text(json.dumps(model, indent=2))
print(f"\nwrote {path}")
