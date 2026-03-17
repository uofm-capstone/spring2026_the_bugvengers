# GitHub API Current State

## Scope
This document captures how GitHub data is currently retrieved, processed, and surfaced in the app before implementing new status-page features.

## Current GitHub Integration Entry Points

### 1. Service Layer: `GithubService` (Octokit + GraphQL/REST)
- File: `app/services/github_service.rb`
- Auth source: `ENV["GITHUB_PAT"]` (via `GithubService.new(token: ...)`, defaulting to env var).
- API usage:
  - REST via Octokit: commit listing and commit detail stats.
  - GraphQL via Octokit `post "graphql"`: project board (ProjectV2) cards/fields.
- Exposed methods:
  - `project_cards(project_url)` for board/card metadata.
  - `get_card_count_per_column`, `get_card_count_per_assignee`, `get_total_hours_per_assignee`.
  - `get_commit_info(repo, username, start_date, end_date)` for commit totals and line churn.

### 2. Controller Layer (Legacy): `Semesters::RepositoriesController#show` (HTTParty)
- File: `app/controllers/semesters/repositories_controller.rb`
- Auth source: `current_user.github_token`.
- Builds raw GitHub REST URLs manually (`api.github.com/repos/...`).
- Pulls contributors, issues, PRs, PR reviews, and commits with `HTTParty.get`.
- Contains comments that this is versioned/legacy and that metrics moved to front-end Octokit.

### 3. Frontend Layer: browser-side Octokit module
- File: `app/javascript/octokit.js`
- Auth source: hidden HTML input (`#access-token`) rendered from `@access_tokens[@team]` sourced from uploaded `git_csv`.
- Calls `octokit.rest.repos.listCommits(...)` directly from the browser.
- Aggregates commits by author/date and renders a chart.

### 4. Token Update Endpoint
- File: `app/controllers/semesters/pages_controller.rb`
- Method: `post_github_key`
- Behavior: directly stores token plaintext into `current_user.github_token`.

## Immediate Observation
There are multiple parallel GitHub access patterns in the codebase (server-side Octokit service, server-side HTTParty legacy controller, and browser-side Octokit), each with different token sources.

## Data Flow Mapping

### A. Status Page (`GET /semesters/:id/status`) flow
1. `SemestersController#status` loads semester, teams, and sprints.
2. It instantiates `@service = GithubService.new`.
3. For each team, it calls `@service.project_cards(team.project_board_url)`.
4. `GithubService#project_cards`:
  - Parses org + project number out of `team.project_board_url`.
  - Calls GitHub GraphQL API for ProjectV2 items/fields.
  - Normalizes data into `CardInfo` structs (`title`, `status`, `assignees`, `fields`, `type`).
5. The status view (`app/views/semesters/show.html.erb`) computes display metrics directly from those cards:
  - FS&D: `get_card_count_per_column`.
  - FA: `get_card_count_per_assignee`.
  - TE: `get_total_hours_per_assignee`.

### B. Commit chart flow on semester/team pages (front-end)
1. `SemestersController#show` (and team page rendering) calls helper `get_git_info(@semester)`.
2. `ClientDisplayHelper#get_git_info` reads attached `git_csv` and returns per-team values:
  - Sprint date windows.
  - Repo owner/name.
  - GitHub access token.
3. `app/views/semesters/team.html.erb` renders hidden form inputs (`repo-owner`, `repo-name`, `access-token`, `start-date`, `end-date`).
4. A script auto-clicks hidden submit button `#gitSubmit` on page load.
5. `app/javascript/octokit.js` intercepts submit, instantiates browser Octokit with the hidden token, calls `repos.listCommits`, then groups commits by author/date for chart rendering.

### C. Legacy repository metrics flow (`GET /semesters/:semester_id/repositories/:id`)
1. `Semesters::RepositoriesController#show` reads `@repo` + `@sprint`.
2. It currently hardcodes sprint date range (`2025-01-01` to `2025-03-01`).
3. It constructs GitHub REST URLs manually.
4. It uses `current_user.github_token` and `HTTParty.get` to fetch:
  - Contributors.
  - Issues.
  - Pull requests.
  - PR reviews.
  - Commits.
5. Parsed arrays are assigned to instance variables for the view.

## Answers To Core Questions

### How is number of commits currently determined?
- In active UI charts: browser-side `octokit.rest.repos.listCommits` results are counted/grouped by author/date.
- In service code: `GithubService#get_commit_info` can count user commits and sum line additions/deletions, but this method is not currently wired into status-page cell rendering.
- In legacy controller: commits are pulled as raw JSON in `@commits_array` with hardcoded date bounds.

### How is "has user touched Kanban board" currently determined?
- No explicit "touched board" metric is implemented.
- Status-page KU metric currently renders as N/A placeholder in `app/views/semesters/show.html.erb`.
- Available board data from GraphQL cards (status transitions/history) is not currently used to infer user board activity.

## Database + Model Structure (Team/User/Sprint/GitHub-relevant)

### Tables (from `db/schema.rb`)
- `users`
  - `github_token` (string): user-level token currently used by legacy HTTParty flow.
  - `role`, `admin`, auth fields.
- `teams`
  - `semester_id` (required FK).
  - `github_token` (string): team-level token field exists.
  - `repo_url`, `project_board_url`, `timesheet_url`, `client_notes_url`.
- `students`
  - `semester_id` FK.
  - `github_username`.
  - legacy fields `team_id`, `team_name`, plus URL fields.
- `sprints`
  - `semester_id` FK.
  - `start_date`, `end_date`, plus `planning_deadline`, `progress_deadline`, `demo_deadline`.
- `repositories`
  - `owner`, `repo_name`, `team` text field.
  - `user_id` required FK.
  - `semester_id`, `team_id` optional in schema.

### Model relationships and notable constraints
- `Semester`:
  - `belongs_to :user`.
  - `has_many :sprints`, `:teams`, `:students`, `:repositories`.
  - Uses ActiveStorage attachments `student_csv`, `git_csv`, `client_csv`.
- `Team`:
  - `belongs_to :semester`.
  - `has_many :students, through: :student_teams`.
  - stores `project_board_url` that drives status-page GraphQL pull.
- `Student`:
  - `belongs_to :semester`.
  - has `github_username` used to map per-user metrics in status table.
- `Sprint`:
  - `belongs_to :semester`; validates name/start/end.
- `Repository`:
  - `belongs_to :user`.
  - `belongs_to :semester, optional: true`.
  - `belongs_to :team, optional: false` in model, but `team_id` is nullable in schema (model/schema mismatch risk).

## Hardcoded / Fragile Areas

1. Hardcoded sprint window in legacy API controller.
- `Semesters::RepositoriesController#show` sets fixed dates to Jan-Mar 2025 instead of using `Sprint` records.

2. Token source fragmentation.
- `ENV["GITHUB_PAT"]` for `GithubService`.
- `current_user.github_token` for HTTParty controller.
- CSV-provided token in hidden HTML input for browser Octokit.
- `teams.github_token` exists but is not a unified source of truth.

3. Sensitive token exposure in UI/data pipeline.
- Team token values are rendered in `app/views/teams/index.html.erb`.
- Browser flow injects token into hidden DOM fields.

4. Status-page metrics partially hardcoded placeholders.
- KU/TS/CC/SR/PF/D render fixed N/A indicators.
- PP/CBP/TSP currently render static "OK" icon, not computed metrics.

5. Incomplete status integration for commit metrics.
- `GithubService#get_commit_info` exists but status page does not call it for CBP cells.

6. Project URL parsing assumptions.
- `project_cards` assumes URL shape where org is segment 5 and project number is segment 7.

7. Potential nil-safety gaps.
- `status` loops over `team.project_board_url` without guardrails for missing/invalid URLs.

## Refactor Priorities For Status Page GitHub API Work

1. Unify token strategy server-side.
- Choose one secure credential source and remove browser-token pattern + duplicated token columns where possible.

2. Route GitHub calls through service objects only.
- Consolidate HTTParty legacy logic into `GithubService` (or dedicated GitHub clients).

3. Replace hardcoded sprint dates with DB-backed sprint windows.
- Use `Sprint.start_date/end_date` or sprint deadlines from semester context.

4. Implement real KU/CBP/TSP computations.
- KU: infer board interaction from card events/updated timestamps or timeline APIs.
- CBP: wire `get_commit_info` into status table per student/sprint.
- TSP: define and compute from commit + board/task activity since progress check date.

5. Normalize repository ownership mapping.
- Prefer `repositories.team_id` / `owner` / `repo_name` from DB over `git_csv` for runtime API calls.

6. Add robust error handling and observability.
- Replace `puts` with structured Rails logging and surfaced error states in UI.

## Summary
The status page already has a partial GitHub foundation (ProjectV2 GraphQL cards via `GithubService`) but still depends on CSV-driven/browser-side token usage and several placeholder metrics. Core next step is to consolidate token + API access server-side and wire real sprint-aware computed metrics into the status grid.
