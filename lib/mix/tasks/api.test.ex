defmodule Mix.Tasks.Api.Test do
  use Mix.Task
  require Logger

  @shortdoc "Test the temporary mailbox API endpoints"

  def run(_) do
    # Start the application
    Mix.shell().info("Starting the application...")
    Mix.Task.run("app.start")

    # Test creating a temporary mailbox
    Mix.shell().info("\n=== Testing Temporary Mailbox API ===\n")
    
    {:ok, mailbox} = create_temporary_mailbox()
    Mix.shell().info("Created temporary mailbox: #{mailbox.email}")
    Mix.shell().info("Token: #{mailbox.token}")
    Mix.shell().info("Expires at: #{mailbox.expires_at}")
    
    # Create a test message for the temporary mailbox
    create_test_message(mailbox)
    
    # Get mailbox details including messages
    {:ok, mailbox_with_messages} = get_mailbox(mailbox.token)
    
    Mix.shell().info("\nMailbox has #{length(mailbox_with_messages.messages)} messages")
    
    if mailbox_with_messages.messages != [] do
      message = hd(mailbox_with_messages.messages)
      Mix.shell().info("First message: #{message.subject} (from: #{message.from})")
      
      # Get message details
      {:ok, full_message} = get_message(mailbox.token, message.id)
      Mix.shell().info("\nMessage details:")
      Mix.shell().info("Subject: #{full_message.subject}")
      Mix.shell().info("From: #{full_message.from}")
      Mix.shell().info("To: #{full_message.to}")
      Mix.shell().info("Body: #{String.slice(full_message.text_body || "", 0, 50)}...")
      
      # Test deleting the message
      {:ok, _} = delete_message(mailbox.token, message.id)
      Mix.shell().info("\nMessage deleted successfully")
    end
    
    # Test extending the mailbox
    {:ok, extended_mailbox} = extend_mailbox(mailbox.token)
    Mix.shell().info("\nMailbox extended:")
    Mix.shell().info("New expiration: #{extended_mailbox.expires_at}")
    
    Mix.shell().info("\nAPI Tests completed successfully!")
  end
  
  # API client functions
  
  defp create_temporary_mailbox do
    # Simulate API request
    case Elektrine.Email.create_temporary_mailbox() do
      {:ok, mailbox} ->
        {:ok, %{
          id: mailbox.id,
          email: mailbox.email,
          token: mailbox.token,
          expires_at: mailbox.expires_at
        }}
      
      error -> error
    end
  end
  
  defp get_mailbox(token) do
    # Simulate API request
    case Elektrine.Email.get_temporary_mailbox_by_token(token) do
      nil -> {:error, :not_found}
      
      mailbox ->
        messages = Elektrine.Email.MailboxAdapter.list_messages(mailbox.id, :temporary, 50)
        
        {:ok, %{
          id: mailbox.id,
          email: mailbox.email,
          token: mailbox.token,
          expires_at: mailbox.expires_at,
          messages: Enum.map(messages, &message_to_map/1)
        }}
    end
  end
  
  defp extend_mailbox(token) do
    # Simulate API request
    case Elektrine.Email.get_temporary_mailbox_by_token(token) do
      nil -> {:error, :not_found}
      
      mailbox ->
        case Elektrine.Email.extend_temporary_mailbox(mailbox.id) do
          {:ok, updated_mailbox} ->
            {:ok, %{
              id: updated_mailbox.id,
              email: updated_mailbox.email,
              token: updated_mailbox.token,
              expires_at: updated_mailbox.expires_at
            }}
          
          error -> error
        end
    end
  end
  
  defp get_message(token, id) do
    # Simulate API request
    case Elektrine.Email.get_temporary_mailbox_by_token(token) do
      nil -> {:error, :not_found}
      
      mailbox ->
        case Elektrine.Email.get_message(id) do
          nil -> {:error, :not_found}
          
          message ->
            if message.mailbox_id == mailbox.id do
              {:ok, message_to_map(message)}
            else
              {:error, :forbidden}
            end
        end
    end
  end
  
  defp delete_message(token, id) do
    # Simulate API request
    case Elektrine.Email.get_temporary_mailbox_by_token(token) do
      nil -> {:error, :not_found}
      
      mailbox ->
        case Elektrine.Email.get_message(id) do
          nil -> {:error, :not_found}
          
          message ->
            if message.mailbox_id == mailbox.id do
              Elektrine.Email.delete_message(message)
            else
              {:error, :forbidden}
            end
        end
    end
  end
  
  defp create_test_message(mailbox) do
    message_attrs = %{
      message_id: "temp-test-#{System.system_time(:millisecond)}",
      from: "test-sender@example.com",
      to: mailbox.email,
      subject: "Test Message for Temporary Mailbox",
      text_body: "This is a test message for a temporary mailbox.\n\nThis is being sent through the API test.",
      html_body: "<p>This is a test message for a temporary mailbox.</p><p>This is being sent through the API test.</p>",
      mailbox_id: mailbox.id,
      mailbox_type: "temporary",
      read: false,
      status: "received"
    }

    Elektrine.Email.MailboxAdapter.create_message(message_attrs)
  end
  
  defp message_to_map(message) do
    %{
      id: message.id,
      message_id: message.message_id,
      from: message.from,
      to: message.to,
      subject: message.subject || "(No Subject)",
      text_body: message.text_body,
      html_body: message.html_body,
      read: message.read,
      received_at: message.inserted_at
    }
  end
end