# frozen_string_literal: true

class AddImplementationTrackingToDesignDocComments < ActiveRecord::Migration[7.0]
  def change
    add_column :ralph_design_doc_comments, :implemented, :boolean, default: false, null: false
    add_column :ralph_design_doc_comments, :implemented_at, :datetime
    add_column :ralph_design_doc_comments, :implemented_in_pr_number, :integer

    add_index :ralph_design_doc_comments, :implemented
  end
end
