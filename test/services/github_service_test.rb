require "test_helper"
require "minitest/mock"

class GithubServiceTest < ActiveSupport::TestCase
    test "reuses cached commit lists for the same repository and date range" do
        service = GithubService.new(token: "test-token")

        start_date = Time.zone.parse("2026-10-01 00:00:00")
        end_date = Time.zone.parse("2026-10-14 23:59:59")

        client = Minitest::Mock.new

        client.expect(
            :commits,
            [],
            ["example/repository"],
            per_page: 100,
            page: 1,
            since: start_date,
            until: end_date
        )

        service.instance_variable_set(:@client, client)

        first_result = service.commits_in_range(
        "example/repository", start_date, end_date
        )

        second_result = service.commits_in_range(
        "example/repository", start_date, end_date
        )

        assert_equal [], first_result
        assert_equal first_result, second_result

        client.verify
    end

    test "force refresh bypasses the cached commit list" do
        service = GithubService.new(token: "test-token")

        start_date = Time.zone.parse("2026-10-01 00:00:00")
        end_date = Time.zone.parse("2026-10-14 23:59:59")

        client = Minitest::Mock.new

        2.times do
            client.expect(
            :commits,
            [],
            ["example/refresh-test-repository"],
            per_page: 100,
            page: 1,
            since: start_date,
            until: end_date
            )
        end

        service.instance_variable_set(:@client, client)

        service.commits_in_range(
            "example/refresh-test-repository",
            start_date,
            end_date
        )

        service.commits_in_range(
            "example/refresh-test-repository",
            start_date,
            end_date,
            force_refresh: true
        )

        client.verify
    end

    test "commit metrics and last commit timestamps share the cached commit list" do
        service = GithubService.new(token: "test-token")

        start_date = Time.zone.parse("2026-09-01 00:00:00")
        end_date = Time.zone.parse("2026-09-14 23:59:59")
        repo = "example/shared-cache-test"

        client = Minitest::Mock.new

        client.expect(
            :commits,
            [],
            [repo],
            per_page: 100,
            page: 1,
            since: start_date,
            until: end_date
        )

        service.instance_variable_set(:@client, client)

        service.commit_metrics_by_user(
            repo,
            start_date,
            end_date,
            force_refresh: true
        )

        service.last_commit_at_by_user(
            repo,
            start_date,
            end_date,
            force_refresh: true
        )

        client.verify
    end

    
    test "github service is unavailable without a token" do
        service = GithubService.new(token: "")

        assert_not service.available?
        assert_equal [], service.commits_in_range(
            "example/repository",
            Time.zone.parse("2026-10-01"),
            Time.zone.parse("2026-10-14")
        )
    end

    
    test "unauthorized GitHub requests raise an authentication error" do
        service = GithubService.new(token: "invalid-test-token")

        start_date = Time.zone.parse("2026-10-01")
        end_date = Time.zone.parse("2026-10-14")

        client = Object.new

        def client.commits(*)
            raise Octokit::Unauthorized
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::Unauthorized) do
            service.commits_in_range(
            "example/unauthorized-test",
            start_date,
            end_date,
            force_refresh: true
            )
        end
    end


    test "unavailable GitHub repositories raise a not found error" do
        service = GithubService.new(token: "test-token")

        start_date = Time.zone.parse("2026-10-01")
        end_date = Time.zone.parse("2026-10-14")

        client = Object.new

        def client.commits(*)
            raise Octokit::NotFound
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::NotFound) do
            service.commits_in_range(
                "example/unavailable-repository",
                start_date,
                end_date,
                force_refresh: true
            )
        end
    end


    test "commit metrics propagate GitHub API rate limit errors" do
        service = GithubService.new(token: "test-token")

        client = Object.new

        def client.commits(*)
            raise Octokit::TooManyRequests
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::TooManyRequests) do
            service.commit_metrics_by_user(
            "example/rate-limit-test",
            Time.zone.parse("2026-10-01"),
            Time.zone.parse("2026-10-14"),
            force_refresh: true
            )
        end
    end


    test "retrieves commits across multiple GitHub API pages" do
        service = GithubService.new(token: "test-token")

        start_date = Time.zone.parse("2026-10-01")
        end_date = Time.zone.parse("2026-10-14")
        repo = "example/pagination-test"

        first_page = (1..100).map { |i| "commit-#{i}" }
        second_page = (101..125).map { |i| "commit-#{i}" }

        client = Minitest::Mock.new

        client.expect(
            :commits,
            first_page,
            [repo],
            per_page: 100,
            page: 1,
            since: start_date,
            until: end_date
        )

        client.expect(
            :commits,
            second_page,
            [repo],
            per_page: 100,
            page: 2,
            since: start_date,
            until: end_date
        )

        service.instance_variable_set(:@client, client)

        result = service.commits_in_range(
            repo,
            start_date,
            end_date,
            force_refresh: true
        )

        assert_equal 125, result.length
        assert_equal first_page + second_page, result

        client.verify
    end


    test "retrieves pull requests across multiple GitHub API pages" do
        service = GithubService.new(token: "test-token")

        repo = "example/pr-pagination-test"

        first_page = (1..100).map { |i| "pr-#{i}" }
        second_page = (101..125).map { |i| "pr-#{i}" }

        client = Minitest::Mock.new

        client.expect(
            :pull_requests,
            first_page,
            [repo],
            state: "all",
            per_page: 100,
            page: 1
        )

        client.expect(
            :pull_requests,
            second_page,
            [repo],
            state: "all",
            per_page: 100,
            page: 2
        )

        client.expect(
            :pull_requests,
            [],
            [repo],
            state: "all",
            per_page: 100,
            page: 3
        )

        service.instance_variable_set(:@client, client)

        result = service.send(:pull_requests, repo)

        assert_equal 125, result.length
        assert_equal first_page + second_page, result

        client.verify
    end


    test "retrieves pull request reviews across multiple GitHub API pages" do
        service = GithubService.new(token: "test-token")

        repo = "example/review-pagination-test"
        pull_number = 42

        first_page = (1..100).map { |i| "review-#{i}" }
        second_page = (101..125).map { |i| "review-#{i}" }

        client = Minitest::Mock.new

        client.expect(
            :pull_request_reviews,
            first_page,
            [repo, pull_number],
            per_page: 100,
            page: 1
        )

        client.expect(
            :pull_request_reviews,
            second_page,
            [repo, pull_number],
            per_page: 100,
            page: 2
        )

        client.expect(
            :pull_request_reviews,
            [],
            [repo, pull_number],
            per_page: 100,
            page: 3
        )

        service.instance_variable_set(:@client, client)

        result = service.send(:pull_request_reviews, repo, pull_number)

        assert_equal 125, result.length
        assert_equal first_page + second_page, result

        client.verify
    end


    test "propagates API failures during pull request pagination" do
        service = GithubService.new(token: "test-token")
        repo = "example/pr-failure-test"

        first_page = (1..100).map { |i| "pr-#{i}" }

        client = Object.new

        client.define_singleton_method(:pull_requests) do |repository, **options|
            raise "Unexpected repository" unless repository == repo

            case options[:page]
            when 1
                first_page
            when 2
                raise Octokit::TooManyRequests
            else
                raise "Unexpected page: #{options[:page]}"
            end
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::TooManyRequests) do
            service.pr_metrics_by_user(
                repo,
                Time.zone.parse("2026-10-01"),
                Time.zone.parse("2026-10-14"),
                force_refresh: true
            )
        end
    end


    test "propagates API failures during pull request review pagination" do
        service = GithubService.new(token: "test-token")
        repo = "example/review-failure-test"
        pull_number = 42

        first_page = (1..100).map { |i| "review-#{i}" }

        client = Object.new

        client.define_singleton_method(:pull_request_reviews) do |repository, number, **options|
            raise "Unexpected repository" unless repository == repo
            raise "Unexpected pull number" unless number == pull_number

            case options[:page]
            when 1
                first_page
            when 2
                raise Octokit::TooManyRequests
            else
                raise "Unexpected page: #{options[:page]}"
            end
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::TooManyRequests) do
            service.send(:pull_request_reviews, repo, pull_number)
        end
    end

    test "review metrics propagate GitHub API failures" do
        service = GithubService.new(token: "test-token")
        repo = "example/review-metrics-failure-test"

        start_date = Time.zone.parse("2026-10-01")
        end_date = Time.zone.parse("2026-10-14")

        pull = Struct.new(:created_at, :merged_at, :number).new(
            start_date + 1.day,
            nil,
            42
        )

        client = Object.new

        client.define_singleton_method(:pull_requests) do |repository, **options|
            raise "Unexpected repository" unless repository == repo

            options[:page] == 1 ? [pull] : []
        end

        client.define_singleton_method(:pull_request_reviews) do |repository, number, **options|
            raise "Unexpected repository" unless repository == repo
            raise "Unexpected pull number" unless number == 42

            raise Octokit::TooManyRequests
        end

        service.instance_variable_set(:@client, client)
        service.instance_variable_set(:@pull_requests_cache, { repo => [pull] })

        assert_raises(Octokit::TooManyRequests) do
            service.review_metrics_by_user(
                repo,
                start_date,
                end_date,
                force_refresh: true
            )
        end
    end

    test "pull request queries propagate repository not found errors" do
        service = GithubService.new(token: "test-token")
        repo = "example/inaccessible-pr-repo"

        client = Object.new

        client.define_singleton_method(:pull_requests) do |repository, **options|
            raise "Unexpected repository" unless repository == repo
            raise Octokit::NotFound
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::NotFound) do
            service.send(:pull_requests, repo)
        end
    end

    test "pull request review queries propagate not found errors" do
        service = GithubService.new(token: "test-token")

        repo = "example/inaccessible-review-repo"
        pull_number = 42

        client = Object.new

        client.define_singleton_method(:pull_request_reviews) do |repository, number, **options|
            raise "Unexpected repository" unless repository == repo
            raise "Unexpected pull number" unless number == pull_number

            raise Octokit::NotFound
        end

        service.instance_variable_set(:@client, client)

        assert_raises(Octokit::NotFound) do
            service.send(:pull_request_reviews, repo, pull_number)
        end
    end
end