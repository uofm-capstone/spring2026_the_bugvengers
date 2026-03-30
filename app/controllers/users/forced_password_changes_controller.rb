class Users::ForcedPasswordChangesController < ApplicationController
  def edit; end

  def update
    if params[:password].blank?
      flash.now[:alert] = "Password can't be blank."
      return render :edit
    end

    if params[:password] != params[:password_confirmation]
      flash.now[:alert] = "Password confirmation doesn't match."
      return render :edit
    end

    if current_user.update(
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )
      current_user.update!(temp_password_changed: true, is_active: true)
      redirect_to root_path, notice: "Password updated. Welcome to TAG!"
    else
      flash.now[:alert] = current_user.errors.full_messages.join(", ")
      render :edit
    end
  end
end