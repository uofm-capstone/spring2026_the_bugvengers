# app/services/kanban_monkey_commit_checker.rb
class KanbanMonkeyCommitChecker
  def self.run
    new.run
  end

  def run
    semester = Semester.current_active
    unless semester
      Rails.logger.info("[KanbanMonkey] No active semester found. Exiting.")
      return
    end

    sprint = current_sprint(semester)
    unless sprint
      Rails.logger.info("[KanbanMonkey] No active sprint for #{semester.name_for_select}. Exiting.")
      return
    end

    days_until_end = (sprint.end_date.to_date - Date.current).to_i
    unless days_until_end <= 7
      Rails.logger.info("[KanbanMonkey] Sprint ends in #{days_until_end} days — too early to remind. Exiting.")
      return
    end

    Rails.logger.info("[KanbanMonkey] Checking commits for #{semester.name_for_select} — #{sprint.name} (#{sprint.start_date.to_date} to #{sprint.end_date.to_date})")

    semester.teams.each do |team|
      check_team(team, sprint)
    end
  end

  private

  def current_sprint(semester)
    semester.sprints.find { |s| Date.current.between?(s.start_date.to_date, s.end_date.to_date) }
  end

  def check_team(team, sprint)
    github = GithubService.new(team: team)
    repo   = github.parse_repo_url(team.repo_url)

    if repo.blank?
      Rails.logger.warn("[KanbanMonkey] Team '#{team.name}' has no valid repo URL. Skipping.")
      return
    end

    unless github.available?
      Rails.logger.warn("[KanbanMonkey] Team '#{team.name}' has no GitHub token. Skipping.")
      return
    end

    commit_metrics = github.commit_metrics_by_user(repo, sprint.start_date, sprint.end_date)

    team.students.each do |student|
      check_student(student, commit_metrics, sprint, team)
    end
  end

  def check_student(student, commit_metrics, sprint, team)
    if student.github_username.blank?
      Rails.logger.warn("[KanbanMonkey] '#{student.full_name}' has no GitHub username. Skipping.")
      return
    end

    unless student.user
      Rails.logger.warn("[KanbanMonkey] '#{student.full_name}' has no linked user account. Skipping.")
      return
    end

    commit_count = commit_metrics[student.github_username]&.commit_count.to_i

    if commit_count.zero?
      Rails.logger.info("[KanbanMonkey] Zero commits — #{student.full_name} (#{student.github_username}). Sending reminder.")
      KanbanMonkeyMailer.commit_reminder(student.user, student, sprint, team).deliver_now
    else
      Rails.logger.info("[KanbanMonkey] #{student.full_name} has #{commit_count} commit(s). No action needed.")
    end
  end
end