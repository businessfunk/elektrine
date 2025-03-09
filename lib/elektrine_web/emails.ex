defmodule ElektrineWeb.Emails do
  @moduledoc """
  Email templates for the application.
  """
  
  import Swoosh.Email
  alias Elektrine.Mailer

  @from_address "noreply@elektrine.com"
  @from_name "Elektrine"

  @doc """
  Delivers password reset instructions to the user's recovery email.
  """
  def deliver_reset_password_instructions(user, email, url_fun) do
    reset_url = url_fun.()

    email = 
      new()
      |> to(email)
      |> from({@from_name, @from_address})
      |> subject("Reset Your Password - Elektrine")
      |> html_body("""
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; color: #FFFFFF; background-color: #000000;">
        <div style="text-align: center; margin-bottom: 20px;">
          <h1 style="color: #F2C029;">Elektrine</h1>
        </div>
        
        <div style="background-color: #111111; padding: 20px; border-radius: 5px; margin-bottom: 20px;">
          <h2 style="color: #F2C029; margin-top: 0;">Reset Your Password</h2>
          <p>Hello #{user.username},</p>
          <p>Someone requested a password reset for your Elektrine account. If this was you, click the button below to reset your password. If you didn't request this, you can safely ignore this email.</p>
          
          <div style="text-align: center; margin: 30px 0;">
            <a href="#{reset_url}" style="background-color: #F2C029; color: #000000; padding: 12px 24px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;">Reset Password</a>
          </div>
          
          <p>Or copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #F2AC29;"><a href="#{reset_url}" style="color: #F2AC29;">#{reset_url}</a></p>
          
          <p>This link will expire in 24 hours.</p>
        </div>
        
        <div style="text-align: center; font-size: 12px; color: #999999;">
          <p>© #{DateTime.utc_now().year} Elektrine. All rights reserved.</p>
          <p>This is an automated message, please do not reply.</p>
        </div>
      </div>
      """)
      |> text_body("""
      ELEKTRINE
      =========
      
      RESET YOUR PASSWORD
      
      Hello #{user.username},
      
      Someone requested a password reset for your Elektrine account. If this was you, follow the link below to reset your password. If you didn't request this, you can safely ignore this email.
      
      #{reset_url}
      
      This link will expire in 24 hours.
      
      © #{DateTime.utc_now().year} Elektrine. All rights reserved.
      This is an automated message, please do not reply.
      """)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, %{to: email.to, body: email.html_body || email.text_body}}
    end
  end
end 