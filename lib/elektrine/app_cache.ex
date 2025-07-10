defmodule Elektrine.AppCache do
  @moduledoc """
  Centralized caching system for the entire Elektrine application.
  Provides caching for users, mailboxes, admin data, search results,
  and system configurations.
  """


  # Cache names and TTLs
  @cache_name :app_cache
  @user_ttl :timer.minutes(30)
  @system_ttl :timer.hours(1)
  @search_ttl :timer.minutes(5)
  @admin_ttl :timer.minutes(10)
  @contact_ttl :timer.minutes(15)
  @temp_mailbox_ttl :timer.minutes(2)

  @doc """
  Starts the application cache.
  This should be called from the application supervision tree.
  """
  def start_link(_opts) do
    Cachex.start_link(@cache_name,
      limit: 50_000,
      ttl: @system_ttl
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # User-related caching

  @doc """
  Caches user profile and settings data.
  """
  def get_user_data(user_id, fetch_fn) do
    key = {:user, user_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @user_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches user preferences and settings.
  """
  def get_user_preferences(user_id, fetch_fn) do
    key = {:user_preferences, user_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @user_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches mailbox settings and configuration.
  """
  def get_mailbox_settings(mailbox_id, fetch_fn) do
    key = {:mailbox_settings, mailbox_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @user_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # Search caching

  @doc """
  Caches search results with query-specific keys.
  """
  def get_search_results(user_id, query, page, per_page, fetch_fn) do
    query_hash = :crypto.hash(:md5, query) |> Base.encode16(case: :lower)
    key = {:search, user_id, query_hash, page, per_page}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @search_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches user's recent search queries.
  """
  def get_recent_searches(user_id, fetch_fn) do
    key = {:recent_searches, user_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @system_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # Contact and sender management caching

  @doc """
  Caches approved senders list for a mailbox.
  """
  def get_approved_senders(mailbox_id, fetch_fn) do
    key = {:approved_senders, mailbox_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @contact_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches blocked/rejected senders list for a mailbox.
  """
  def get_blocked_senders(mailbox_id, fetch_fn) do
    key = {:blocked_senders, mailbox_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @contact_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches email aliases for a user.
  """
  def get_aliases(user_id, fetch_fn) do
    key = {:aliases, user_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @contact_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # System configuration caching

  @doc """
  Caches system-wide configuration settings.
  """
  def get_system_config(key, fetch_fn) do
    cache_key = {:system_config, key}
    
    case Cachex.fetch(@cache_name, cache_key, fn _key ->
      {:commit, fetch_fn.(), ttl: @system_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches invite code settings and validation.
  """
  def get_invite_settings(fetch_fn) do
    key = {:invite_settings}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @system_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # Admin dashboard caching

  @doc """
  Caches admin dashboard statistics.
  """
  def get_admin_stats(stat_type, fetch_fn) do
    key = {:admin_stats, stat_type}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @admin_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Caches admin dashboard recent activity data.
  """
  def get_admin_recent_activity(activity_type, fetch_fn) do
    key = {:admin_recent, activity_type}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @admin_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # Temporary mailbox caching

  @doc """
  Caches temporary mailbox validation and metadata.
  """
  def get_temp_mailbox_data(token, fetch_fn) do
    key = {:temp_mailbox, token}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @temp_mailbox_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  # Cache invalidation functions

  @doc """
  Invalidates all cache entries for a specific user.
  """
  def invalidate_user_cache(user_id) do
    patterns = [
      {:user, user_id},
      {:user_preferences, user_id},
      {:recent_searches, user_id},
      {:aliases, user_id}
    ]
    
    patterns
    |> Enum.each(&Cachex.del(@cache_name, &1))
    
    # Also invalidate search results for this user
    clear_user_searches(user_id)
  end

  @doc """
  Invalidates cache entries for a specific mailbox.
  """
  def invalidate_mailbox_cache(mailbox_id) do
    patterns = [
      {:mailbox_settings, mailbox_id},
      {:approved_senders, mailbox_id},
      {:blocked_senders, mailbox_id}
    ]
    
    patterns
    |> Enum.each(&Cachex.del(@cache_name, &1))
  end

  @doc """
  Invalidates system configuration cache.
  """
  def invalidate_system_cache do
    clear_by_pattern({:system_config, :_})
    clear_by_pattern({:invite_settings})
  end

  @doc """
  Invalidates admin dashboard cache.
  """
  def invalidate_admin_cache do
    clear_by_pattern({:admin_stats, :_})
    clear_by_pattern({:admin_recent, :_})
  end

  @doc """
  Invalidates search results for a user.
  """
  def invalidate_search_cache(user_id) do
    clear_user_searches(user_id)
    Cachex.del(@cache_name, {:recent_searches, user_id})
  end

  @doc """
  Invalidates temporary mailbox cache.
  """
  def invalidate_temp_mailbox_cache(token) do
    Cachex.del(@cache_name, {:temp_mailbox, token})
  end

  # Warming functions

  @doc """
  Warms up cache for a user after login.
  """
  def warm_user_cache(user_id, mailbox_id) do
    Task.start(fn ->
      # Warm user data
      try do
        user = Elektrine.Accounts.get_user!(user_id)
        get_user_data(user_id, fn -> user end)
      rescue
        _ -> :ok
      end

      # Warm mailbox settings
      try do
        mailbox = Elektrine.Email.get_mailbox(mailbox_id)
        get_mailbox_settings(mailbox_id, fn -> mailbox end)
      rescue
        _ -> :ok
      end

      # Warm contact lists
      try do
        get_approved_senders(mailbox_id, fn -> 
          Elektrine.Email.list_approved_senders(mailbox_id) 
        end)
        get_blocked_senders(mailbox_id, fn -> 
          Elektrine.Email.list_blocked_senders(mailbox_id) 
        end)
      rescue
        _ -> :ok
      end
    end)
  end

  @doc """
  Gets cache statistics for monitoring.
  """
  def stats do
    Cachex.stats(@cache_name)
  end

  @doc """
  Clears all application cache entries.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end

  @doc """
  Clears cache entries matching a pattern.
  """
  def clear_by_pattern(pattern) do
    {:ok, keys} = Cachex.keys(@cache_name)
    
    keys
    |> Enum.filter(&matches_pattern?(&1, pattern))
    |> Enum.each(&Cachex.del(@cache_name, &1))
  end

  # Private helper functions

  defp clear_user_searches(user_id) do
    {:ok, keys} = Cachex.keys(@cache_name)
    
    keys
    |> Enum.filter(fn
      {:search, ^user_id, _, _, _} -> true
      _ -> false
    end)
    |> Enum.each(&Cachex.del(@cache_name, &1))
  end


  defp matches_pattern?(key, pattern) when is_tuple(key) and is_tuple(pattern) do
    key_list = Tuple.to_list(key)
    pattern_list = Tuple.to_list(pattern)
    
    length(key_list) == length(pattern_list) and
      Enum.zip(key_list, pattern_list)
      |> Enum.all?(fn
        {_key_elem, :_} -> true
        {key_elem, pattern_elem} -> key_elem == pattern_elem
      end)
  end

  defp matches_pattern?(_, _), do: false
end