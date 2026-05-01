# Status Page Grading Criteria

This document explains how each status metric is calculated in the app.

## Status Metric Direction

Kanban-derived scoring is being removed from the status experience because team Kanban formats are not standardized.
The replacement metric is Last Commit recency (GitHub activity recency per student).

## Metric Definitions

- `FS&D` (Feature Selection and Decomposition): Per-student card counts by status in sprint scope (Backlog, Todo, In Progress, Done).
- `FA` (Feature Assignments): Number of sprint-scope cards assigned to the student.
- `TE` (Time Estimate): Sum of estimate values from sprint-scope cards.
- `TT` (Time Taken): Sum of time-spent/taken values from sprint-scope cards.
- `LC` (Last Commit): Most recent commit timestamp for the student.
- `PP` (Product Progress): Completion percentage for sprint-scope cards.
- `GH` (GitHub Composite): Aggregated GitHub activity indicator.
- `CBP` (Coding Best Practices): Commit volume and code churn score.
- `PR` (Pull Request Workflow): PR throughput/merge behavior score.
- `RVW` (Review Activity): Review/approval behavior score.

## Last Commit Metric Specification

### Goal

For each student on the status table, display when they last committed to GitHub.
This metric is informational and recency-based, not Kanban-formula-based.

### Canonical Definition

Last Commit is the latest available commit timestamp for the student in the team repository.
The source is latest overall commit history, not sprint-bounded history.

### Time Source and Date Basis

- Data source: GitHub commits API results already used by the service layer.
- Per-student identity: `student.github_username`.
- Timestamp basis: commit author timestamp from GitHub payload.
- Recency scope: latest overall commit for that student in repository history.

### Timezone and Formatting

- Display timezone: `America/Chicago`.
- Display format: absolute date/time text.
- Recommended display shape: `Mon DD, YYYY h:mm AM/PM CT`.
- Example: `Apr 09, 2026 2:14 PM CT`.

### Data Contract (Target)

Student-level status payload should include a Last Commit object with explicit availability and reason signals.

Suggested shape:

```json
{
  "last_commit": {
    "timestamp_utc": "2026-04-09T19:14:00Z",
    "display_local": "Apr 09, 2026 2:14 PM CT",
    "has_sprint_commit": false,
    "data_available": true,
    "state": "ok",
    "reason": null
  }
}
```

Allowed `state` values:

- `ok`
- `no_github_username`
- `no_commits_found`
- `github_data_unavailable`

### Precedence Rules

Order of evaluation:

1. If `github_username` is blank, show `No GitHub username`.
2. Else if API/token/repo query fails, show `GitHub data unavailable`.
3. Else if at least one commit exists for the student, show the latest overall commit absolute datetime.
4. Else show `No commits in sprint`.

Conflict rule approved for this sprint:

- If there are no sprint-window commits but there is an older historical commit, show the last overall commit date only.
- Do not prepend a warning message in this case.

## UI Text Specification

Student-cell display text by state:

- `ok`: `Apr 09, 2026 2:14 PM CT`
- `no_github_username`: `No GitHub username`
- `github_data_unavailable`: `GitHub data unavailable`
- `no_commits_found`: `No commits in sprint`

Team total-row guidance:

- Show latest commit among team members when available.
- If none available, show `No commits in sprint`.

## GH Composite Note

Composite scoring documentation is intentionally separated from this metric spec.
During migration, Last Commit display behavior is authoritative for the replaced status column.

Notes:

- This document now treats Last Commit specification as source of truth for the replaced column behavior.

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
Missing-data behavior for Last Commit must follow the state mapping in UI Text Specification.

## Task 1 Acceptance Checklist

- Written Last Commit metric spec exists in this document.
- Time source, timezone, display format, and fallback behavior are explicitly documented.
- All required no-data and failure states are defined with exact UI text.
- Conflict precedence is documented for sprint-window inactivity with historical commits.
- No Kanban formula language is used as part of this metric specification.

## Task 1 Test Notes

Validate expected display text for each state:

- Student with commit history: absolute datetime in `America/Chicago`.
- Student without GitHub username: `No GitHub username`.
- Student with no commits: `No commits in sprint`.
- API/token/repo failures: `GitHub data unavailable`.
