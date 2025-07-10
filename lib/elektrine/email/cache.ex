defmodule Elektrine.Email.Cache do
  @moduledoc """
  Caching layer for email-related data to improve performance.
  Uses Cachex for in-memory caching with automatic TTL and invalidation.
  """

  @cache_name :email_cache
  @default_ttl :timer.minutes(5)
  @counts_ttl :timer.minutes(1)
  @messages_ttl :timer.minutes(3)

  @doc """
  Starts the cache with configuration.
  Called from the application supervision tree.
  """
  def start_link(_opts) do
    Cachex.start_link(@cache_name,
      # Limit cache size to prevent memory issues
      limit: 10_000,
      # Default TTL for all entries
      ttl: @default_ttl
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

  # Message count caching

  @doc """
  Gets cached message counts or fetches fresh data.
  """
  def get_counts(user_id, fetch_fn) do
    key = {:counts, user_id}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @counts_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Invalidates all count caches for a user.
  """
  def invalidate_counts(user_id) do
    key = {:counts, user_id}
    Cachex.del(@cache_name, key)
  end

  # Paginated messages caching

  @doc """
  Gets cached paginated messages or fetches fresh data.
  """
  def get_messages(user_id, category, page, per_page, fetch_fn) do
    key = {:messages, user_id, category, page, per_page}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: @messages_ttl}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Invalidates message cache for a specific category or all categories.
  """
  def invalidate_messages(user_id, category \\ :all) do
    if category == :all do
      # Clear all message caches for the user
      pattern = {:messages, user_id, :_, :_, :_}
      clear_by_pattern(pattern)
    else
      # Clear specific category
      pattern = {:messages, user_id, category, :_, :_}
      clear_by_pattern(pattern)
    end
  end

  # Individual message caching

  @doc """
  Caches an individual message.
  """
  def put_message(message_id, message) do
    key = {:message, message_id}
    Cachex.put(@cache_name, key, message, ttl: @messages_ttl)
  end

  @doc """
  Gets a cached individual message.
  """
  def get_message(message_id) do
    key = {:message, message_id}
    Cachex.get(@cache_name, key)
  end

  @doc """
  Invalidates an individual message cache.
  """
  def invalidate_message(message_id) do
    key = {:message, message_id}
    Cachex.del(@cache_name, key)
  end

  # Search results caching

  @doc """
  Caches search results with a shorter TTL.
  """
  def get_search_results(user_id, query, filters, fetch_fn) do
    key = {:search, user_id, query, filters}
    
    case Cachex.fetch(@cache_name, key, fn _key ->
      {:commit, fetch_fn.(), ttl: :timer.minutes(1)}
    end) do
      {:commit, value} -> {:ok, value}
      {:commit, value, _opts} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Invalidates all search result caches for a user.
  """
  def invalidate_search_results(user_id) do
    pattern = {:search, user_id, :_, :_}
    clear_by_pattern(pattern)
  end

  # Utility functions

  @doc """
  Clears all caches for a specific user.
  Useful when user logs out or major changes occur.
  """
  def clear_user_cache(user_id) do
    # Clear counts
    invalidate_counts(user_id)
    
    # Clear messages
    invalidate_messages(user_id, :all)
    
    # Clear search results
    invalidate_search_results(user_id)
  end

  @doc """
  Warms up the cache for a user by preloading common data.
  """
  def warm_cache(_user_id) do
    # This can be called after login to preload frequently accessed data
    # Implementation depends on specific use cases
    :ok
  end

  @doc """
  Gets cache statistics for monitoring.
  """
  def stats do
    Cachex.stats(@cache_name)
  end

  @doc """
  Clears the entire cache. Use with caution!
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end

  # Private functions

  defp clear_by_pattern(pattern) do
    # Note: Cachex doesn't support pattern matching directly,
    # so we need to iterate through keys
    {:ok, keys} = Cachex.keys(@cache_name)
    
    keys
    |> Enum.filter(&matches_pattern?(&1, pattern))
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