defmodule ElektrineWeb.API.TemporaryMailboxJSON do
  @doc """
  Renders a temporary mailbox with its messages.
  """
  def show(%{mailbox: mailbox, messages: messages}) do
    %{
      data: %{
        id: mailbox.id,
        email: mailbox.email,
        token: mailbox.token,
        expires_at: mailbox.expires_at,
        remaining_time: calculate_remaining_time(mailbox.expires_at),
        messages: Enum.map(messages, &message_json/1)
      }
    }
  end
  
  # Renders a temporary mailbox without messages.
  def show(%{mailbox: mailbox}) do
    %{
      data: %{
        id: mailbox.id,
        email: mailbox.email,
        token: mailbox.token,
        expires_at: mailbox.expires_at,
        remaining_time: calculate_remaining_time(mailbox.expires_at)
      }
    }
  end
  
  @doc """
  Renders a single message.
  """
  def message(%{message: message}) do
    %{
      data: message_json(message)
    }
  end
  
  # Helper function to format a message as JSON
  defp message_json(message) do
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
  
  # Helper to calculate remaining time until expiration
  defp calculate_remaining_time(expires_at) do
    now = DateTime.utc_now()
    
    case DateTime.compare(expires_at, now) do
      :gt ->
        # Calculate difference in seconds
        diff_seconds = DateTime.diff(expires_at, now, :second)
        %{
          expired: false,
          seconds: diff_seconds,
          minutes: div(diff_seconds, 60),
          hours: div(diff_seconds, 3600)
        }
        
      _ ->
        %{
          expired: true,
          seconds: 0,
          minutes: 0,
          hours: 0
        }
    end
  end
end