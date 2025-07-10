defmodule Elektrine.Email.Cached do
  @moduledoc """
  Cached versions of Email context functions.
  This module provides cached wrappers around frequently-accessed Email functions
  to improve performance and reduce database load.
  """

  alias Elektrine.Email
  alias Elektrine.Email.Cache
  alias Elektrine.AppCache

  @doc """
  Gets cached unread count for a mailbox.
  """
  def unread_count(mailbox_id) do
    {:ok, count} = Cache.get_counts("mailbox:#{mailbox_id}:unread", fn ->
      Email.unread_count(mailbox_id)
    end)
    count
  end

  @doc """
  Gets cached unread count for a user.
  """
  def user_unread_count(user_id) do
    {:ok, count} = Cache.get_counts("user:#{user_id}:unread", fn ->
      Email.user_unread_count(user_id)
    end)
    count
  end

  @doc """
  Gets cached paginated messages with automatic cache invalidation.
  """
  def list_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :all, page, per_page, fn ->
      Email.list_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached inbox messages paginated.
  """
  def list_inbox_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :inbox, page, per_page, fn ->
      Email.list_inbox_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached screener messages paginated.
  """
  def list_screener_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :screener, page, per_page, fn ->
      Email.list_screener_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached feed messages paginated.
  """
  def list_feed_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :feed, page, per_page, fn ->
      Email.list_feed_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached paper trail messages paginated.
  """
  def list_paper_trail_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :paper_trail, page, per_page, fn ->
      Email.list_paper_trail_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached set aside messages paginated.
  """
  def list_set_aside_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :set_aside, page, per_page, fn ->
      Email.list_set_aside_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached reply later messages paginated.
  """
  def list_reply_later_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    {:ok, result} = Cache.get_messages(mailbox_id, :reply_later, page, per_page, fn ->
      Email.list_reply_later_messages_paginated(mailbox_id, page, per_page)
    end)
    result
  end

  @doc """
  Gets cached screener messages count.
  """
  def screener_messages_count(mailbox_id) do
    {:ok, count} = Cache.get_counts("mailbox:#{mailbox_id}:screener", fn ->
      Email.list_screener_messages(mailbox_id) |> length()
    end)
    count
  end

  @doc """
  Gets cached feed messages count.
  """
  def feed_messages_count(mailbox_id) do
    {:ok, count} = Cache.get_counts("mailbox:#{mailbox_id}:feed", fn ->
      Email.list_feed_messages(mailbox_id) |> length()
    end)
    count
  end

  @doc """
  Invalidates caches when a message is created, updated, or deleted.
  Should be called from Email context functions that modify messages.
  """
  def invalidate_message_caches(mailbox_id, user_id, categories \\ [:all]) do
    # Invalidate counts
    Cache.invalidate_counts("mailbox:#{mailbox_id}:unread")
    Cache.invalidate_counts("user:#{user_id}:unread")
    Cache.invalidate_counts("mailbox:#{mailbox_id}:screener")
    Cache.invalidate_counts("mailbox:#{mailbox_id}:feed")
    
    # Invalidate message lists
    if categories == [:all] do
      Cache.invalidate_messages(mailbox_id, :all)
    else
      Enum.each(categories, fn category ->
        Cache.invalidate_messages(mailbox_id, category)
      end)
    end
    
    # Also clear search results as they might be affected
    Cache.invalidate_search_results(user_id)
  end

  # Contact and alias management

  @doc """
  Gets cached approved senders for a mailbox.
  """
  def get_approved_senders(mailbox_id) do
    {:ok, senders} = AppCache.get_approved_senders(mailbox_id, fn ->
      Email.list_approved_senders(mailbox_id)
    end)
    senders
  end

  @doc """
  Gets cached blocked/rejected senders for a mailbox.
  """
  def get_blocked_senders(mailbox_id) do
    {:ok, senders} = AppCache.get_blocked_senders(mailbox_id, fn ->
      Email.list_blocked_senders(mailbox_id)
    end)
    senders
  end

  @doc """
  Gets cached aliases for a user.
  """
  def get_aliases(user_id) do
    {:ok, aliases} = AppCache.get_aliases(user_id, fn ->
      Email.list_aliases(user_id)
    end)
    aliases
  end

  @doc """
  Gets cached mailbox settings.
  """
  def get_mailbox_settings(mailbox_id) do
    {:ok, settings} = AppCache.get_mailbox_settings(mailbox_id, fn ->
      Email.get_mailbox(mailbox_id)
    end)
    settings
  end

  @doc """
  Invalidates contact-related caches for a mailbox.
  """
  def invalidate_contact_caches(mailbox_id, user_id) do
    AppCache.invalidate_mailbox_cache(mailbox_id)
    AppCache.invalidate_user_cache(user_id)
  end

  @doc """
  Warms up cache for a user after login.
  """
  def warm_user_cache(user_id, mailbox_id) do
    # Use the AppCache warming function which is more comprehensive
    AppCache.warm_user_cache(user_id, mailbox_id)
    
    # Also warm email-specific data
    Task.start(fn ->
      # Load counts
      unread_count(mailbox_id)
      screener_messages_count(mailbox_id)
      feed_messages_count(mailbox_id)
      
      # Load first page of inbox
      list_inbox_messages_paginated(mailbox_id, 1, 20)
    end)
  end
end