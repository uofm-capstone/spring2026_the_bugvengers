# Status Page Grading Criteria

This document explains how each status metric is calculated in the app.

## Where KU appears on the page

On the status table, `KU` is the Kanban quality metric.
`GH` uses KU as one of its weighted inputs.

## Metric Definitions

- `FS&D` (Feature Selection and Decomposition): Per-student card counts by status in sprint scope (Backlog, Todo, In Progress, Done).
- `FA` (Feature Assignments): Number of sprint-scope cards assigned to the student.
- `TE` (Time Estimate): Sum of estimate values from sprint-scope cards.
- `TT` (Time Taken): Sum of time-spent/taken values from sprint-scope cards.
- `KU` (Kanban Updates): Documentation hygiene score for completed work.
- `PP` (Product Progress): Completion percentage for sprint-scope cards.
- `GH` (GitHub Composite): Weighted score of KU + CBP + PR + RVW.
- `CBP` (Coding Best Practices): Commit volume and code churn score.
- `PR` (Pull Request Workflow): PR throughput/merge behavior score.
- `RVW` (Review Activity): Review/approval behavior score.

## GH Composite Formula

`GH = KU*0.35 + CBP*0.30 + PR*0.20 + RVW*0.15`

Notes:
- GH can be non-zero even if CBP/PR/RVW are zero, because KU contributes 35%.
- KU is the same concept that was previously referred to as "KAN" in older wording.

## KU Formula (0-100)

Team and student KU both follow:

`KU = base_20 + (done_with_estimate_pct * 0.40) + (done_with_time_taken_pct * 0.40)`

- `base_20` is 20 when there is relevant work, else 0.
- Team KU done scope includes statuses: `Done`, `Archived`, `Done in Sprint X`.
- Student KU uses the student's assigned cards and same done scope rules.

KU bands:
- `Healthy` >= 85
- `Watch` >= 70 and < 85
- `At Risk` < 70

## PP Formula

`PP completion % = done_cards / total_cards * 100`

PP bands:
- `On Track` >= 80
- `Monitor` >= 60 and < 80
- `Behind` < 60

## CBP Formula (0-100)

`CBP = min(commit_count*12, 60) + min(lines_changed/40, 40)`

Then bounded to `[0, 100]`.

## PR Formula (0-100)

`PR = opened_component + merged_component + merge_velocity_bonus - open_penalty`

Where:
- `opened_component = min(opened_count*8, 35)`
- `merged_component = min(merged_count*12, 45)`
- `open_penalty = min(open_count*4, 20)`
- `merge_velocity_bonus = min((36 / avg_merge_hours)*20, 20)` when avg merge hours > 0, otherwise 0

Then bounded to `[0, 100]`.

### How lingering open PRs are penalized

The current implementation does **not** use an age timer per open PR.
It penalizes by **count** of PRs that are still open in the sprint query window:

- each qualifying open PR adds a `4` point penalty
- capped at `20` total penalty

Important nuance:
- PRs are considered in-range by `opened_at` (or `merged_at` if merged), within sprint start/end dates.
- Very old PRs opened before the sprint and still open are not currently counted by this penalty logic.

## RVW Formula (0-100)

`RVW = min(review_count*8, 55) + min(approvals*10, 35) - min(changes_requested*3, 20)`

Then bounded to `[0, 100]`.

## Banding For GH

- `Strong` >= 85
- `Solid` >= 70 and < 85
- `Watch` >= 55 and < 70
- `At Risk` < 55

## Missing-data Messages

Missing flags can appear when API data is unavailable (for example token/repo issues, query failures, or timeouts).
In the table UI, missing-flag text under KU/GH chips was intentionally removed for cleaner display.
