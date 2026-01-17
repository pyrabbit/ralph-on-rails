module Ralph
  class ClaudeSession < Base
    belongs_to :iteration, optional: true, class_name: "Ralph::Iteration"

    scope :by_model, ->(model) { where(model: model) }
    scope :by_context, ->(context) { where(context: context) }

    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    def success?
      exit_code&.zero?
    end

    def failure?
      !success?
    end
  end
end
