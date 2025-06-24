defmodule Elektrine.Contact do
  @moduledoc """
  The Contact context manages contact form submissions.
  """

  alias Elektrine.Contact.Message
  alias Elektrine.Mailer
  import Swoosh.Email

  @doc """
  Sends a contact message via email.
  """
  def send_message(%{"name" => name, "email" => email, "message" => message} = attrs) do
    # Validate the message
    changeset = Message.changeset(%Message{}, attrs)

    if changeset.valid? do
      # Send the email
      new()
      |> to(Application.get_env(:elektrine, :contact_email, "admin@elektrine.com"))
      |> from({name, email})
      |> subject("Contact Form Submission from #{name}")
      |> text_body("""
      Name: #{name}
      Email: #{email}

      Message:
      #{message}
      """)
      |> Mailer.deliver()

      {:ok, %{name: name, email: email}}
    else
      {:error, changeset}
    end
  end
end
