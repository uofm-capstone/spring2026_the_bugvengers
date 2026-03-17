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
