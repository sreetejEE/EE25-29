#************Written by Venkata Sai*************

from pathlib import Path
import argparse
import json
import random
import subprocess
import sys
speed = 100
BASE_DIR = Path(
    fr"C:\Users\vishw\Documents\Vibration Dataset\{speed}"
)
PROJECT_DIR = Path(__file__).resolve().parent
SPLIT_FILE = BASE_DIR / "dataset_split.json"

TRAIN_COUNT = 8
CALIBRATION_COUNT = 3
TEST_COUNT = 4
ALL_COLUMNS = list(range(2, 17))

STAGES = [
    ("1/3 Feature calibration", "all_classes_three_channels_calibration.py"),
    ("2/3 Decision-threshold calibration",
     "three_channel_majority_vote_threshold_calibration.py"),
    ("3/3 Final accuracy testing",
     "final_accuracy_three_channel_majority_vote.py"),
]


def validate_split(split):
    required = {"TRAIN_COLUMNS", "CALIBRATION_COLUMNS", "TEST_COLUMNS"}
    if set(split) < required:
        raise ValueError(f"Split JSON must contain {sorted(required)}.")

    train = split["TRAIN_COLUMNS"]
    calibration = split["CALIBRATION_COLUMNS"]
    test = split["TEST_COLUMNS"]

    if (len(train), len(calibration), len(test)) != (
        TRAIN_COUNT, CALIBRATION_COUNT, TEST_COUNT
    ):
        raise ValueError("Split sizes must be 8 training, 3 calibration, 4 test.")

    combined = train + calibration + test
    if len(combined) != len(set(combined)):
        raise ValueError("Column overlap or duplicate found in dataset split.")
    if sorted(combined) != ALL_COLUMNS:
        raise ValueError("Split must use every column from 2 through 16 exactly once.")


def create_split(seed=None):
    columns = ALL_COLUMNS.copy()
    rng = random.Random(seed)
    rng.shuffle(columns)

    split = {
        "TRAIN_COLUMNS": sorted(columns[:TRAIN_COUNT]),
        "CALIBRATION_COLUMNS": sorted(
            columns[TRAIN_COUNT:TRAIN_COUNT + CALIBRATION_COUNT]
        ),
        "TEST_COLUMNS": sorted(columns[TRAIN_COUNT + CALIBRATION_COUNT:]),
        "seed": seed,
    }
    validate_split(split)
    return split


def save_split(split):
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    with SPLIT_FILE.open("w", encoding="utf-8") as f:
        json.dump(split, f, indent=4)


def load_split():
    if not SPLIT_FILE.exists():
        raise FileNotFoundError(
            f"No existing split found at:\n{SPLIT_FILE}\n"
            "Run without --reuse-split to generate one."
        )
    with SPLIT_FILE.open("r", encoding="utf-8") as f:
        split = json.load(f)
    validate_split(split)
    return split


def print_split(split):
    print("\nDATASET PARTITION (CSV columns are 1-based)")
    print("-" * 55)
    print("Training columns    :", split["TRAIN_COLUMNS"])
    print("Calibration columns :", split["CALIBRATION_COLUMNS"])
    print("Testing columns     :", split["TEST_COLUMNS"])
    print("Saved split file    :", SPLIT_FILE)
    print("-" * 55)


def run_stage(label, script_name):
    script_path = PROJECT_DIR / script_name
    if not script_path.exists():
        raise FileNotFoundError(f"Pipeline script not found: {script_path}")

    print(f"\n\n{'=' * 76}")
    print(label)
    print(f"Running: {script_name}")
    print("=" * 76, flush=True)

    # Run with the same Python interpreter/environment as main.py.
    subprocess.run(
        [sys.executable, str(script_path)],
        cwd=str(PROJECT_DIR),
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Run the complete three-channel vibration fault pipeline."
    )
    parser.add_argument(
        "--seed", type=int, default=None,
        help="Optional random seed. Same seed produces the same partition."
    )
    parser.add_argument(
        "--new-split", action="store_true",
        help="Reuse the existing dataset_split.json instead of generating a new split."
    )
    parser.add_argument(
        "--yes", action="store_true",
        help="Run without interactive confirmation."
    )
    args = parser.parse_args()

    if not BASE_DIR.exists():
        raise FileNotFoundError(
            f"Dataset directory does not exist:\n{BASE_DIR}\n"
            "Edit BASE_DIR in main.py if your dataset is stored elsewhere."
        )

    if SPLIT_FILE.exists() and not args.new_split:
        split = load_split()
        print("\nReusing the existing dataset split.")
    else:
        split = create_split(args.seed)
        save_split(split)
        print("\nA new random dataset split has been generated and saved.")

    print_split(split)

    if not args.yes:
        print(
            "\nThis will run feature calibration, threshold calibration, "
            "and final testing in that order."
        )
        answer = input("Continue? [y/N]: ").strip().lower()
        if answer not in ("y", "yes"):
            print("Cancelled. The generated split remains saved.")
            return

    for label, script_name in STAGES:
        run_stage(label, script_name)

    print("\n" + "=" * 76)
    print("COMPLETE PIPELINE FINISHED SUCCESSFULLY")
    print("Dataset split:", SPLIT_FILE)
    print("Results folder:", BASE_DIR / "classification_test_results")
    print("=" * 76)


if __name__ == "__main__":
    main()
