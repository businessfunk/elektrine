defmodule ElektrineWeb.AdminController do
  use ElektrineWeb, :controller

  alias Elektrine.{Accounts, Email, Repo}
  import Ecto.Query

  plug :put_layout, html: {ElektrineWeb.Layouts, :admin}

  def dashboard(conn, _params) do
    invite_code_stats = Accounts.get_invite_code_stats()
    
    stats = %{
      total_users: get_user_count(),
      total_mailboxes: get_mailbox_count(),
      total_messages: get_message_count(),
      temp_mailboxes: get_temp_mailbox_count(),
      recent_users: get_recent_users(),
      pending_deletions: get_pending_deletion_count(),
      invite_codes_active: invite_code_stats.active
    }

    render(conn, :dashboard, stats: stats)
  end

  def users(conn, params) do
    search_query = Map.get(params, "search", "")
    users = if search_query != "", do: search_users(search_query), else: Accounts.list_users()
    render(conn, :users, users: users, search_query: search_query)
  end

  def new(conn, _params) do
    changeset = Accounts.change_user_admin_registration(%Accounts.User{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.admin_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User #{user.username} created successfully.")
        |> redirect(to: ~p"/admin/users")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def toggle_admin(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    case Accounts.update_user_admin_status(user, !user.is_admin) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, "User admin status updated successfully.")
        |> redirect(to: ~p"/admin/users")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update user admin status.")
        |> redirect(to: ~p"/admin/users")
    end
  end

  def edit(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    changeset = Accounts.change_user_admin(user)
    render(conn, :edit, user: user, changeset: changeset)
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    user = Accounts.get_user!(id)

    case Accounts.admin_update_user(user, user_params) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, "User updated successfully.")
        |> redirect(to: ~p"/admin/users")

      {:error, changeset} ->
        render(conn, :edit, user: user, changeset: changeset)
    end
  end

  def ban(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    # Prevent banning admin users
    if user.is_admin do
      conn
      |> put_flash(:error, "Admin users cannot be banned.")
      |> redirect(to: ~p"/admin/users")
    else
      render(conn, :ban, user: user)
    end
  end

  def confirm_ban(conn, %{"id" => id, "ban" => ban_params}) do
    user = Accounts.get_user!(id)

    # Prevent banning admin users
    if user.is_admin do
      conn
      |> put_flash(:error, "Admin users cannot be banned.")
      |> redirect(to: ~p"/admin/users")
    else
      case Accounts.ban_user(user, ban_params) do
        {:ok, _banned_user} ->
          conn
          |> put_flash(:info, "User has been banned successfully.")
          |> redirect(to: ~p"/admin/users")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Failed to ban user.")
          |> redirect(to: ~p"/admin/users")
      end
    end
  end

  def unban(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    case Accounts.unban_user(user) do
      {:ok, _unbanned_user} ->
        conn
        |> put_flash(:info, "User has been unbanned successfully.")
        |> redirect(to: ~p"/admin/users")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to unban user.")
        |> redirect(to: ~p"/admin/users")
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    cond do
      # Prevent admins from deleting themselves
      user.id == conn.assigns.current_user.id ->
        conn
        |> put_flash(:error, "You cannot delete your own account.")
        |> redirect(to: ~p"/admin/users")

      # Prevent deleting admin users
      user.is_admin ->
        conn
        |> put_flash(:error, "Admin users cannot be deleted.")
        |> redirect(to: ~p"/admin/users")

      true ->
        case Accounts.admin_delete_user(user) do
          {:ok, _deleted_user} ->
            conn
            |> put_flash(:info, "User and all associated data deleted successfully.")
            |> redirect(to: ~p"/admin/users")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to delete user.")
            |> redirect(to: ~p"/admin/users")
        end
    end
  end

  def mailboxes(conn, params) do
    search_query = Map.get(params, "search", "")

    mailboxes =
      if search_query != "", do: search_mailboxes(search_query), else: get_all_mailboxes()

    render(conn, :mailboxes, mailboxes: mailboxes, search_query: search_query)
  end

  def messages(conn, params) do
    search_query = Map.get(params, "search", "")

    messages =
      if search_query != "", do: search_messages(search_query), else: get_recent_messages()

    render(conn, :messages, messages: messages, search_query: search_query)
  end

  # Private helper functions

  defp get_user_count do
    Repo.aggregate(Accounts.User, :count, :id)
  end

  defp get_mailbox_count do
    Repo.aggregate(Email.Mailbox, :count, :id)
  end

  defp get_message_count do
    Repo.aggregate(Email.Message, :count, :id)
  end

  defp get_temp_mailbox_count do
    Repo.aggregate(Email.TemporaryMailbox, :count, :id)
  end

  defp get_recent_users do
    from(u in Accounts.User,
      order_by: [desc: u.inserted_at],
      limit: 10,
      select: [:id, :username, :is_admin, :banned, :inserted_at]
    )
    |> Repo.all()
  end

  defp get_all_mailboxes do
    from(m in Email.Mailbox,
      join: u in Accounts.User,
      on: m.user_id == u.id,
      order_by: [desc: m.inserted_at],
      limit: 50,
      select: %{
        id: m.id,
        email: m.email,
        temporary: m.temporary,
        username: u.username,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  defp get_recent_messages do
    from(m in Email.Message,
      join: mb in Email.Mailbox,
      on: m.mailbox_id == mb.id,
      join: u in Accounts.User,
      on: mb.user_id == u.id,
      order_by: [desc: m.inserted_at],
      limit: 50,
      select: %{
        id: m.id,
        subject: m.subject,
        from: m.from,
        username: u.username,
        mailbox_email: mb.email,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  def deletion_requests(conn, _params) do
    requests = Accounts.list_deletion_requests()
    render(conn, :deletion_requests, requests: requests)
  end

  def show_deletion_request(conn, %{"id" => id}) do
    request = Accounts.get_deletion_request!(id)
    render(conn, :show_deletion_request, request: request)
  end

  def approve_deletion_request(conn, %{"id" => id, "admin_notes" => admin_notes}) do
    request = Accounts.get_deletion_request!(id)
    admin = conn.assigns.current_user

    case Accounts.review_deletion_request(request, admin, "approved", %{admin_notes: admin_notes}) do
      {:ok, _updated_request} ->
        conn
        |> put_flash(:info, "Account deletion request approved and user account deleted.")
        |> redirect(to: ~p"/admin/deletion-requests")

      {:error, error} when is_binary(error) ->
        conn
        |> put_flash(:error, error)
        |> redirect(to: ~p"/admin/deletion-requests/#{id}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to approve deletion request.")
        |> redirect(to: ~p"/admin/deletion-requests/#{id}")
    end
  end

  def approve_deletion_request(conn, %{"id" => id}) do
    approve_deletion_request(conn, %{"id" => id, "admin_notes" => ""})
  end

  def deny_deletion_request(conn, %{"id" => id, "admin_notes" => admin_notes}) do
    request = Accounts.get_deletion_request!(id)
    admin = conn.assigns.current_user

    case Accounts.review_deletion_request(request, admin, "denied", %{admin_notes: admin_notes}) do
      {:ok, _updated_request} ->
        conn
        |> put_flash(:info, "Account deletion request denied.")
        |> redirect(to: ~p"/admin/deletion-requests")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to deny deletion request.")
        |> redirect(to: ~p"/admin/deletion-requests/#{id}")
    end
  end

  def deny_deletion_request(conn, %{"id" => id}) do
    deny_deletion_request(conn, %{"id" => id, "admin_notes" => ""})
  end

  defp search_users(search_query) do
    search_term = "%#{search_query}%"

    from(u in Accounts.User,
      where: ilike(u.username, ^search_term),
      order_by: [desc: u.inserted_at],
      select: [:id, :username, :is_admin, :banned, :inserted_at]
    )
    |> Repo.all()
  end

  defp search_mailboxes(search_query) do
    search_term = "%#{search_query}%"

    from(m in Email.Mailbox,
      join: u in Accounts.User,
      on: m.user_id == u.id,
      where: ilike(m.email, ^search_term) or ilike(u.username, ^search_term),
      order_by: [desc: m.inserted_at],
      limit: 50,
      select: %{
        id: m.id,
        email: m.email,
        temporary: m.temporary,
        username: u.username,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  defp search_messages(search_query) do
    search_term = "%#{search_query}%"

    from(m in Email.Message,
      join: mb in Email.Mailbox,
      on: m.mailbox_id == mb.id,
      join: u in Accounts.User,
      on: mb.user_id == u.id,
      where:
        ilike(m.subject, ^search_term) or ilike(m.from, ^search_term) or
          ilike(u.username, ^search_term),
      order_by: [desc: m.inserted_at],
      limit: 50,
      select: %{
        id: m.id,
        subject: m.subject,
        from: m.from,
        username: u.username,
        mailbox_email: mb.email,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
  end

  defp get_pending_deletion_count do
    from(r in Elektrine.Accounts.AccountDeletionRequest,
      where: r.status == "pending"
    )
    |> Repo.aggregate(:count)
  end
  
  # Invite Code management
  
  def invite_codes(conn, _params) do
    invite_codes = Accounts.list_invite_codes()
    stats = Accounts.get_invite_code_stats()
    render(conn, :invite_codes, invite_codes: invite_codes, stats: stats)
  end
  
  def new_invite_code(conn, _params) do
    changeset = Accounts.change_invite_code(%Elektrine.Accounts.InviteCode{})
    render(conn, :new_invite_code, changeset: changeset)
  end
  
  def create_invite_code(conn, %{"invite_code" => invite_code_params}) do
    invite_code_params = Map.put(invite_code_params, "created_by_id", conn.assigns.current_user.id)
    
    case Accounts.create_invite_code(invite_code_params) do
      {:ok, _invite_code} ->
        conn
        |> put_flash(:info, "Invite code created successfully.")
        |> redirect(to: ~p"/admin/invite-codes")
        
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new_invite_code, changeset: changeset)
    end
  end
  
  def edit_invite_code(conn, %{"id" => id}) do
    invite_code = Accounts.get_invite_code(id)
    changeset = Accounts.change_invite_code(invite_code)
    render(conn, :edit_invite_code, invite_code: invite_code, changeset: changeset)
  end
  
  def update_invite_code(conn, %{"id" => id, "invite_code" => invite_code_params}) do
    invite_code = Accounts.get_invite_code(id)
    
    case Accounts.update_invite_code(invite_code, invite_code_params) do
      {:ok, _invite_code} ->
        conn
        |> put_flash(:info, "Invite code updated successfully.")
        |> redirect(to: ~p"/admin/invite-codes")
        
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit_invite_code, invite_code: invite_code, changeset: changeset)
    end
  end
  
  def delete_invite_code(conn, %{"id" => id}) do
    invite_code = Accounts.get_invite_code(id)
    {:ok, _invite_code} = Accounts.delete_invite_code(invite_code)
    
    conn
    |> put_flash(:info, "Invite code deleted successfully.")
    |> redirect(to: ~p"/admin/invite-codes")
  end
end
