defmodule Mix.Tasks.Email.TestCrossDomain do
  @moduledoc """
  Tests cross-domain email receiving functionality.
  
  Usage:
    mix email.test_cross_domain
  """
  
  use Mix.Task
  
  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    
    alias Elektrine.Email
    alias Elektrine.Accounts
    
    IO.puts("Testing cross-domain email receiving...")
    
    # Get the first user
    user = case Accounts.list_users() |> List.first() do
      nil ->
        IO.puts("No users found. Please create a user first.")
        exit(:normal)
      user -> user
    end
    
    IO.puts("Testing with user: #{user.username}")
    
    # Get or create mailbox for user
    case Email.get_user_mailbox(user.id) do
      nil ->
        case Email.create_mailbox(user) do
          {:ok, mailbox} ->
            IO.puts("Created mailbox: #{mailbox.email}")
            test_cross_domain_lookup(user.username, mailbox.email)
          {:error, reason} ->
            IO.puts("Failed to create mailbox: #{inspect(reason)}")
        end
      mailbox ->
        IO.puts("Found existing mailbox: #{mailbox.email}")
        test_cross_domain_lookup(user.username, mailbox.email)
    end
  end
  
  defp test_cross_domain_lookup(username, _existing_email) do
    # Test both domains
    domains = Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]
    
    Enum.each(domains, fn domain ->
      test_email = "#{username}@#{domain}"
      IO.puts("\nTesting email reception for: #{test_email}")
      
      # Test the receiver function
      result = test_find_mailbox(test_email)
      
      case result do
        {:ok, mailbox} ->
          IO.puts("✓ SUCCESS: Found mailbox #{mailbox.email} for #{test_email}")
        {:error, reason} ->
          IO.puts("✗ FAILED: #{inspect(reason)} for #{test_email}")
      end
    end)
  end
  
  # Simulate the receiver's find_recipient_mailbox function
  defp test_find_mailbox(recipient_email) do
    import Ecto.Query
    alias Elektrine.Email.Mailbox
    alias Elektrine.Repo
    
    # Try exact match first
    mailbox = Mailbox
              |> where(email: ^recipient_email)
              |> Repo.one()
    
    case mailbox do
      nil ->
        # Try cross-domain lookup
        case extract_username_and_domain(recipient_email) do
          {username, domain} ->
            supported_domains = Application.get_env(:elektrine, :email)[:supported_domains] || ["elektrine.com"]
            
            if domain in supported_domains do
              like_patterns = Enum.map(supported_domains, fn d -> "#{username}@#{d}" end)
              
              found_mailbox = Mailbox
              |> where([m], m.email in ^like_patterns)
              |> Repo.one()
              
              if found_mailbox do
                {:ok, found_mailbox}
              else
                {:error, :no_mailbox_found}
              end
            else
              {:error, :unsupported_domain}
            end
          _ ->
            {:error, :invalid_email}
        end
      mailbox ->
        {:ok, mailbox}
    end
  end
  
  defp extract_username_and_domain(email) do
    case String.split(email, "@") do
      [username, domain] -> {username, domain}
      _ -> nil
    end
  end
end