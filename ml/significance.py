"""Re-evaluate the exact five-feature pipeline exported by train_final.py."""
import json
from train_final import load_data, running_mean, evaluate, summary, TARGETS

if __name__ == "__main__":
    df = load_data()
    for target in TARGETS:
        frame = df[df[target].notna()].copy()
        frame["run_mean"] = running_mean(frame, target)
        rows = evaluate(frame, target)
        print(target)
        print(rows.round(3).to_string(index=False))
        print(json.dumps(summary(rows), indent=2))
