class PagesController < ApplicationController
  def home
  end

  def second
  end

  def forms
  end

  def echo
  end

  def keys
  end

  def framed
  end

  def save_step
    redirect_to framed_path(step: 3)
  end

  def styled
  end

  def secret
    redirect_to login_path unless signed_in?
  end

  def broken
    raise "Broken endpoint"
  end

  def body
    render json: { body: request.raw_post, type: request.content_type }
  end

  def now
    render json: { now: Time.now.to_r.to_s }
  end

  def greeting
    if signed_in?
      render json: { greeting: "Hello, #{session[:user]}" }
    else
      redirect_to login_path
    end
  end
end
