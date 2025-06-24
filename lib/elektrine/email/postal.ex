defmodule Elektrine.Email.Postal do
  @moduledoc """
  Email sending functionality using the configured mailer.
  This module provides functions to send emails and manage messaging.
  """

  require Logger
  alias Elektrine.Email
  alias Elektrine.Mailer

  @doc """
  Sends an email through the Postal SMTP server.
  """
  def send_email(message_params) do
    # Basic validation
    if !message_params[:from] || !message_params[:to] do
      Logger.error("Missing required email fields: from or to")
      {:error, "Missing required email fields: from or to"}
    else
      # Create a Swoosh email
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.from(message_params[:from])
        |> Swoosh.Email.to(message_params[:to])
        |> Swoosh.Email.subject(message_params[:subject] || "")
        |> add_cc_recipients(message_params[:cc])
        |> add_bcc_recipients(message_params[:bcc])
        |> add_email_content(message_params[:text_body], message_params[:html_body])

      # Send the email via Swoosh
      case Mailer.deliver(email) do
        {:ok, response} ->
          Logger.info("Email sent successfully via Postal SMTP: #{inspect(response)}")

          {:ok,
           %{
             message_id:
               response.id ||
                 "postal-#{:rand.uniform(1_000_000)}-#{System.system_time(:millisecond)}",
             status: "sent"
           }}

        {:error, reason} ->
          Logger.error("Failed to send email: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Creates an incoming email message directly.

  This is used for testing and local development when there's no actual email server.
  """
  def create_test_email(params) do
    Logger.info("Creating test email: #{inspect(params)}")

    # Extract message data from parameters
    email_data = %{
      message_id:
        params[:message_id] ||
          "local-#{:rand.uniform(1_000_000)}-#{System.system_time(:millisecond)}",
      from: params[:from],
      to: params[:to],
      subject: params[:subject],
      text_body: params[:text_body],
      html_body: params[:html_body],
      status: "received"
    }

    # Extract recipient email to find the correct mailbox
    recipient = email_data.to

    # Find the mailbox for this recipient
    case find_mailbox_for_email(recipient) do
      nil ->
        Logger.warning("No mailbox found for recipient: #{recipient}")
        {:error, :no_mailbox}

      mailbox ->
        # Send notification to LiveView
        Logger.info("Broadcasting :new_email event for user:#{mailbox.user_id}")

        # Ensure read flag is explicitly set to false for new messages
        email_data = Map.put(email_data, :read, false)

        # Add mailbox_id to email data
        email_data = Map.put(email_data, :mailbox_id, mailbox.id)

        # Create the message in the database
        case Email.create_message(email_data) do
          {:ok, message} ->
            # Broadcast the message to any connected LiveViews
            Phoenix.PubSub.broadcast!(
              Elektrine.PubSub,
              "user:#{mailbox.user_id}",
              {:new_email, message}
            )

            {:ok, message}

          error ->
            error
        end
    end
  end

  # Helper functions for building Swoosh email
  defp add_cc_recipients(email, nil), do: email
  defp add_cc_recipients(email, ""), do: email

  defp add_cc_recipients(email, cc) when is_binary(cc) do
    # Parse CC addresses (comma-separated)
    cc_list = String.split(cc, ",") |> Enum.map(&String.trim/1) |> Enum.filter(&(&1 != ""))
    Swoosh.Email.cc(email, cc_list)
  end

  defp add_cc_recipients(email, cc) when is_list(cc), do: Swoosh.Email.cc(email, cc)

  defp add_bcc_recipients(email, nil), do: email
  defp add_bcc_recipients(email, ""), do: email

  defp add_bcc_recipients(email, bcc) when is_binary(bcc) do
    # Parse BCC addresses (comma-separated)
    bcc_list = String.split(bcc, ",") |> Enum.map(&String.trim/1) |> Enum.filter(&(&1 != ""))
    Swoosh.Email.bcc(email, bcc_list)
  end

  defp add_bcc_recipients(email, bcc) when is_list(bcc), do: Swoosh.Email.bcc(email, bcc)

  defp add_email_content(email, nil, nil), do: Swoosh.Email.text_body(email, "")

  defp add_email_content(email, text_body, nil),
    do: Swoosh.Email.text_body(email, text_body || "")

  defp add_email_content(email, nil, html_body),
    do: Swoosh.Email.html_body(email, html_body || "")

  defp add_email_content(email, text_body, html_body) do
    email
    |> Swoosh.Email.text_body(text_body || "")
    |> Swoosh.Email.html_body(html_body || "")
  end

  # Find a mailbox based on the recipient email address
  defp find_mailbox_for_email(email) do
    import Ecto.Query
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo

    Mailbox
    |> where(email: ^email)
    |> Repo.one()
  end
end
