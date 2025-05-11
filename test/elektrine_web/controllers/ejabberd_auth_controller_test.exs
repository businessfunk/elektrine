defmodule ElektrineWeb.EjabberdAuthControllerTest do
  use ElektrineWeb.ConnCase

  alias Elektrine.Accounts
  alias Elektrine.Accounts.User

  @valid_user_attrs %{
    username: "testuser",
    password: "password123",
    password_confirmation: "password123"
  }
  @invalid_password "wrongpassword"
  @server "localhost"  # example server domain

  setup do
    # Create a test user
    {:ok, user} = Accounts.create_user(@valid_user_attrs)
    %{user: user}
  end

  describe "auth/2" do
    test "returns true when credentials are valid", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/ejabberd/auth", %{
        "user" => user.username,
        "server" => @server,
        "password" => @valid_user_attrs.password
      })

      assert %{"result" => true} = json_response(conn, 200)
    end

    test "returns false when password is invalid", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/ejabberd/auth", %{
        "user" => user.username,
        "server" => @server,
        "password" => @invalid_password
      })

      assert %{"result" => false} = json_response(conn, 200)
    end

    test "returns false when user does not exist", %{conn: conn} do
      conn = post(conn, ~p"/api/ejabberd/auth", %{
        "user" => "nonexistent",
        "server" => @server,
        "password" => @valid_user_attrs.password
      })

      assert %{"result" => false} = json_response(conn, 200)
    end
  end

  describe "isuser/2" do
    test "returns true when user exists", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/ejabberd/isuser", %{
        "user" => user.username,
        "server" => @server
      })

      assert %{"result" => true} = json_response(conn, 200)
    end

    test "returns false when user does not exist", %{conn: conn} do
      conn = post(conn, ~p"/api/ejabberd/isuser", %{
        "user" => "nonexistent",
        "server" => @server
      })

      assert %{"result" => false} = json_response(conn, 200)
    end
  end

  describe "setpass/2" do
    test "returns true when updating existing user password", %{conn: conn, user: user} do
      new_password = "newpassword123"
      
      conn = post(conn, ~p"/api/ejabberd/setpass", %{
        "user" => user.username,
        "server" => @server,
        "password" => new_password
      })

      assert %{"result" => true} = json_response(conn, 200)

      # Verify the password was actually updated
      assert {:ok, _} = Accounts.authenticate_user(user.username, new_password)
    end

    test "returns false for non-existent user", %{conn: conn} do
      conn = post(conn, ~p"/api/ejabberd/setpass", %{
        "user" => "nonexistent",
        "server" => @server,
        "password" => "anypassword123"
      })

      assert %{"result" => false} = json_response(conn, 200)
    end

    test "returns false when password is invalid", %{conn: conn, user: user} do
      # Try with a short password that will fail validation
      conn = post(conn, ~p"/api/ejabberd/setpass", %{
        "user" => user.username,
        "server" => @server,
        "password" => "short"  # Too short to meet validation
      })

      assert %{"result" => false} = json_response(conn, 200)
    end
  end
end