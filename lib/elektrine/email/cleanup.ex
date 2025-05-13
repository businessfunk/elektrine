defmodule Elektrine.Email.Cleanup do
  @moduledoc """
  Handles the cleanup of expired temporary mailboxes.
  """
  
  alias Elektrine.Email
  require Logger
  
  @doc """
  Performs the cleanup of expired temporary mailboxes.
  This function should be called periodically, e.g., from a scheduler.
  """
  def cleanup_expired_mailboxes do
    Logger.info("Starting cleanup of expired temporary mailboxes")
    
    case Email.cleanup_expired_temporary_mailboxes() do
      {:ok, count} ->
        Logger.info("Deleted #{count} expired temporary mailboxes")
        {:ok, count}
        
      error ->
        Logger.error("Error cleaning up expired temporary mailboxes: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  A function that can be called by a scheduler to perform periodic cleanup.
  """
  def perform_scheduled_cleanup do
    cleanup_expired_mailboxes()
  end
end