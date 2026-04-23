class AddDateJoinedToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :date_joined, :datetime
  end
end
