defmodule Elektrine.Email.TempMailboxCached do
  @moduledoc """
  Cached operations for temporary mailboxes.
  Provides fast access to temporary mailbox data and validation.
  """

  alias Elektrine.Email
  alias Elektrine.AppCache

  @doc """
  Gets cached temporary mailbox data by token.
  """
  def get_temp_mailbox_by_token(token) do
    {:ok, mailbox} = AppCache.get_temp_mailbox_data(token, fn ->
      Email.get_temporary_mailbox_by_token(token)
    end)
    mailbox
  end

  @doc """
  Gets cached temporary mailbox data by email.
  """
  def get_temp_mailbox_by_email(email) do
    # For email lookups, we use a system cache since email doesn't change
    {:ok, mailbox} = AppCache.get_system_config("temp_mailbox_by_email:#{email}", fn ->
      Email.get_temporary_mailbox_by_email(email)
    end)
    mailbox
  end

  @doc """
  Gets cached message count for a temporary mailbox.
  """
  def get_temp_mailbox_message_count(mailbox_id) do
    {:ok, count} = AppCache.get_system_config("temp_mailbox_count:#{mailbox_id}", fn ->
      Email.list_messages(mailbox_id) |> length()
    end)
    count
  end

  @doc """
  Gets cached messages for a temporary mailbox with pagination.
  """
  def list_temp_mailbox_messages(token, page \\ 1, per_page \\ 20) do
    case get_temp_mailbox_by_token(token) do
      nil -> 
        %{messages: [], page: page, per_page: per_page, total_count: 0, total_pages: 0, has_next: false, has_prev: false}
      mailbox -> 
        {:ok, result} = AppCache.get_system_config("temp_mailbox_messages:#{mailbox.id}:#{page}:#{per_page}", fn ->
          # This would implement proper pagination for temp mailbox messages
          messages = Email.list_messages(mailbox.id, per_page, (page - 1) * per_page)
          total_count = get_temp_mailbox_message_count(mailbox.id)
          total_pages = ceil(total_count / per_page)
          
          %{
            messages: messages,
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: total_pages,
            has_next: page < total_pages,
            has_prev: page > 1
          }
        end)
        result
    end
  end

  @doc """
  Validates if a temporary mailbox is still active (not expired).
  """
  def is_temp_mailbox_active?(token) do
    case get_temp_mailbox_by_token(token) do
      nil -> false
      mailbox -> 
        DateTime.compare(mailbox.expires_at, DateTime.utc_now()) == :gt
    end
  end

  @doc """
  Gets cached expiration info for a temporary mailbox.
  """
  def get_expiration_info(token) do
    {:ok, info} = AppCache.get_temp_mailbox_data("#{token}_expiration", fn ->
      case get_temp_mailbox_by_token(token) do
        nil -> nil
        mailbox ->
          now = DateTime.utc_now()
          remaining_seconds = DateTime.diff(mailbox.expires_at, now)
          
          %{
            expires_at: mailbox.expires_at,
            remaining_seconds: max(0, remaining_seconds),
            is_active: remaining_seconds > 0,
            expires_in_minutes: max(0, div(remaining_seconds, 60))
          }
      end
    end)
    info
  end

  @doc """
  Invalidates all cache entries for a temporary mailbox.
  """
  def invalidate_temp_mailbox_cache(token) do
    AppCache.invalidate_temp_mailbox_cache(token)
    
    # Also clear related caches
    case get_temp_mailbox_by_token(token) do
      nil -> :ok
      mailbox ->
        AppCache.get_system_config("temp_mailbox_by_email:#{mailbox.email}", fn -> nil end)
        AppCache.get_system_config("temp_mailbox_count:#{mailbox.id}", fn -> nil end)
        clear_temp_mailbox_messages_cache(mailbox.id)
    end
  end

  @doc """
  Invalidates cache when a new message arrives at a temporary mailbox.
  """
  def invalidate_on_new_message(mailbox_id) do
    # Clear message count and pagination caches
    AppCache.get_system_config("temp_mailbox_count:#{mailbox_id}", fn -> nil end)
    clear_temp_mailbox_messages_cache(mailbox_id)
  end

  @doc """
  Pre-warms cache for a temporary mailbox.
  """
  def warm_temp_mailbox_cache(token) do
    Task.start(fn ->
      # Preload mailbox data
      get_temp_mailbox_by_token(token)
      
      # Preload expiration info
      get_expiration_info(token)
      
      # Preload first page of messages
      list_temp_mailbox_messages(token, 1, 20)
    end)
  end

  # Private helper functions

  defp clear_temp_mailbox_messages_cache(mailbox_id) do
    # Clear all pagination caches for this mailbox
    {:ok, keys} = Cachex.keys(:app_cache)
    
    keys
    |> Enum.filter(fn
      {:system_config, "temp_mailbox_messages:" <> rest} ->
        String.starts_with?(rest, "#{mailbox_id}:")
      _ -> false
    end)
    |> Enum.each(&Cachex.del(:app_cache, &1))
  end
end