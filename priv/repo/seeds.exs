# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Elektrine.Repo.insert!(%Elektrine.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Elektrine.Accounts
alias Elektrine.Repo

# Only run in development environment
if Mix.env() == :dev do
  IO.puts("Seeding development data...")

  # Create admin user if it doesn't exist
  admin_username = "admin"
  
  case Accounts.get_user_by_username(admin_username) do
    nil ->
      IO.puts("Creating admin user: #{admin_username}")
      {:ok, admin_user} = Accounts.create_user(%{
        username: admin_username,
        password: "adminpass123",
        password_confirmation: "adminpass123"
      })
      
      # Make the user an admin
      {:ok, _admin_user} = Accounts.update_user_admin_status(admin_user, true)
      IO.puts("✓ Admin user created with username: #{admin_username}, password: adminpass123")
      
    existing_user ->
      # Ensure existing user is admin
      if not existing_user.is_admin do
        {:ok, _admin_user} = Accounts.update_user_admin_status(existing_user, true)
        IO.puts("✓ Made existing user '#{admin_username}' an admin")
      else
        IO.puts("✓ Admin user '#{admin_username}' already exists")
      end
  end

  # Create a test user if it doesn't exist
  test_username = "testuser"
  
  case Accounts.get_user_by_username(test_username) do
    nil ->
      IO.puts("Creating test user: #{test_username}")
      {:ok, _test_user} = Accounts.create_user(%{
        username: test_username,
        password: "testpass123",
        password_confirmation: "testpass123"
      })
      IO.puts("✓ Test user created with username: #{test_username}, password: testpass123")
      
    _existing_user ->
      IO.puts("✓ Test user '#{test_username}' already exists")
  end

  IO.puts("Development seeding complete!")
  IO.puts("")
  IO.puts("Available accounts:")
  IO.puts("  Admin: admin / adminpass123")
  IO.puts("  Test User: testuser / testpass123")
else
  IO.puts("Skipping seeds - not in development environment")
end
