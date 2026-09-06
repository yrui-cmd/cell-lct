# Optional no-ai treatment before recognition

Apply this branch only to a new raster reconstruction, after text-only cleanup and before submitting image bytes for path recognition. Preserve the original and its text manifest. For text-free inputs, use the original as the prepared image. Existing vector/PPT edits, recoloring and resume operations do not need a new treatment.

## Dependency and current workflow

Run the bundled `scripts/sync_cell_no_ai.py` once per new raster job to install/update the sibling skill from the official `yrui-cmd/cell_no_ai` main branch. The synchronizer preserves credentials and backs up changed files. Read that sibling's current `SKILL.md` and, when the user selects treatment, its API/workflow references. Do not duplicate endpoints or outdated service claims here. If synchronization fails, say so; drawing with a declined treatment can continue, but resolve the dependency before a new watermark submission. Installing or updating a dependency does not authorize a charge.

## Decision and submission

1. Briefly explain that `cell_no_ai` opens the official verification page for manual detection, or submits PNG/JPG through its removal API and downloads the result. Follow its current opening notice about treatment scope without claiming verified removal. Do not open a browser for the removal branch.
2. Ask once whether the user wants the optional treatment for this image, with an additional cost of 1 credit, separate from recognition. A previous explicit yes/no for the same image remains valid; no answer remains pending. If the user is undecided, ask before querying an account unnecessarily.
3. If no, submit the prepared image to the existing recognition entrypoint with the original text manifest. No removal API call or extra charge occurs.
4. If yes, follow `cell_no_ai` to query and display the current available balance with the same key before any removal upload. Display `当前可用余额：N；本次去 AI 水印消耗 1 个额度。` Zero, less than 1, unknown or failed balance means stop the removal branch without uploading. Do not use recognition authorization, an old balance or an attempted paid submission as a substitute. If authorization has not yet been given, obtain it after showing the balance and cost; do not ask again when it is already explicit.
5. Submit the prepared PNG/JPG once through the documented removal API. For WebP, prepare a lossless PNG copy. Save the input identity, decision and returned job ID without credentials. Continue polling and downloading that same job; an uncertain submit or transient error must not trigger another paid submission.

## Receive and continue

Receive the processed image, verify that it is a readable image, and save a new file. Do not finish at a job ID, send the original to recognition while the chosen treatment is pending, or silently switch to the no branch on failure. Follow the dependency's expiry and failure rules. Return the received image/link briefly, then continue recognition with that returned file and restore the recorded live text in the normal drawing workflow.

Use normalized text coordinates (x/source-width, y/source-height and corresponding size ratios) to map the manifest to the actual recognition canvas. Keep the original manifest and write a derived copy if dimensions differ. Do not add unsolicited quality, resolution or watermark-verification commentary; layout/text restoration remains part of normal drawing validation. A treatment charge and a recognition charge are separate; never infer balances or guarantee all provenance signals are removed.
