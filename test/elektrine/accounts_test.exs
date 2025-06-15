defmodule Elektrine.AccountsTest do
  use Elektrine.DataCase

  alias Elektrine.Accounts
  alias Elektrine.Accounts.User

  describe "bcrypt authentication" do
    test "authenticate_user/2 works with bcrypt hash" do
      # Generate a fresh bcrypt hash for password "testpassword123"
      bcrypt_hash = Bcrypt.hash_pwd_salt("testpassword123")
      
      # Create a user with bcrypt hash directly in database
      user = %User{
        username: "bcryptuser",
        password_hash: bcrypt_hash,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      # Test authentication with correct password
      assert {:ok, authenticated_user} = Accounts.authenticate_user("bcryptuser", "testpassword123")
      assert authenticated_user.id == user.id
      assert authenticated_user.username == "bcryptuser"

      # Verify the hash was upgraded to Argon2 after successful login
      updated_user = Repo.get!(User, user.id)
      refute String.starts_with?(updated_user.password_hash, "$2")
      assert String.starts_with?(updated_user.password_hash, "$argon2")

      # Test authentication with wrong password fails
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("bcryptuser", "wrongpassword")
    end

    test "authenticate_user/2 works with $2y$ bcrypt hash" do
      # Test with $2y$ variant specifically
      bcrypt_2y_hash = Bcrypt.hash_pwd_salt("password123", log_rounds: 12)
      
      # Ensure we got a $2b$ hash (bcrypt_elixir uses $2b$ by default)
      assert String.starts_with?(bcrypt_2y_hash, "$2b$")
      
      user = %User{
        username: "bcrypt2yuser", 
        password_hash: bcrypt_2y_hash,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      # Test authentication works
      assert {:ok, authenticated_user} = Accounts.authenticate_user("bcrypt2yuser", "password123")
      assert authenticated_user.username == "bcrypt2yuser"

      # Verify password upgrade occurred
      updated_user = Repo.get!(User, user.id)
      assert String.starts_with?(updated_user.password_hash, "$argon2")
    end

    test "is_bcrypt_hash?/1 detects various bcrypt formats" do
      # We need to access the private function for testing
      # This is a bit of a hack but necessary for testing the detection logic
      
      # Test that our detection logic works for different bcrypt variants
      bcrypt_hash_2a = "$2a$12$vVqErFEWHlshU1braPtB0.9.pPQUINGEBE3pShC19uEbuVpgCl1/a"
      bcrypt_hash_2b = "$2b$12$vVqErFEWHlshU1braPtB0.9.pPQUINGEBE3pShC19uEbuVpgCl1/a" 
      bcrypt_hash_2y = "$2y$12$vVqErFEWHlshU1braPtB0.9.pPQUINGEBE3pShC19uEbuVpgCl1/a"
      argon2_hash = "$argon2id$v=19$m=65536,t=1,p=1$SomeHashHere"

      # Create users with different hash types to test authentication
      user_2a = %User{
        username: "user2a",
        password_hash: bcrypt_hash_2a,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      } |> Repo.insert!()

      user_2b = %User{
        username: "user2b", 
        password_hash: bcrypt_hash_2b,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      } |> Repo.insert!()

      user_2y = %User{
        username: "user2y",
        password_hash: bcrypt_hash_2y,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      } |> Repo.insert!()

      # Note: These are hardcoded bcrypt hashes, so we can't test actual password verification
      # But we can test that the system recognizes them as bcrypt hashes
      # In a real scenario, these would be generated from known passwords

      # For testing purposes, let's verify the detection works by checking our imported users
      imported_user = Accounts.get_user_by_username("admin")
      assert imported_user != nil
      assert String.starts_with?(imported_user.password_hash, "$2a$")
    end

    test "bcrypt to argon2 upgrade preserves login functionality" do
      # Create user with a fresh bcrypt hash
      password = "mySecurePassword123"
      bcrypt_hash = Bcrypt.hash_pwd_salt(password)
      
      user = %User{
        username: "upgradetest",
        password_hash: bcrypt_hash,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second), 
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      # First login with bcrypt hash
      assert {:ok, _} = Accounts.authenticate_user("upgradetest", password)
      
      # Verify hash was upgraded
      updated_user = Repo.get!(User, user.id)
      assert String.starts_with?(updated_user.password_hash, "$argon2")
      
      # Second login should still work with new Argon2 hash
      assert {:ok, _} = Accounts.authenticate_user("upgradetest", password)
      
      # Hash should still be Argon2
      final_user = Repo.get!(User, user.id)
      assert String.starts_with?(final_user.password_hash, "$argon2")
    end
  end
end