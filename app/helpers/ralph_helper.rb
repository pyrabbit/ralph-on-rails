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
end
