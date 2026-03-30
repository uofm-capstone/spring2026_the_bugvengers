class Users::PasswordsController < Devise::PasswordsController
  def update
    super do |resource|
      if resource.errors.empty?
        resource.update!(
          temp_password_changed: true,
          is_active: true
        )
      end
    end
  end
end