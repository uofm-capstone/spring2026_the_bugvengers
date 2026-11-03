require "test_helper"
require "minitest/mock"

class SemestersControllerTest < ActiveSupport::TestCase
  test "github sprint metrics include the entire final day" do
    sprint = Sprint.new(
      name: "Sprint 3",
      start_date: Time.zone.parse("2026-10-15 00:00:00"),
      end_date: Time.zone.parse("2026-11-03 00:00:00")
    )

    start_time = sprint.start_date.beginning_of_day
    end_time = sprint.end_date.end_of_day

    assert_equal Time.zone.parse("2026-10-15 00:00:00"), start_time
    assert_equal sprint.end_date.end_of_day, end_time

    assert start_time <= Time.zone.parse("2026-10-15 00:00:00")
    assert end_time >= Time.zone.parse("2026-11-03 23:59:59")
    assert end_time < Time.zone.parse("2026-11-04 00:00:00")
  end

  test "github metrics use full sprint date boundaries" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        expected_start = sprint.start_date.beginning_of_day
        expected_end = sprint.end_date.end_of_day

        service = Minitest::Mock.new

        service.expect(:available?, true)

        service.expect(
            :commit_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [
            "owner/repo",
            expected_end.to_date - 180.days,
            expected_end.to_date
            ],
            cache_version: ":fallback_last_commit",
            force_refresh: false
        )

        service.expect(
            :pr_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :review_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
        )

        controller = SemestersController.new

        result = controller.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "owner/repo",
            sprint: sprint,
            students: []
        )

        assert result[:data_available]
        service.verify
    end

    test "github metrics correctly aggregate student contributions" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        students = [students(:one), students(:two)]

        service = Minitest::Mock.new
        service.expect(:available?, true)

        service.expect(
            :commit_metrics_by_user,
            {
            "student_one" => GithubService::CBPResult.new(5, 100, 20, 120),
            "student_two" => GithubService::CBPResult.new(3, 60, 20, 80)
            },
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [String, Date, Date],
            cache_version: ":fallback_last_commit",
            force_refresh: false
        )

        service.expect(
            :pr_metrics_by_user,
            {
            "student_one" => GithubService::PRResult.new(2, 1, 1, 12.0),
            "student_two" => GithubService::PRResult.new(1, 1, 0, 8.0)
            },
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :review_metrics_by_user,
            {
            "student_one" => GithubService::ReviewResult.new(4, 3, 1),
            "student_two" => GithubService::ReviewResult.new(2, 1, 1)
            },
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "owner/repo",
            sprint: sprint,
            students: students
        )

        assert result[:data_available], "GitHub metrics should be available"

        # Commit totals
        assert_equal 8, result[:cbp][:total_commits]
        assert_equal 200, result[:cbp][:total_lines_changed]
        assert_equal 2, result[:cbp][:active_contributors]

        # Pull request totals
        assert_equal 3, result[:pr][:opened_count]
        assert_equal 2, result[:pr][:merged_count]
        assert_equal 1, result[:pr][:open_count]

        # Review totals
        assert_equal 6, result[:review][:review_count]
        assert_equal 4, result[:review][:approvals]
        assert_equal 2, result[:review][:changes_requested]

        # Individual contributions remain separate
        assert_equal 5, result[:per_student]["student_one"][:cbp][:commit_count]
        assert_equal 3, result[:per_student]["student_two"][:cbp][:commit_count]

        service.verify
    end

    test "different sprints use different reporting windows" do
        sprint_two = Sprint.new(
            start_date: Time.zone.parse("2026-09-22"),
            end_date: Time.zone.parse("2026-10-09")
        )

        sprint_three = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        [sprint_two, sprint_three].each do |sprint|
            expected_start = sprint.start_date.beginning_of_day
            expected_end = sprint.end_date.end_of_day

            service = Minitest::Mock.new
            service.expect(:available?, true)

            service.expect(
            :commit_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
            )

            service.expect(
            :last_commit_at_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
            )

            service.expect(
            :last_commit_at_by_user,
            {},
            [
                "owner/repo",
                expected_end.to_date - 180.days,
                expected_end.to_date
            ],
            cache_version: ":fallback_last_commit",
            force_refresh: false
            )

            service.expect(
            :pr_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
            )

            service.expect(
            :review_metrics_by_user,
            {},
            ["owner/repo", expected_start, expected_end],
            cache_version: nil,
            force_refresh: false
            )

            result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "owner/repo",
            sprint: sprint,
            students: []
            )

            assert result[:data_available]
            service.verify
        end

        assert_not_equal(
            sprint_two.start_date.beginning_of_day,
            sprint_three.start_date.beginning_of_day
        )

        assert_not_equal(
            sprint_two.end_date.end_of_day,
            sprint_three.end_date.end_of_day
        )
     end

     test "successful github query with zero contributions is available data" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Minitest::Mock.new
        service.expect(:available?, true)

        service.expect(
            :commit_metrics_by_user,
            {},
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [String, Date, Date],
            cache_version: ":fallback_last_commit",
            force_refresh: false
        )

        service.expect(
            :pr_metrics_by_user,
            {},
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :review_metrics_by_user,
            {},
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "owner/repo",
            sprint: sprint,
            students: [students(:one)]
        )

        assert_equal true, result[:data_available]
        assert_empty result[:missing_data_flags]
        assert_equal 0, result[:cbp][:total_commits]

        student_metrics = result[:per_student]["student_one"]

        assert_equal true, student_metrics[:data_available]
        assert_empty student_metrics[:missing_data_flags]
        assert_equal 0, student_metrics[:cbp][:commit_count]
        assert_equal 0, student_metrics[:pr][:opened_count]
        assert_equal 0, student_metrics[:review][:review_count]

        service.verify
    end

    test "github fallback preserves last commit without reporting contributions as available" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        last_commit = Time.zone.parse("2026-10-28 14:30:00")

        service = Minitest::Mock.new
        service.expect(:available?, true)

        service.expect(
            :last_commit_at_by_user,
            { "student_one" => last_commit },
            [String, Time, Time],
            cache_version: nil,
            force_refresh: false
        )

        service.expect(
            :last_commit_at_by_user,
            {},
            [String, Date, Date],
            cache_version: ":fallback_last_commit",
            force_refresh: false
        )

        result = SemestersController.new.send(
            :build_last_commit_only,
            team_service: service,
            repo: "owner/repo",
            sprint: sprint,
            students: [students(:one)],
            missing_data_flags: ["github_query_timeout"]
        )

        assert_equal false, result[:data_available]
        assert_includes result[:missing_data_flags], "github_query_timeout"

        student_metrics = result[:per_student]["student_one"]

        assert_equal false, student_metrics[:data_available]
        assert_includes student_metrics[:missing_data_flags], "github_query_timeout"
        assert_equal last_commit, student_metrics[:last_commit_at]

        assert_equal 0, student_metrics[:cbp][:commit_count]
        assert_equal 0, student_metrics[:pr][:opened_count]
        assert_equal 0, student_metrics[:review][:review_count]

        service.verify
    end

    test "github API failures are reported as unavailable data" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Object.new

        def service.available?
            true
        end

        def service.commit_metrics_by_user(*args, **kwargs)
            raise Octokit::TooManyRequests
        end

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "example/rate-limit-test",
            sprint: sprint,
            students: [students(:one)]
        )

        assert_equal false, result[:data_available]
        assert_includes result[:missing_data_flags], "github_query_failed"

    
    end

    test "pull request API failures are reported as unavailable data" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Object.new

        def service.available?
            true
        end

        def service.commit_metrics_by_user(*args, **kwargs)
            {}
        end

        def service.last_commit_at_by_user(*args, **kwargs)
            {}
        end

        def service.pr_metrics_by_user(*args, **kwargs)
            raise Octokit::TooManyRequests
        end

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "example/pr-rate-limit-test",
            sprint: sprint,
            students: [students(:one)]
        )

        assert_equal false, result[:data_available]
        assert_includes result[:missing_data_flags], "github_query_failed"
        assert_equal 0, result[:pr][:opened_count]
    end

    test "review API failures are reported as unavailable data" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Object.new

        def service.available?
            true
        end

        def service.commit_metrics_by_user(*args, **kwargs)
            {}
        end

        def service.last_commit_at_by_user(*args, **kwargs)
            {}
        end

        def service.pr_metrics_by_user(*args, **kwargs)
            {}
        end

        def service.review_metrics_by_user(*args, **kwargs)
            raise Octokit::TooManyRequests
        end

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "example/review-rate-limit-test",
            sprint: sprint,
            students: [students(:one)]
        )

        assert_equal false, result[:data_available]
        assert_includes result[:missing_data_flags], "github_query_failed"
        assert_equal 0, result[:review][:review_count]
    end


    test "invalid GitHub credentials are reported as unavailable data" do
        sprint = Sprint.new(
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Object.new

        def service.available?
            true
        end

        def service.commit_metrics_by_user(*args, **kwargs)
            raise Octokit::Unauthorized
        end

        result = SemestersController.new.send(
            :build_github_sprint_metrics,
            team_service: service,
            repo: "example/invalid-token-test",
            sprint: sprint,
            students: [students(:one)]
        )

        assert_equal false, result[:data_available]
        assert_includes result[:missing_data_flags], "github_query_failed"
        assert_equal 0, result[:cbp][:total_commits]
    end


    test "students without GitHub usernames are marked as unavailable" do
        student = students(:one)
        student.github_username = nil

        sprint = Sprint.new(
            name: "Sprint 3",
            start_date: Time.zone.parse("2026-10-15"),
            end_date: Time.zone.parse("2026-11-03")
        )

        service = Minitest::Mock.new
        service.expect(:get_card_count_per_column, {}, [[]])

        controller = SemestersController.new
        controller.instance_variable_set(:@service, service)

        result = controller.send(
            :build_live_status_metrics,
            sprint_cards: [],
            board_health: nil,
            student: student,
            sprint: sprint,
            github_student_metrics: nil,
            team_github_available: true
        )

        assert_equal false, result[:github][:data_available]
        assert_includes result[:github][:missing_data_flags], "no_github_username"
        assert_equal "No Data", result[:github][:band]

        service.verify
    end
end