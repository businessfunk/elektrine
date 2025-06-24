defmodule Mix.Tasks.Email.Recategorize do
  @moduledoc """
  Re-categorizes existing messages in all mailboxes based on current categorization rules.

  Usage:
    mix email.recategorize
  """

  use Mix.Task

  alias Elektrine.Email
  alias Elektrine.Accounts

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Re-categorizing existing messages...")

    # Get all users and their mailboxes
    users = Accounts.list_users()

    Enum.each(users, fn user ->
      case Email.get_user_mailbox(user.id) do
        nil ->
          IO.puts("No mailbox found for user #{user.id}")

        mailbox ->
          IO.puts(
            "Re-categorizing messages for mailbox #{mailbox.id} (user: #{user.username})..."
          )

          Email.recategorize_messages(mailbox.id)
      end
    end)

    IO.puts("Done!")
  end
end
