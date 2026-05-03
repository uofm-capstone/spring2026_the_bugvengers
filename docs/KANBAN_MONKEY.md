# KanbanMonkey — Known Issues & Solutions

## Uninitialized Constant Error When Running the Job

**Symptom:** The Cloud Run Job fails immediately with:

```
NameError: uninitialized constant KanbanMonkeyCommitChecker
```

**Cause:** The job is pointed at a stale Docker image that was built before the `KanbanMonkeyCommitChecker` class was added.

**Fix:** Rebuild and push a new Docker image, then update the job to reference it.

In **Cloud Run → Jobs → kanban-monkey → Edit**, update the container image URL to match the latest image used by the main Cloud Run service.

Any time a new service class is added, the Docker image must be rebuilt and the job updated to reference the new image before the job will recognize the class.

---

## 7-Day Sprint Window Guard Disabled for Showcase

**Context:** The 7-day sprint window guard inside `KanbanMonkeyCommitChecker` was commented out before the final showcase so the job would run regardless of where the current date falls within the sprint. This was intentional for demo purposes.

The guard lives in the `run` method in `app/services/kanban_monkey_commit_checker.rb`:

```ruby
days_until_end = (sprint.end_date.to_date - Date.current).to_i

unless days_until_end <= 7
  Rails.logger.info("[KanbanMonkey] Sprint ends in #{days_until_end} days — too early to remind. Exiting.")
  return
end
```
