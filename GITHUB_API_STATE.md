# GitHub API Current State

## Implemented GitHub-Only Grading Signals

The status page now computes a per-sprint GitHub composite score for each student and team.

### Composite score weights

- `KAN` (Kanban quality): `35%`
- `CBP` (commit/code churn): `30%`
- `PR` (pull request workflow): `20%`
- `RVW` (review participation/quality): `15%`

Formula:
`github_score = (kanban_score * 0.35) + (cbp_score * 0.30) + (pr_score * 0.20) + (review_score * 0.15)`

Band thresholds:

- `Strong`: `>= 85`
- `Solid`: `>= 70`
- `Watch`: `>= 55`
- `At Risk`: `< 55`

## Data Sources

### Kanban (`KAN`)

- Source: GitHub ProjectV2 GraphQL board items and field values.
- Service: `app/services/github_service.rb#board_health`.
- Includes assignee coverage and TE/TT completeness for done cards.

### CBP (`CBP`)

- Source: GitHub commits API + commit details.
- Services:
  - `app/services/github_service.rb#commits_in_range`
  - `app/services/github_service.rb#commit_metrics_by_user`
- Inputs:
  - `commit_count`
  - `lines_changed`

### PR (`PR`)

- Source: Pull request list scoped to sprint window.
- Service: `app/services/github_service.rb#pr_metrics_by_user`
- Inputs:
  - `opened_count`
  - `merged_count`
  - `open_count`
  - `avg_merge_hours`

### Review (`RVW`)

- Source: Pull request reviews scoped to sprint window.
- Service: `app/services/github_service.rb#review_metrics_by_user`
- Inputs:
  - `review_count`
  - `approvals`
  - `changes_requested`

## Controller Metric Contract

Primary assembly lives in `app/controllers/semesters_controller.rb`.

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
  - Student-specific FS&D/FA/TE/TT/PP.
  - `github` breakdown and score with same structure.
  - Availability metadata and fallback flags.

### Sprint GitHub aggregation

- Method: `build_github_sprint_metrics`
- Uses sprint `start_date..end_date` window.
- Returns `empty_team_github_metrics` when repo or token is unavailable.

## UI Surfaces

### Status table

- File: `app/views/semesters/_status_metrics_table.html.erb`
- `KU` column now shows GitHub composite score and chips: `KAN`, `CBP`, `PR`, `RVW`.
- `PP` column shows product-progress completion percentage and band.
- No-data state displays `N/A` plus missing-data hints.

### Team overview cards

- File: `app/views/semesters/_team_overview_cards.html.erb`
- Sprint pill shows GitHub score/band, or explicit no-data reason.

### GitHub inspector

- File: `app/views/semesters/_github_data_inspector.html.erb`
- Shows sprint-level repo, score components, availability, and missing flags.

## Availability and Missing-Data Flags

Current flags include:

- `repo_missing`
- `token_unavailable`
- `github_query_failed`
- `repo_or_token_missing` (student fallback)

These are surfaced in table/overview/inspector to distinguish low performance from unavailable data.

## Out of Scope for GitHub-Only Metrics

These rubric items are not auto-derived from GitHub APIs and remain external/manual:

- Attendance and meeting participation
- Timesheet compliance requirements
- Client communication notes quality
- Reflection survey completion
- Cross-team feedback proof unless standardized into GitHub artifacts
