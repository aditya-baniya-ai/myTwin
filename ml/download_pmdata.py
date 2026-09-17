"""Fetch the PMData files this project uses, from the Hugging Face mirror.

The official 1.35 GB zip is mostly food photographs and the server throttles large
transfers, so this pulls only what the model needs: the daily self-reports and the
daily Fitbit summaries, about 84 MB.

Run:  python download_pmdata.py
"""
import pathlib
import urllib.error
import urllib.request

BASE = "https://huggingface.co/datasets/aai530-group6/pmdata/resolve/main"
OUT = pathlib.Path(__file__).parent / "data" / "pmdata_hf"

WANTED = [
    "pmsys/wellness.csv",                  # the labels: fatigue, mood, readiness, stress
    "pmsys/srpe.csv",                      # training sessions, for previous-day load
    "fitbit/sleep_score.csv",
    "fitbit/sleep.json",
    "fitbit/resting_heart_rate.json",
    "fitbit/lightly_active_minutes.json",
    "fitbit/moderately_active_minutes.json",
    "fitbit/very_active_minutes.json",
    "fitbit/sedentary_minutes.json",
    "fitbit/steps.json",
]
# Skipped on purpose: food-images (hundreds of photos) and heart_rate.json
# (minute-level, ~114 MB per person, unused by the current model).

def main():
    got = missing = 0
    for number in range(1, 17):
        person = f"p{number:02d}"
        for name in WANTED:
            target = OUT / person / name
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                urllib.request.urlretrieve(f"{BASE}/{person}/{name}", target)
                got += 1
            except urllib.error.HTTPError:
                missing += 1          # a few files are absent for some participants
                target.unlink(missing_ok=True)
        print(f"{person} done")
    size = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file()) / 1e6
    print(f"\ndownloaded {got} files ({missing} not available), {size:.0f} MB in {OUT}")

if __name__ == "__main__":
    main()
