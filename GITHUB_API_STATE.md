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
