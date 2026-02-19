class SessionsController < ApplicationController
  skip_before_action :require_authentication!, only: %i[new create]

  def new
    if auth_bypassed_for_localhost?
      redirect_to salary_book_path, notice: "Auth is bypassed on localhost."
      return
    end

    redirect_to salary_book_path if user_signed_in?
  end

  def create
    if auth_bypassed_for_localhost?
      redirect_to salary_book_path, notice: "Auth is bypassed on localhost."
      return
    end

    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      destination = consume_return_location || salary_book_path

      reset_session
      session[:user_id] = user.id
      user.update(last_signed_in_at: Time.current, last_signed_in_ip: request.remote_ip.to_s)

      redirect_to destination, notice: "Signed in."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
