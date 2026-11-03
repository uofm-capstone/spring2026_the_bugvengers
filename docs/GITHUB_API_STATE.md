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

## GitHub Authentication Setup

### Token Configuration

The application authenticates GitHub API requests using a personal access token (PAT).

`GithubService.resolve_token` selects the first available credential in the following order:

1. Explicitly supplied `token`
2. `team.github_token`
3. `user.github_token`
4. `ENV["GITHUB_PAT"]`

For environments using a shared GitHub credential, configure `GITHUB_PAT` as an environment variable.

Do not commit actual GitHub tokens to source control or include them in application documentation.

### Repository Access and Permissions

The configured GitHub personal access token (PAT) must have access
to the repositories and GitHub Projects requested by the application.

For fine-grained personal access tokens, the recommended permissions are:

| Resource | Recommended Permission |
|---|---|
| Repository commits | Contents: Read-only |
| Pull requests | Pull requests: Read-only |
| Pull request reviews | Pull requests: Read-only |
| GitHub Projects v2 | Projects: Read-only |

For private repositories, the token must also be granted access to
the relevant repositories.

GitHub Projects v2 data is retrieved through the GraphQL API.

Classic personal access tokens use different scopes, such as `repo`
for private repository access and `read:project` for Projects access.

These permissions are recommended starting points. The precise
minimum permission set has not been independently verified against
all application API requests.

Use the least privileges necessary and never expose GitHub tokens
in source code, logs, screenshots, or documentation.

### Connection Configuration

The GitHub service supports two optional environment variables:

| Environment Variable | Default | Purpose |
|---|---|---|
| `GITHUB_OPEN_TIMEOUT_SECONDS` | 4 | Maximum connection establishment time |
| `GITHUB_READ_TIMEOUT_SECONDS` | 8 | Maximum API response wait time |

These values are read when the application initializes the service class.

### Authentication Verification

The service initializes an Octokit client when a nonblank token is available.

However, successful client initialization does not guarantee that the token is valid or has sufficient permissions.

Actual GitHub API requests are required to verify authentication and repository access.

## GitHub Integration Troubleshooting

### Missing GitHub Credentials

**Symptoms:** GitHub metrics are unavailable, or the service logs a warning about missing credentials.

**Possible cause:** No GitHub token was supplied through the explicit token parameter, team settings, user settings, or `GITHUB_PAT`.

**Recommended checks:**
- Confirm that a GitHub token is configured.
- Verify that the application can access the configured credential.
- Restart the application if environment variables were recently changed.

### Invalid Credentials or Insufficient Permissions

**Symptoms:** GitHub API requests fail with authentication or authorization errors.

**Possible causes:**
- The token is invalid, expired, or revoked.
- The token lacks access to the requested repository or GitHub resource.

**Recommended checks:**
- Verify that the token is still valid.
- Confirm that the token has access to the intended repository.
- Check the application logs for GitHub API errors.

### Unavailable Repositories

**Symptoms:** GitHub requests return `Octokit::NotFound`.

**Possible causes:**
- The repository owner or name is incorrect.
- The repository was deleted, renamed, or made inaccessible.
- The configured token lacks access to a private repository.

**Recommended checks:**
- Verify the repository owner and name.
- Confirm that the repository exists and is accessible to the configured GitHub account.
- Check the token's repository access permissions.

### API Rate Limits and Network Failures

**Symptoms:** GitHub metrics fail to load or display unavailable-data indicators.

**Possible causes:**
- GitHub API rate limits.
- Network connectivity problems.
- Slow API responses or request timeouts.

**Recommended checks:**
- Review application logs for the underlying API error.
- Check GitHub API rate-limit status when applicable.
- Verify network connectivity.
- Review the configured GitHub connection and read timeouts.

### Missing Student GitHub Usernames

**Symptoms:** A student's GitHub metrics display `"No Data"`.

**Possible cause:** The student has not configured a GitHub username.

**Recommended checks:**
- Confirm that the student's GitHub username is present.
- Verify that the username matches the intended GitHub account.

The application uses the `no_github_username` missing-data flag when student GitHub metrics are absent and no username is configured.

### Interpreting Missing-Data Indicators

GitHub metrics should distinguish between successful requests returning zero contributions and requests where data could not be retrieved.

Relevant indicators include:

- `no_github_username`: The student has no configured GitHub username.
- `github_query_failed`: A GitHub metrics request failed.
- `github_query_timeout`: A GitHub metrics request exceeded its timeout.
- `repo_missing`: Repository configuration is missing.
- `token_unavailable`: GitHub credentials are unavailable.

These indicators help distinguish missing information from actual contribution counts.

## GitHub Authentication and API Error Handling

### Authentication

GitHub API access is managed by `GithubService`, located in `app/services/github_service.rb`.

- The service resolves a GitHub token during initialization.
- If no token is available, the GitHub client is not initialized, and `available?` returns `false`.
- If a token is provided, the service initializes an Octokit client.
- The service does not perform an immediate authentication request during initialization to avoid unnecessary API calls and increased loading times.
- The `available?` method confirms that a client exists; it does not verify whether the token is valid.

### API Error Handling

### API Error Handling

GitHub API requests may fail because of invalid credentials, insufficient
permissions, rate limits, unavailable repositories, or network errors.

- `commits_in_range` logs and re-raises `Octokit::Unauthorized` exceptions.
- `commit_metrics_by_user` propagates API failures instead of silently
  returning empty contribution results.
- `pr_metrics_by_user` logs and re-raises API exceptions instead of
  returning empty pull request metrics.
- `review_metrics_by_user` logs and re-raises API exceptions instead of
  returning empty review metrics.
- `build_github_sprint_metrics` catches propagated exceptions and marks
  GitHub metrics as unavailable using the `github_query_failed` flag.
- Successful queries returning no contributions remain valid results
  containing zero contributions.
- `pull_requests` and `pull_request_reviews` propagate
  `Octokit::NotFound` exceptions to prevent inaccessible resources
  from being interpreted as successful empty results.

If an API request fails during pagination, the service propagates the
exception rather than returning partially retrieved contribution metrics.

This distinction prevents failed GitHub queries from being incorrectly
reported as successful queries with zero contributions.

### Known Limitations

- `pull_requests` and `pull_request_reviews` now propagate
  `Octokit::NotFound` exceptions instead of returning empty arrays.
  This prevents inaccessible GitHub resources from being silently
  interpreted as having zero contributions.
- A `404 Not Found` response may indicate either a nonexistent
  resource or insufficient repository permissions. The application
  currently treats both situations as unavailable GitHub data.
- GitHub rate-limit errors are propagated, but automatic retry and
  backoff behavior has not been verified.
- A successfully initialized Octokit client does not guarantee that
  its token is valid or has sufficient repository permissions.
- Pagination and failure handling have been verified using mocked
  GitHub API responses rather than live integration tests.

## GitHub Commit Pagination

GitHub commit history is retrieved through `GithubService#commits_in_range`, using the GitHub REST API.

### Pagination Behavior

- The service requests up to 100 commits per API page.
- Requests begin at page 1.
- When a page contains exactly 100 commits, the service requests the next page.
- Pagination stops when a page contains fewer than 100 commits.
- Results from all retrieved pages are combined into a single commit list.
- The requested sprint date range is applied to each API request.

### Regression Testing

A regression test in `test/services/github_service_test.rb` verifies pagination using a simulated repository containing 125 commits.

The test confirms that:

- Page 1 returns 100 commits.
- Page 2 returns 25 commits.
- All 125 commits are included in the final result.
- The correct pagination parameters are used for both requests.

The test uses a mocked GitHub client and does not make external API requests.

## GitHub Pull Request and Review Pagination

Pull requests and pull request reviews are retrieved through
`GithubService`, using the GitHub REST API.

### Pagination Behavior

Both `pull_requests` and `pull_request_reviews`:

- Request up to 100 results per API page.
- Begin pagination at page 1.
- Increment the page number after each nonempty response.
- Continue requesting pages until GitHub returns an empty response.
- Combine results from all retrieved pages into a single collection.

Unlike commit pagination, these methods continue until an empty
page is returned, even when the previous page contains fewer
than 100 results.

### Regression Testing

Tests in `test/services/github_service_test.rb` verify that:

- Pull requests are retrieved across multiple API pages.
- Pull request reviews are retrieved across multiple API pages.
- All 125 simulated results are included in each pagination test.
- API failures during pagination are propagated rather than
  silently returning incomplete results.
- Review metrics propagate GitHub API errors.

Controller tests additionally verify that pull request and review
API failures produce unavailable GitHub metrics with the
`github_query_failed` flag.

These tests use mocked GitHub API responses and do not make
external API requests.

## GitHub Integration Testing and Verification

### Automated Test Coverage

GitHub integration tests are located in:

- `test/services/github_service_test.rb`
- `test/controllers/semesters_controller_test.rb`

The tests cover the following functionality:

**Authentication and API Error Handling**
- Missing GitHub tokens and unavailable clients.
- Unauthorized GitHub API requests.
- Propagation of GitHub API rate-limit errors.
- Controller handling of failed API requests.
- Distinguishing unavailable GitHub data from successful queries returning zero contributions.

**Caching and Data Retrieval**
- Reusing cached commit lists.
- Bypassing cached results during forced refreshes.
- Sharing cached commit lists between contribution metrics and last-commit calculations.
- Retrieving commits across multiple API pages.

**Sprint Metrics**
- Correct sprint date boundaries.
- Separate reporting windows for different sprints.
- Aggregation of commits, pull requests, and reviews.
- Preservation of last-commit timestamps during fallback processing.

### Test Execution

Run the complete Rails test suite using:

```bash
docker compose exec \
  -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:password@db:5432/tag_app_test \
  web bin/rails test
```

### Verification Results

The full test suite was executed successfully on November 2, 2026.

| Metric | Result |
|---|---|
| Tests executed | 77 |
| Assertions | 276 |
| Failures | 0 |
| Errors | 0 |
| Skipped tests | 0 |

Additional regression tests verified:
- Unavailable GitHub repositories raise `Octokit::NotFound`.
- Students without GitHub usernames receive the `no_github_username` flag and a `"No Data"` performance band.

### Limitations

The GitHub integration tests use mocked API responses. They verify application behavior without requiring live GitHub requests.

Live API behavior, including actual rate-limit responses, repository permissions, and network failures, may require additional integration testing.


## GitHub Service Caching

GitHub API responses are cached to reduce redundant requests and improve Team Status Page loading performance.

Current caching behavior:

- `commits_in_range` caches commit lists for 10 minutes, using the repository and normalized date range as cache-key inputs.
- `commit_metrics_by_user` reuses cached commit lists when calculating commit counts and lines changed.
- `last_commit_at_by_user` can reuse the same cached commit lists when calculating last-commit timestamps.
- `commit_details` is cached for 12 hours.
- `pull_requests` is cached for 10 minutes.
- `pull_request_reviews` is cached for 10 minutes.
- `cache_fetch` uses Rails cache when available, otherwise a shared in-memory fallback.

### Forced Refresh Behavior

The `force_refresh` parameter allows the application to bypass cached results when updated GitHub data is requested.

During a forced refresh, commit metrics retrieve a fresh commit list. Subsequent last-commit calculations can reuse that refreshed list, avoiding unnecessary duplicate API requests.

### Performance Verification

After implementing commit-list caching, three consecutive Team Status Page refreshes completed in approximately 7, 7, and 6 seconds.

An earlier initial page load took approximately 60 seconds and required another refresh. Although subsequent refreshes succeeded, initial-load performance may warrant additional investigation.

## Out of Scope for GitHub-Only Metrics

These rubric items are not auto-derived from GitHub APIs and remain external/manual:

- Attendance and meeting participation
- Timesheet compliance requirements
- Client communication notes quality
- Reflection survey completion
- Cross-team feedback proof unless standardized into GitHub artifacts
