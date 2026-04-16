class CreateLoginLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :login_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :logged_in_at

      t.timestamps
    end
  end
end
