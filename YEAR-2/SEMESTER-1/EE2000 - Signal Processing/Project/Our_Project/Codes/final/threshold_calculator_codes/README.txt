# Three-channel vibration fault classification pipeline

## Files
- `main.py`: creates or reuses the random dataset split and runs all three stages.
- `all_classes_three_channels_calibration.py`: extracts FFT features and creates per-class/per-channel calibration CSVs.
- `three_channel_majority_vote_threshold_calibration.py`: calibrates per-channel MIN_SCORE and MIN_MARGIN thresholds.
- `final_accuracy_three_channel_majority_vote.py`: evaluates the frozen classifier on the test recordings.

## Dataset path
The scripts currently use:
`C:\Users\vishw\Documents\Vibration Dataset\50`

If your dataset is elsewhere, change `BASE_DIR` in all four Python files to the same directory.

## Run
Open PowerShell in this folder and run:
```powershell
python main.py
```

The program generates `dataset_split.json` in the dataset directory. It randomly partitions CSV columns 2–16 into:
- 8 training recordings
- 3 threshold-calibration recordings
- 4 final-test recordings

It then runs the three stages in order. All scripts read the same JSON file, so the column selections stay consistent across all five classes and all three channels.

## Reuse the exact same partition
To rerun the pipeline without changing the split:
```powershell
python main.py --reuse-split
```

To create a reproducible new split:
```powershell
python main.py --seed 42
```

To skip the confirmation prompt:
```powershell
python main.py --yes
```

## Important
- Do not run the final-test script before feature and threshold calibration have completed.
- A normal `python main.py` run creates a new random split and overwrites `dataset_split.json`. Use `--reuse-split` to preserve the previous partition.
- The final-test script uses the thresholds produced by the threshold-calibration stage.
- Install dependencies in the Python environment used to run the scripts: `numpy`, `pandas`, `scipy`, and `scikit-learn`.
