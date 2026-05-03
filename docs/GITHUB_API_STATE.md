# GitHub API Current State

## Status Page Pipeline

Primary assembly lives in `app/controllers/semesters_controller.rb`.

- `status` renders the shell and handles the "Update Cached Status Data" action.
- `status_content` builds the heavy payload and returns HTML via Turbo Frame.
- When caching is enabled (Rails cache is not `NullStore`), a manual snapshot is stored as rendered HTML in Rails cache.
- On cache miss, the UI shows a prompt to build the initial snapshot.
- On update, `status_content` rebuilds the payload, stamps `@status_snapshot_built_at`, and writes the HTML snapshot to cache.

## Data Sources

### Kanban (ProjectV2)

- Source: GitHub ProjectV2 GraphQL board items and field values.
- Service: `app/services/github_service.rb#board_health`.
- Used for FS&D, FA, TE, TT, and PP metrics.

### Commits / Pull Requests / Reviews

- Source: GitHub REST APIs.
- Services:
  - `app/services/github_service.rb#commit_metrics_by_user`
  - `app/services/github_service.rb#last_commit_at_by_user`
  - `app/services/github_service.rb#pr_metrics_by_user`
  - `app/services/github_service.rb#review_metrics_by_user`

## Sprint GitHub Aggregation

- Method: `build_github_sprint_metrics` uses `start_date..end_date` for the sprint window.
- Last commit recency also has a 180-day fallback window to avoid blanks.
- On timeout or failure, `build_last_commit_only` supplies per-student `last_commit_at` plus empty PR/Review/CBP counts.
- If repo or token is unavailable, `empty_team_github_metrics` is returned.

## Scoring (Computed, Not a Primary Table Column)

Composite score weights (from `GITHUB_SCORE_WEIGHTS`):

- `KAN` (kanban hygiene): 35%
- `CBP` (commit / churn): 30%
- `PR` (pull requests): 20%
- `RVW` (reviews): 15%

Formula:
`github_score = (kanban_score * 0.35) + (cbp_score * 0.30) + (pr_score * 0.20) + (review_score * 0.15)`

Bands:

- `Strong`: >= 85
- `Solid`: >= 70
- `Watch`: >= 55
- `At Risk`: < 55

Team and student composite scores are still computed, but the main status table uses the Last Commit column instead of a GitHub score column.

## Controller Metric Contract

### Team metrics

- Method: `build_team_sprint_metrics`
- Includes:
  - Kanban and PP values.
  - `github: { score, band, kanban_score, cbp_score, pr_score, review_score }`
  - Raw aggregates: `github[:cbp]`, `github[:pr]`, `github[:review]`
  - Availability metadata: `github[:data_available]`, `github[:missing_data_flags]`

### Student metrics

- Method: `build_live_status_metrics`
- Includes:
  - Student-specific FS&D / FA / TE / TT / PP.
  - `last_commit_at` and `last_commit` metadata for recency display.
  - `github` breakdown and score with the same structure as teams.

## UI Surfaces

### Status table

- File: `app/views/semesters/_status_metrics_table.html.erb`
- Columns per sprint: `FS&D`, `FA`, `TE`, `TT`, `Last Commit`, `PP`.
- Last Commit shows the latest available GitHub commit timestamp per student and is informational (not a formula-based score).
- PP shows completion percentage and band.

### Team overview cards

- File: `app/views/semesters/_team_overview_cards.html.erb`
- Sprint pills show the GitHub composite score and band when data is available.

### GitHub inspector (TA/Admin)

- File: `app/views/semesters/_github_data_inspector.html.erb`
- Shows per-sprint repo, score components, data availability, and missing flags.

## Availability and Missing-Data Flags

Current flags include:

- `repo_missing`
- `token_unavailable`
- `github_query_failed`
- `github_query_timeout`
- `no_github_username`
- `github_student_data_unavailable`
- `repo_or_token_missing` (student fallback)

These are surfaced in the UI to distinguish low performance from unavailable data.

## GitHub Service Caching

- `commit_details` cached for 12 hours.
- `pull_requests` cached for 10 minutes.
- `pull_request_reviews` cached for 10 minutes.
- `cache_fetch` uses Rails cache when available, otherwise a shared in-memory fallback.

## Out of Scope for GitHub-Only Metrics

These rubric items are not auto-derived from GitHub APIs and remain external/manual:

- Attendance and meeting participation
- Timesheet compliance requirements
- Client communication notes quality
- Reflection survey completion
- Cross-team feedback proof unless standardized into GitHub artifacts
