defmodule Elektrine.Accounts.Cached do
  @moduledoc """
  Cached versions of Accounts context functions.
  Provides caching for user data, preferences, and authentication.
  """

  alias Elektrine.Accounts
  alias Elektrine.AppCache

  @doc """
  Gets cached user data by ID.
  """
  def get_user!(id) do
    {:ok, user} = AppCache.get_user_data(id, fn ->
      Accounts.get_user!(id)
    end)
    user
  end

  @doc """
  Gets cached user data by username.
  """
  def get_user_by_username(username) do
    # For username lookups, we cache with a different key
    {:ok, user} = AppCache.get_system_config("user_by_username:#{username}", fn ->
      Accounts.get_user_by_username(username)
    end)
    user
  end

  @doc """
  Gets cached user data by email.
  """
  def get_user_by_email(email) do
    {:ok, user} = AppCache.get_system_config("user_by_email:#{email}", fn ->
      Accounts.get_user_by_email(email)
    end)
    user
  end

  @doc """
  Gets cached user preferences/settings.
  """
  def get_user_preferences(user_id) do
    {:ok, preferences} = AppCache.get_user_preferences(user_id, fn ->
      # This would need to be implemented in Accounts context
      # For now, return basic structure
      %{
        email_notifications: true,
        theme: "light",
        timezone: "UTC",
        language: "en"
      }
    end)
    preferences
  end

  @doc """
  Invalidates all cached data for a user.
  Should be called when user data changes.
  """
  def invalidate_user_cache(user_id) do
    AppCache.invalidate_user_cache(user_id)
    
    # Also clear email/username lookup caches
    try do
      user = Accounts.get_user!(user_id)
      AppCache.get_system_config("user_by_username:#{user.username}", fn -> nil end)
      AppCache.get_system_config("user_by_email:#{user.email}", fn -> nil end)
    rescue
      _ -> :ok
    end
  end
end