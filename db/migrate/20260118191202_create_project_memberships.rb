class CreateProjectMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :project_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :role, null: false, default: 'viewer'

      t.timestamps

      t.index [:user_id, :project_id], unique: true
      t.index :role
    end
  end
end
