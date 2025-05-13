defmodule Mix.Tasks.Email.TestTemporary do
  use Mix.Task
  require Logger

  @shortdoc "Test the temporary email system with adapter"

  def run(_) do
    # Start the application
    Mix.shell().info("Starting the application...")
    Mix.Task.run("app.start")

    # Create a temporary mailbox
    {:ok, temp_mailbox} = Elektrine.Email.create_temporary_mailbox()

    Mix.shell().info("Created temporary mailbox: #{temp_mailbox.email}")
    Mix.shell().info("Token: #{temp_mailbox.token}")
    Mix.shell().info("Expires at: #{temp_mailbox.expires_at}")

    # Create a test message for the temporary mailbox
    message_attrs = %{
      message_id: "temp-test-#{System.system_time(:millisecond)}",
      from: "test-sender@example.com",
      to: temp_mailbox.email,
      subject: "Test Message for Temporary Mailbox",
      text_body: "This is a test message for a temporary mailbox.",
      html_body: "<p>This is a test message for a temporary mailbox.</p>",
      mailbox_id: temp_mailbox.id,
      mailbox_type: "temporary",
      read: false,
      status: "received"
    }

    Mix.shell().info("Creating test message...")
    case Elektrine.Email.MailboxAdapter.create_message(message_attrs) do
      {:ok, message} ->
        Mix.shell().info("Message created successfully with ID: #{message.id}")
      {:error, changeset} ->
        Mix.shell().error("Failed to create message: #{inspect(changeset)}")
    end

    # List messages to verify
    messages = Elektrine.Email.MailboxAdapter.list_messages(temp_mailbox.id, :temporary)
    Mix.shell().info("Temporary mailbox has #{length(messages)} messages")
    
    # Display messages
    if messages != [] do
      Mix.shell().info("Messages:")
      Enum.each(messages, fn message ->
        Mix.shell().info("- #{message.subject} (from: #{message.from})")
      end)
    end

    Mix.shell().info("Test completed!")
  end
end