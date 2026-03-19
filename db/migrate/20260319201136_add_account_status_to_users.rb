class AddAccountStatusToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :is_active, :boolean, default: false, null: false
    add_column :users, :temp_password_changed, :boolean, default: false, null: false
  end
end
