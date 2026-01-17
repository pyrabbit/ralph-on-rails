class GithubLabelService
  DESIGN_APPROVED_LABEL = "design approved"

  def initialize(github_client = nil)
    @client = github_client || Ralph::GitHub::Client.new
  end

  # Check if issue has the design approved label
  def has_label?(repository, issue_number, label_name = DESIGN_APPROVED_LABEL)
    result = @client.fetch_issue(repository, issue_number)
    return false unless result[:success]

    issue = result[:data]
    issue.labels.any? { |label| label.name == label_name }
  end

  # Add design approved label to issue
  def add_label(repository, issue_number, label_name = DESIGN_APPROVED_LABEL)
    @client.add_labels_to_issue(repository, issue_number, [label_name])
  end

  # Remove design approved label from issue
  def remove_label(repository, issue_number, label_name = DESIGN_APPROVED_LABEL)
    @client.octokit.remove_label(repository, issue_number, label_name)
    { success: true }
  rescue Octokit::NotFound
    # Label already doesn't exist - treat as success
    { success: true }
  rescue Octokit::Error => e
    { success: false, error: e.message }
  end

  # Toggle label (add if missing, remove if present)
  def toggle_label(repository, issue_number, label_name = DESIGN_APPROVED_LABEL)
    has_label = has_label?(repository, issue_number, label_name)

    if has_label
      result = remove_label(repository, issue_number, label_name)
      result.merge(action: :removed) if result[:success]
    else
      result = add_label(repository, issue_number, label_name)
      result.merge(action: :added) if result[:success]
    end

    result
  end
end
