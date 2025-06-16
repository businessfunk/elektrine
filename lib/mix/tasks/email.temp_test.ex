defmodule Mix.Tasks.Email.TempTest do
  use Mix.Task
  require Logger

  @shortdoc "Test the temporary email system by receiving test emails"

  def run(_) do
    # Start the application
    Mix.shell().info("Starting the application...")
    Mix.Task.run("app.start")

    # Create a temporary mailbox
    {:ok, temp_mailbox} = Elektrine.Email.create_temporary_mailbox()

    Mix.shell().info("Created temporary mailbox: #{temp_mailbox.email}")
    Mix.shell().info("Token: #{temp_mailbox.token}")
    Mix.shell().info("Expires at: #{temp_mailbox.expires_at}")

    # Test receiving an email to the temporary mailbox
    test_receive_email(temp_mailbox)

    # List messages to verify
    messages = Elektrine.Email.list_messages(temp_mailbox.id)
    Mix.shell().info("Temporary mailbox has #{length(messages)} messages")
    
    # Display messages
    if messages != [] do
      Mix.shell().info("Messages:")
      Enum.each(messages, fn message ->
        Mix.shell().info("- #{message.subject} (from: #{message.from})")
      end)
    end

    Mix.shell().info("Temporary email test completed!")
  end

  defp test_receive_email(temp_mailbox) do
    Mix.shell().info("Testing email receiving for temporary mailbox...")

    # Check if webhook handling is working
    # First, test with the postal controller directly
    Mix.shell().info("Testing webhook processing via controller...")
    
    # Create raw mock email data (simple text email)
    from = "test-sender@example.com"
    to = temp_mailbox.email
    subject = "Test Email to Temporary Mailbox #{DateTime.utc_now()}"
    message_id = "temp-test-#{:rand.uniform(1000000)}-#{System.system_time(:millisecond)}"
    
    raw_email = """
    From: #{from}
    To: #{to}
    Subject: #{subject}
    Message-ID: <#{message_id}>
    Date: #{DateTime.utc_now() |> Calendar.strftime("%a, %d %b %Y %H:%M:%S %z")}
    Content-Type: text/plain; charset=UTF-8

    This is a test email sent to a temporary mailbox.
    Sent at: #{DateTime.utc_now()}
    """
    
    # Base64 encode the raw email for the postal webhook
    base64_email = Base.encode64(raw_email)
    
    # Create a mock webhook payload
    _webhook_payload = %{
      "message" => base64_email,
      "rcpt_to" => temp_mailbox.email,
      "mail_from" => from
    }
    
    # Simulate processing of the webhook
    _conn = %Plug.Conn{
      remote_ip: {127, 0, 0, 1},
      req_headers: []
    }

    case ElektrineWeb.PostalInboundController.process_email(raw_email, temp_mailbox.email) do
      {:ok, message} ->
        Mix.shell().info("Test email processed successfully! Message ID: #{message.id}")
        {:ok, message}
        
      {:error, reason} ->
        Mix.shell().error("Failed to process test email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end