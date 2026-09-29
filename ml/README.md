# ml/

Training code for board recognition. Output: `.tflite` models copied to
`app/assets/models/`.

Planned models:
1. `board_corners` — predicts the 4 board corners from a photo.
2. `square_classifier` — 13-class classifier on warped square crops
   (good for screenshots).
3. `piece_detector` — YOLO-style detector for real 3D board photos.

Starting datasets to evaluate: public chess-piece datasets on Roboflow
Universe and Kaggle, plus synthetic renders (Blender) and our own photos.

Use a Python venv here (`python -m venv .venv`); it is git-ignored.
