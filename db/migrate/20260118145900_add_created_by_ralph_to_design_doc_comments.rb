# frozen_string_literal: true

class AddCreatedByRalphToDesignDocComments < ActiveRecord::Migration[7.0]
  def change
    add_column :ralph_design_doc_comments, :created_by_ralph, :boolean, default: false, null: false
    add_index :ralph_design_doc_comments, :created_by_ralph
  end
end
