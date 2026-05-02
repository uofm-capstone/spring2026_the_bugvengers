class CreateSponsorSurveys < ActiveRecord::Migration[7.0]
  def change
    create_table :sponsor_surveys do |t|
      t.references :team, null: false, foreign_key: true
      t.integer :sprint_number, null: false
      t.text :summary_text
      t.string :sentiment
      t.string :summary_model
      t.datetime :summary_generated_at
      t.timestamps
    end

    add_index :sponsor_surveys, [:team_id, :sprint_number], unique: true
  end
end
