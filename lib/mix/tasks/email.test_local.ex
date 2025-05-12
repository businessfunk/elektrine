defmodule Mix.Tasks.Email.TestLocal do
  @moduledoc """
  Mix task for sending test emails to users in the system.
  This helper is designed for development and testing.
  
  ## Usage
  
      mix email.test_local recipient@domain.com --from sender@domain.com --subject "Test Subject"

  """
  use Mix.Task
  require Logger
  alias Elektrine.Email
  alias Elektrine.Email.Mailbox
  alias Elektrine.Repo
  import Ecto.Query

  @shortdoc "Sends a test email to a user in the system"
  def run(args) do
    # Parse options
    {opts, args, _} = OptionParser.parse(args, 
      strict: [
        from: :string,
        subject: :string,
        body: :string
      ]
    )

    # Ensure we have a recipient
    case args do
      [recipient | _] ->
        # Start application
        {:ok, _} = Application.ensure_all_started(:elektrine)
        
        # Find or create recipient mailbox
        recipient = recipient |> String.trim()
        from = opts[:from] || "test@elektrine.com"
        subject = opts[:subject] || "Test Email at #{DateTime.utc_now()}"
        body = opts[:body] || "This is a test email sent at #{DateTime.utc_now()}."
        
        # Find the mailbox
        mailbox = get_mailbox_by_email(recipient)
        
        if mailbox do
          Logger.info("Found mailbox for #{recipient}")
          
          # Create a message directly
          message_data = %{
            message_id: "local-test-#{:rand.uniform(1000000)}-#{System.system_time(:millisecond)}",
            from: from,
            to: recipient,
            subject: subject,
            text_body: body,
            html_body: "<p>#{body}</p>",
            status: "received",
            read: false,
            mailbox_id: mailbox.id
          }
          
          case Email.create_message(message_data) do
            {:ok, message} ->
              Logger.info("Created message successfully with ID: #{message.id}")
              
              # Send PubSub notification to update inbox
              Phoenix.PubSub.broadcast!(
                Elektrine.PubSub,
                "user:#{mailbox.user_id}",
                {:new_email, message}
              )
              
              Logger.info("Sent PubSub notification for user:#{mailbox.user_id}")
              
              # Success message
              IO.puts("\nTest email created successfully:")
              IO.puts("  From: #{from}")
              IO.puts("  To: #{recipient}")
              IO.puts("  Subject: #{subject}")
              IO.puts("  Message ID: #{message.id}")
              IO.puts("  PubSub notification sent: user:#{mailbox.user_id}")
              
            {:error, changeset} ->
              Logger.error("Failed to create message: #{inspect(changeset.errors)}")
              Mix.raise("Failed to create test email. See log for details.")
          end
        else
          Mix.raise("Could not find a mailbox for #{recipient}")
        end
        
      [] ->
        Mix.raise("Please provide a recipient email address")
    end
  end
  
  defp get_mailbox_by_email(email) do
    Mailbox
    |> where([m], m.email == ^email)
    |> Repo.one()
  end
end