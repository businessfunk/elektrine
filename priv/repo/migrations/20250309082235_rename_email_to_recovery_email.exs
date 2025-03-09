defmodule Elektrine.Repo.Migrations.RenameEmailToRecoveryEmail do
  use Ecto.Migration

  def change do
    rename table(:users), :email, to: :recovery_email
    
    # Update the unique index
    drop_if_exists index(:users, [:email])
    create unique_index(:users, [:recovery_email])
  end
end
