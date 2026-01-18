module RalphHelper
  # Render markdown to HTML
  def markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      filter_html: true,
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )

    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      no_intra_emphasis: true
    )

    markdown.render(text).html_safe
  end

  # Status badge for issue states
  def issue_state_badge(state)
    color_class = case state
                  when "completed", "merged"
                    "badge-state-completed"
                  when "implementing", "in_progress"
                    "badge-state-in-progress"
                  when "planning"
                    "badge-state-planning"
                  when "discovered", "not_started"
                    "badge-state-not-started"
                  when "blocked"
                    "badge-state-blocked"
                  else
                    "badge-state-default"
                  end

    content_tag(:span, state.humanize, class: "badge #{color_class}")
  end

  # Status badge for PR states
  def pr_state_badge(state)
    color_class = case state
                  when "merged"
                    "badge-pr-merged"
                  when "approved"
                    "badge-pr-approved"
                  when "open"
                    "badge-pr-open"
                  when "draft"
                    "badge-pr-draft"
                  when "changes_requested"
                    "badge-pr-changes-requested"
                  when "closed"
                    "badge-pr-closed"
                  else
                    "badge-pr-default"
                  end

    content_tag(:span, state.humanize, class: "badge #{color_class}")
  end

  # Status badge for design documents
  def doc_status_badge(status, approved)
    if approved
      content_tag(:span, "Approved", class: "badge badge-doc-approved")
    else
      color_class = case status
                    when "published"
                      "badge-doc-published"
                    when "draft"
                      "badge-doc-draft"
                    else
                      "badge-doc-default"
                    end
      content_tag(:span, status.humanize, class: "badge #{color_class}")
    end
  end

  # Recursively collect all descendants of an issue
  def collect_all_descendants(issue, descendants = [])
    issue.child_issues.each do |child|
      descendants << child
      collect_all_descendants(child, descendants)
    end
    descendants
  end

  # Calculate comprehensive metrics for a root issue
  def calculate_root_issue_metrics(root_issue)
    # Collect all descendants recursively
    all_descendants = collect_all_descendants(root_issue)

    metrics = {
      total_children: all_descendants.count,
      children_by_state: {},
      total_docs: 0,
      docs_by_status: {},
      docs_approved: 0,
      total_prs: 0,
      prs_by_state: {},
      unresolved_comments_total: 0
    }

    # Count child issue states (all descendants)
    all_descendants.group_by(&:state).each do |state, issues|
      metrics[:children_by_state][state] = issues.count
    end

    # Count design docs for root issue
    root_design_docs = root_issue.design_documents
    metrics[:total_docs] = root_design_docs.count
    root_design_docs.group(:status).count.each do |status, count|
      metrics[:docs_by_status][status] = count
    end
    metrics[:docs_approved] += root_design_docs.where.not(approved_at: nil).count

    # Count design docs for all descendants
    all_descendants.each do |descendant|
      descendant_docs = descendant.design_documents
      metrics[:total_docs] += descendant_docs.count
      descendant_docs.group(:status).count.each do |status, count|
        metrics[:docs_by_status][status] ||= 0
        metrics[:docs_by_status][status] += count
      end
      metrics[:docs_approved] += descendant_docs.where.not(approved_at: nil).count
    end

    # Count PRs for all descendants
    all_descendants.each do |descendant|
      descendant_prs = descendant.pull_requests
      metrics[:total_prs] += descendant_prs.count
      descendant_prs.group(:state).count.each do |state, count|
        metrics[:prs_by_state][state] ||= 0
        metrics[:prs_by_state][state] += count
      end
      metrics[:unresolved_comments_total] += descendant_prs.sum(:unresolved_comments_count)
    end

    metrics
  end

  # Generate GitHub issue link
  def github_issue_link(issue)
    if issue.github_issue_number && issue.repository
      url = "https://github.com/#{issue.repository}/issues/#{issue.github_issue_number}"
      link_to "##{issue.github_issue_number}", url, target: "_blank", rel: "noopener noreferrer"
    else
      content_tag(:span, "N/A", class: "text-muted")
    end
  end

  # Truncate text with tooltip
  def truncate_with_tooltip(text, length = 100)
    return "" if text.blank?

    if text.length > length
      truncated = truncate(text, length: length, omission: "...")
      content_tag(:span, truncated, title: text, class: "truncated-text")
    else
      text
    end
  end

  # Format timestamp for display
  def format_timestamp(timestamp)
    return "N/A" if timestamp.blank?

    time_ago = time_ago_in_words(timestamp)
    full_time = timestamp.strftime("%Y-%m-%d %H:%M:%S %Z")
    content_tag(:span, "#{time_ago} ago", title: full_time)
  end

  # Get metrics summary for index view
  def root_issue_summary_metrics(root_issue)
    child_count = root_issue.child_issues.count
    pr_count = root_issue.child_issues.joins(:pull_requests).count(:id)

    {
      children: child_count,
      pull_requests: pr_count
    }
  end

  # Fetch GitHub Actions status for a PR
  # Returns hash with :status (:success, :failure, :pending, :unknown), :details, :mergeable, :mergeable_state
  def fetch_pr_checks_status(repository, pr_number)
    return { status: :unknown, details: [], mergeable: nil, mergeable_state: nil } unless pr_number && repository

    begin
      client = Ralph::GitHub::Client.new

      # Fetch PR to get head SHA and merge status
      pr_result = client.fetch_pull_request(repository, pr_number)
      return { status: :unknown, details: [], mergeable: nil, mergeable_state: nil } unless pr_result[:success]

      pr_data = pr_result[:data]
      head_sha = pr_data.head.sha

      # Extract merge conflict information
      # mergeable can be: true (no conflicts), false (has conflicts), nil (being calculated)
      # mergeable_state can be: "clean", "unstable", "dirty" (conflicts), "unknown", "blocked"
      mergeable = pr_data.mergeable
      mergeable_state = pr_data.mergeable_state

      # Fetch check runs for the head SHA
      checks_result = client.fetch_check_runs(repository, head_sha)
      return { status: :unknown, details: [], mergeable: mergeable, mergeable_state: mergeable_state } unless checks_result[:success]

      check_runs = checks_result[:data].check_runs
      return { status: :pending, details: [], mergeable: mergeable, mergeable_state: mergeable_state } if check_runs.empty?

      # Determine overall status
      has_failure = check_runs.any? { |check| check.status == "completed" && check.conclusion == "failure" }
      has_pending = check_runs.any? { |check| check.status != "completed" }

      overall_status = if has_failure
        :failure
      elsif has_pending
        :pending
      else
        :success
      end

      { status: overall_status, details: check_runs, mergeable: mergeable, mergeable_state: mergeable_state }
    rescue Ralph::ConfigurationError => e
      Rails.logger.warn("GitHub token not configured for checks: #{e.message}")
      { status: :unknown, details: [], mergeable: nil, mergeable_state: nil }
    rescue => e
      Rails.logger.error("Error fetching PR checks: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      { status: :unknown, details: [], mergeable: nil, mergeable_state: nil }
    end
  end

  # Badge for CI/GitHub Actions status
  def ci_status_badge(status)
    badge_class, badge_text, badge_icon = case status
    when :success
      ["badge-ci-success", "Checks passing", "✓"]
    when :failure
      ["badge-ci-failure", "Checks failing", "✗"]
    when :pending
      ["badge-ci-pending", "Checks running", "●"]
    else
      ["badge-ci-unknown", "No checks", "?"]
    end

    content_tag(:span, "#{badge_icon} #{badge_text}", class: "badge #{badge_class}")
  end

  # Badge for merge conflict status
  # mergeable: true (no conflicts), false (has conflicts), nil (calculating/unknown)
  # mergeable_state: "clean", "unstable", "dirty", "unknown", "blocked"
  def merge_conflict_badge(mergeable, mergeable_state)
    return nil if mergeable.nil? && mergeable_state.nil?

    badge_class, badge_text, badge_icon = case mergeable_state
    when "clean"
      ["badge-merge-clean", "No conflicts", "✓"]
    when "dirty"
      ["badge-merge-conflict", "Merge conflicts", "⚠️"]
    when "unstable"
      ["badge-merge-unstable", "Unstable", "⚠️"]
    when "blocked"
      ["badge-merge-blocked", "Blocked", "🚫"]
    when "unknown"
      ["badge-merge-unknown", "Status unknown", "?"]
    else
      # Fallback to mergeable boolean if mergeable_state isn't helpful
      if mergeable == false
        ["badge-merge-conflict", "Merge conflicts", "⚠️"]
      elsif mergeable == true
        ["badge-merge-clean", "No conflicts", "✓"]
      else
        ["badge-merge-unknown", "Status unknown", "?"]
      end
    end

    content_tag(:span, "#{badge_icon} #{badge_text}", class: "badge #{badge_class}")
  end
end
