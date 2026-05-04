class AccountsController < ApplicationController
  before_action :load_user

  def show
    @codex_account = @user.codex_account
  end

  def edit
  end

  def update
    if @user.update(account_params)
      redirect_to account_path, notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def load_user
      @user = Current.session.user
    end

    def account_params
      params.require(:user).permit(:display_name, :timezone, :preferred_units)
    end
end
