module Ralph
  class Iteration < Base
    has_one :claude_session, class_name: "Ralph::ClaudeSession", foreign_key: :iteration_id

    scope :recent, -> { order(started_at: :desc).limit(100) }
    scope :failed, -> { where(status: "failure") }
    scope :successful, -> { where(status: "success") }
    scope :idle, -> { where(status: "no_work") }

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    def success?
      status == "success"
    end

    def failure?
      status == "failure"
    end

    def no_work?
      status == "no_work"
    end
  end
end
