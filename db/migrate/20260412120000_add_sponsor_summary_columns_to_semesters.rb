class AddSponsorSummaryColumnsToSemesters < ActiveRecord::Migration[7.0]
  def change
    # Each sprint keeps its own persisted summary so the status page can render
    # immediately on reload without re-calling the LLM endpoint.
    add_column :semesters, :sponsor_summary_sprint_2, :text
    add_column :semesters, :sponsor_summary_sprint_3, :text
    add_column :semesters, :sponsor_summary_sprint_4, :text
  end
end
