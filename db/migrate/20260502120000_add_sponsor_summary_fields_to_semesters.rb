class AddSponsorSummaryFieldsToSemesters < ActiveRecord::Migration[7.0]
  def change
    add_column :semesters, :sponsor_summary_sprint_2, :text
    add_column :semesters, :sponsor_summary_sprint_3, :text
    add_column :semesters, :sponsor_summary_sprint_4, :text
    add_column :semesters, :sponsor_sentiment_sprint_2, :string
    add_column :semesters, :sponsor_sentiment_sprint_3, :string
    add_column :semesters, :sponsor_sentiment_sprint_4, :string
    add_column :semesters, :sponsor_summary_generated_at_sprint_2, :datetime
    add_column :semesters, :sponsor_summary_generated_at_sprint_3, :datetime
    add_column :semesters, :sponsor_summary_generated_at_sprint_4, :datetime
    add_column :semesters, :sponsor_summary_model_sprint_2, :string
    add_column :semesters, :sponsor_summary_model_sprint_3, :string
    add_column :semesters, :sponsor_summary_model_sprint_4, :string
  end
end
