defmodule Elektrine.Email do
  @moduledoc """
  The Email context.
  This context handles all email-related functionality like managing mailboxes,
  sending/receiving emails, and storing/retrieving email messages.
  """

  import Ecto.Query, warn: false
  alias Elektrine.Repo

  alias Elektrine.Email.Mailbox
  alias Elektrine.Email.Message
  alias Elektrine.Email.TemporaryMailbox
  alias Elektrine.Email.ApprovedSender
  alias Elektrine.Email.RejectedSender
  alias Elektrine.Email.Alias
  alias Elektrine.Email.CacheHooks

  @doc """
  Gets a user's mailbox.
  Returns nil if the Mailbox does not exist.
  """
  def get_user_mailbox(user_id) do
    Mailbox
    |> where(user_id: ^user_id)
    |> Repo.one()
  end

  @doc """
  Gets a single mailbox.
  Returns nil if the Mailbox does not exist.
  """
  def get_mailbox(id), do: Repo.get(Mailbox, id)

  @doc """
  Gets a single mailbox for a specific user.
  Returns nil if the Mailbox does not exist for that user.
  """
  def get_mailbox(id, user_id) do
    Mailbox
    |> where(id: ^id, user_id: ^user_id)
    |> Repo.one()
  end

  @doc """
  Creates a mailbox for a user or with the given parameters.
  """
  def create_mailbox(user) when is_struct(user) do
    Mailbox.create_for_user(user)
    |> Repo.insert()
  end

  def create_mailbox(mailbox_params) when is_map(mailbox_params) do
    %Mailbox{}
    |> Mailbox.changeset(mailbox_params)
    |> Repo.insert()
  end

  @doc """
  Ensures a user has a mailbox, creating one if it doesn't exist.
  """
  def ensure_user_has_mailbox(user) do
    case get_user_mailbox(user.id) do
      nil -> create_mailbox(user)
      mailbox -> {:ok, mailbox}
    end
  end

  @doc """
  Returns the list of mailboxes for a user.
  """
  def list_mailboxes(user_id) do
    Mailbox
    |> where(user_id: ^user_id)
    |> order_by([m], desc: m.primary, asc: m.email)
    |> Repo.all()
  end

  @doc """
  Returns all mailboxes in the system.
  """
  def list_all_mailboxes do
    Mailbox
    |> order_by([m], asc: m.id)
    |> Repo.all()
  end

  @doc """
  Updates a mailbox.
  """
  def update_mailbox(mailbox, attrs) do
    mailbox
    |> Mailbox.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mailbox.
  """
  def delete_mailbox(mailbox) do
    Repo.delete(mailbox)
  end

  @doc """
  Returns the list of messages for a user.
  """
  def list_user_messages(user_id, limit \\ 50, offset \\ 0) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      list_messages(mailbox.id, limit, offset)
    else
      []
    end
  end

  @doc """
  Returns the list of messages for a mailbox.
  """
  def list_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns the list of non-spam, non-archived messages for a mailbox.
  """
  def list_inbox_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, spam: false, archived: false)
    |> where([m], m.status != "sent" or is_nil(m.status))
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns the list of spam messages for a mailbox.
  """
  def list_spam_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, spam: true)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns the list of archived messages for a mailbox.
  """
  def list_archived_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, archived: true)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns paginated messages for a mailbox with metadata.
  """
  def list_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns paginated inbox messages (non-spam, non-archived) for a mailbox with metadata.
  """
  def list_inbox_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, spam: false, archived: false)
      |> where([m], m.status != "sent" or is_nil(m.status))
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_inbox_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns paginated spam messages for a mailbox with metadata.
  """
  def list_spam_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, spam: true)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_spam_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns paginated archived messages for a mailbox with metadata.
  """
  def list_archived_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, archived: true)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_archived_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns paginated sent messages for a mailbox with metadata.
  """
  def list_sent_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where([m], m.mailbox_id == ^mailbox_id and m.status == "sent")
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages =
      Message
      |> where([m], m.mailbox_id == ^mailbox_id and m.status == "sent")
      |> order_by(desc: :inserted_at)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns the list of unread messages for a user.
  """
  def list_user_unread_messages(user_id) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      list_unread_messages(mailbox.id)
    else
      []
    end
  end

  @doc """
  Returns the list of unread messages for a mailbox.
  """
  def list_unread_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, read: false)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single message.
  Returns nil if the Message does not exist.
  """
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Gets a single message for a specific mailbox.
  Returns nil if the Message does not exist for that mailbox.
  """
  def get_message(id, mailbox_id) do
    Message
    |> where(id: ^id, mailbox_id: ^mailbox_id)
    |> Repo.one()
  end

  @doc """
  Gets a single message by its message_id for a specific mailbox.
  Returns nil if the Message does not exist for that mailbox.
  This is used to prevent duplicate message creation.
  """
  def get_message_by_id(message_id, mailbox_id) do
    Message
    |> where(message_id: ^message_id, mailbox_id: ^mailbox_id)
    |> Repo.one()
  end

  @doc """
  Creates a message.
  """
  def create_message(attrs \\ %{}) do
    result =
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, message} ->
        # Broadcast to any LiveViews monitoring this mailbox
        if Map.has_key?(attrs, :mailbox_id) do
          Phoenix.PubSub.broadcast!(
            Elektrine.PubSub,
            "mailbox:#{attrs.mailbox_id}",
            {:new_email, message}
          )
        end

        # Return the original result with cache invalidation
        CacheHooks.with_cache_invalidation({:ok, message})

      error ->
        error
    end
  end

  @doc """
  Updates a message.
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
    |> CacheHooks.with_cache_invalidation()
  end

  @doc """
  Marks a message as read.
  """
  def mark_as_read(%Message{} = message) do
    result =
      message
      |> Message.read_changeset()
      |> Repo.update()

    case result do
      {:ok, updated_message} ->
        # Get the mailbox to find the user_id
        mailbox = get_mailbox(updated_message.mailbox_id)

        if mailbox && mailbox.user_id do
          # Get the new unread count
          new_unread_count = unread_count(updated_message.mailbox_id)

          # Broadcast the unread count update
          Phoenix.PubSub.broadcast!(
            Elektrine.PubSub,
            "user:#{mailbox.user_id}",
            {:unread_count_updated, new_unread_count}
          )
        end

        CacheHooks.with_cache_invalidation({:ok, updated_message}, user_id: mailbox && mailbox.user_id)

      error ->
        error
    end
  end

  @doc """
  Marks a message as unread.
  """
  def mark_as_unread(%Message{} = message) do
    result =
      message
      |> Message.unread_changeset()
      |> Repo.update()

    case result do
      {:ok, updated_message} ->
        # Get the mailbox to find the user_id
        mailbox = get_mailbox(updated_message.mailbox_id)

        if mailbox && mailbox.user_id do
          # Get the new unread count
          new_unread_count = unread_count(updated_message.mailbox_id)

          # Broadcast the unread count update
          Phoenix.PubSub.broadcast!(
            Elektrine.PubSub,
            "user:#{mailbox.user_id}",
            {:unread_count_updated, new_unread_count}
          )
        end

        {:ok, updated_message}

      error ->
        error
    end
  end

  @doc """
  Marks a message as spam.
  """
  def mark_as_spam(%Message{} = message) do
    message
    |> Message.spam_changeset()
    |> Repo.update()
    |> CacheHooks.with_cache_invalidation()
  end

  @doc """
  Marks a message as not spam.
  """
  def mark_as_not_spam(%Message{} = message) do
    message
    |> Message.unspam_changeset()
    |> Repo.update()
  end

  @doc """
  Archives a message.
  """
  def archive_message(%Message{} = message) do
    message
    |> Message.archive_changeset()
    |> Repo.update()
    |> CacheHooks.with_cache_invalidation()
  end

  @doc """
  Unarchives a message.
  """
  def unarchive_message(%Message{} = message) do
    message
    |> Message.unarchive_changeset()
    |> Repo.update()
    |> CacheHooks.with_cache_invalidation()
  end

  @doc """
  Deletes a message.
  """
  def delete_message(%Message{} = message) do
    # Store info before deletion
    was_unread = !message.read
    mailbox_id = message.mailbox_id

    result = Repo.delete(message)

    case result do
      {:ok, _deleted_message} ->
        mailbox = get_mailbox(mailbox_id)
        
        # Only broadcast if the deleted message was unread
        if was_unread do
          if mailbox && mailbox.user_id do
            # Get the new unread count
            new_unread_count = unread_count(mailbox_id)

            # Broadcast the unread count update
            Phoenix.PubSub.broadcast!(
              Elektrine.PubSub,
              "user:#{mailbox.user_id}",
              {:unread_count_updated, new_unread_count}
            )
          end
        end

        # Invalidate caches after deletion
        user_id = if mailbox, do: mailbox.user_id
        CacheHooks.with_cache_invalidation(result, user_id: user_id, mailbox_id: mailbox_id)

      error ->
        error
    end
  end

  @doc """
  Returns the unread message count for a user.
  """
  def user_unread_count(user_id) do
    mailbox = get_user_mailbox(user_id)

    if mailbox do
      unread_count(mailbox.id)
    else
      0
    end
  end

  @doc """
  Returns the unread message count for a mailbox.
  """
  def unread_count(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, read: false)
    |> Repo.aggregate(:count)
  end

  #
  # Temporary Mailbox Functions
  #

  @doc """
  Gets or creates a temporary mailbox for a user.
  If the user already has an active temporary mailbox, it updates the expiration time.
  """
  def get_or_create_user_temporary_mailbox(user_id, expires_in_hours \\ 24, domain \\ nil) do
    # Check if user already has an active temporary mailbox
    existing = TemporaryMailbox
               |> where([m], m.user_id == ^user_id)
               |> where([m], m.expires_at > ^DateTime.utc_now())
               |> Repo.one()

    capped_hours = min(expires_in_hours, 720)
    expires_at = DateTime.utc_now() |> DateTime.add(capped_hours * 60 * 60, :second)

    case existing do
      nil ->
        # Create new temporary mailbox for user
        create_user_temporary_mailbox(user_id, expires_at, domain)
      
      mailbox ->
        # Update expiration time of existing mailbox
        mailbox
        |> TemporaryMailbox.changeset(%{expires_at: expires_at})
        |> Repo.update()
    end
  end

  @doc """
  Gets a user's active temporary mailbox.
  """
  def get_user_temporary_mailbox(user_id) do
    TemporaryMailbox
    |> where([m], m.user_id == ^user_id)
    |> where([m], m.expires_at > ^DateTime.utc_now())
    |> Repo.one()
  end

  @doc """
  Resets (deletes) a user's temporary mailbox.
  """
  def reset_user_temporary_mailbox(user_id) do
    TemporaryMailbox
    |> where([m], m.user_id == ^user_id)
    |> Repo.delete_all()
    
    :ok
  end

  @doc """
  Creates a new temporary mailbox with a random email address.
  The mailbox will expire after the specified duration (default: 24 hours, max: 30 days).
  Optionally accepts a domain override for multi-domain support.
  """
  def create_temporary_mailbox(expires_in_hours \\ 24, domain \\ nil) do
    # Enforce maximum duration of 30 days (720 hours)
    capped_hours = min(expires_in_hours, 720)

    # Set expiration time
    expires_at = DateTime.utc_now() |> DateTime.add(capped_hours * 60 * 60, :second)

    # Retry creation with unique email/token if there are conflicts
    create_temporary_mailbox_with_retry(expires_at, domain, 0)
  end

  defp create_user_temporary_mailbox(user_id, expires_at, domain) do
    create_user_temporary_mailbox_with_retry(user_id, expires_at, domain, 0)
  end

  defp create_user_temporary_mailbox_with_retry(user_id, expires_at, domain, attempts) when attempts < 10 do
    email = TemporaryMailbox.generate_email(domain)
    token = TemporaryMailbox.generate_token()

    case %TemporaryMailbox{}
         |> TemporaryMailbox.changeset(%{
           email: email,
           token: token,
           expires_at: expires_at,
           user_id: user_id
         })
         |> Repo.insert() do
      {:ok, mailbox} ->
        {:ok, mailbox}

      {:error, %Ecto.Changeset{errors: errors}} ->
        has_unique_error =
          Enum.any?(errors, fn {field, {_, opts}} ->
            field in [:email, :token] and opts[:constraint] == :unique
          end)

        if has_unique_error do
          create_user_temporary_mailbox_with_retry(user_id, expires_at, domain, attempts + 1)
        else
          {:error, %Ecto.Changeset{errors: errors}}
        end
    end
  end

  defp create_user_temporary_mailbox_with_retry(_user_id, _expires_at, _domain, _attempts) do
    {:error, "Failed to create unique temporary mailbox after 10 attempts"}
  end

  defp create_temporary_mailbox_with_retry(expires_at, domain, attempts) when attempts < 10 do
    # Generate a random email and token
    email = TemporaryMailbox.generate_email(domain)
    token = TemporaryMailbox.generate_token()

    # Create the temporary mailbox
    case %TemporaryMailbox{}
         |> TemporaryMailbox.changeset(%{
           email: email,
           token: token,
           expires_at: expires_at
         })
         |> Repo.insert() do
      {:ok, mailbox} ->
        {:ok, mailbox}

      {:error, %Ecto.Changeset{errors: errors}} ->
        # Check if error is due to unique constraint violation
        has_unique_error =
          Enum.any?(errors, fn {field, {_, opts}} ->
            field in [:email, :token] and opts[:constraint] == :unique
          end)

        if has_unique_error do
          # Retry with new email/token
          create_temporary_mailbox_with_retry(expires_at, domain, attempts + 1)
        else
          # Other error, return it
          {:error, %Ecto.Changeset{errors: errors}}
        end
    end
  end

  defp create_temporary_mailbox_with_retry(_expires_at, _domain, _attempts) do
    {:error, "Failed to create unique temporary mailbox after 10 attempts"}
  end

  @doc """
  Creates a new temporary mailbox with duration specified in days.
  Maximum duration is 30 days.
  """
  def create_temporary_mailbox_days(expires_in_days \\ 1, domain \\ nil) do
    # Convert days to hours and cap at 30 days
    hours = min(expires_in_days * 24, 720)
    create_temporary_mailbox(hours, domain)
  end

  @doc """
  Gets a temporary mailbox by its token.
  Returns nil if the mailbox does not exist or has expired.
  """
  def get_temporary_mailbox_by_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    TemporaryMailbox
    |> where([m], m.token == ^token and m.expires_at > ^now)
    |> Repo.one()
  end

  @doc """
  Gets a temporary mailbox by its email address.
  Returns nil if the mailbox does not exist or has expired.
  """
  def get_temporary_mailbox_by_email(email) when is_binary(email) do
    now = DateTime.utc_now()

    # First try exact match
    result =
      TemporaryMailbox
      |> where([m], m.email == ^email and m.expires_at > ^now)
      |> Repo.one()

    # If not found, try case-insensitive match
    if is_nil(result) do
      TemporaryMailbox
      |> where(
        [m],
        fragment("lower(?)", m.email) == ^String.downcase(email) and m.expires_at > ^now
      )
      |> Repo.one()
    else
      result
    end
  end

  @doc """
  Lists all messages for a temporary mailbox identified by its token.
  Returns an empty list if the mailbox does not exist or has expired.
  """
  def list_temporary_mailbox_messages(token, limit \\ 50, offset \\ 0) do
    case get_temporary_mailbox_by_token(token) do
      nil -> []
      mailbox -> list_messages(mailbox.id, limit, offset)
    end
  end

  @doc """
  Extends the expiration time of a temporary mailbox.
  Maximum total lifetime is 30 days from creation.
  """
  def extend_temporary_mailbox(mailbox_id, additional_hours \\ 24) do
    mailbox = Repo.get(TemporaryMailbox, mailbox_id)

    if mailbox do
      # Calculate proposed new expiration time
      proposed_expires_at =
        DateTime.utc_now() |> DateTime.add(additional_hours * 60 * 60, :second)

      # Calculate maximum allowed expiration (30 days from creation)
      max_expires_at = mailbox.inserted_at |> DateTime.add(720 * 60 * 60, :second)

      # Use the earlier of the two dates to respect the 30-day maximum
      new_expires_at =
        case DateTime.compare(proposed_expires_at, max_expires_at) do
          :gt -> max_expires_at
          _ -> proposed_expires_at
        end

      # Update the mailbox
      mailbox
      |> TemporaryMailbox.changeset(%{expires_at: new_expires_at})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Deletes expired temporary mailboxes.
  """
  def cleanup_expired_temporary_mailboxes do
    now = DateTime.utc_now()

    {count, _} =
      TemporaryMailbox
      |> where([m], m.expires_at <= ^now)
      |> Repo.delete_all()

    {:ok, count}
  end

  #
  # Hey.com Features
  #

  @doc """
  Returns messages pending approval in The Screener.
  """
  def list_screener_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    # Get list of rejected senders
    rejected_emails = RejectedSender
                     |> where(mailbox_id: ^mailbox_id)
                     |> select([r], r.email_address)
                     |> Repo.all()

    query = Message
            |> where(mailbox_id: ^mailbox_id, screener_status: "pending")
            |> where([m], not m.spam and not m.archived)
            |> order_by(desc: :inserted_at)
            |> limit(^limit)
            |> offset(^offset)

    # Exclude messages from rejected senders if any exist
    query = if length(rejected_emails) > 0 do
      where(query, [m], m.from not in ^rejected_emails)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Returns paginated screener messages for a mailbox with metadata.
  """
  def list_screener_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, screener_status: "pending")
      |> where([m], not m.spam and not m.archived)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_screener_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns messages in The Feed (newsletters, notifications).
  """
  def list_feed_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, category: "feed")
    |> where([m], not m.spam and not m.archived)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns paginated feed messages for a mailbox with metadata.
  """
  def list_feed_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, category: "feed")
      |> where([m], not m.spam and not m.archived)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_feed_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns messages in Paper Trail (receipts, confirmations).
  """
  def list_paper_trail_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, category: "paper_trail")
    |> where([m], not m.spam and not m.archived)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns paginated paper trail messages for a mailbox with metadata.
  """
  def list_paper_trail_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, category: "paper_trail")
      |> where([m], not m.spam and not m.archived)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_paper_trail_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns messages that are set aside.
  """
  def list_set_aside_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id, category: "set_aside")
    |> where([m], not is_nil(m.set_aside_at))
    |> where([m], not m.spam and not m.archived)
    |> order_by(desc: :set_aside_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns paginated set aside messages for a mailbox with metadata.
  """
  def list_set_aside_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id, category: "set_aside")
      |> where([m], not is_nil(m.set_aside_at))
      |> where([m], not m.spam and not m.archived)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_set_aside_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns messages marked for reply later.
  """
  def list_reply_later_messages(mailbox_id, limit \\ 50, offset \\ 0) do
    Message
    |> where(mailbox_id: ^mailbox_id)
    |> where([m], not is_nil(m.reply_later_at))
    |> where([m], not m.spam and not m.archived)
    |> order_by(:reply_later_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns paginated reply later messages for a mailbox with metadata.
  """
  def list_reply_later_messages_paginated(mailbox_id, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Get total count
    total_count =
      Message
      |> where(mailbox_id: ^mailbox_id)
      |> where([m], not is_nil(m.reply_later_at))
      |> where([m], not m.spam and not m.archived)
      |> Repo.aggregate(:count)

    # Get messages for current page
    messages = list_reply_later_messages(mailbox_id, per_page, offset)

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Returns all inbox messages for a mailbox without pagination.
  Used for bulk operations.
  """
  def list_all_inbox_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, spam: false, archived: false)
    |> where([m], m.status != "sent" or is_nil(m.status))
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all screener messages (new contacts) for a mailbox without pagination.
  """
  def list_all_screener_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, screener: true)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all feed messages (bulk mail) for a mailbox without pagination.
  """
  def list_all_feed_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, feed: true)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all paper trail messages for a mailbox without pagination.
  """
  def list_all_paper_trail_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, is_receipt: true)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all set aside messages for a mailbox without pagination.
  """
  def list_all_set_aside_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, set_aside: true)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all reply later messages for a mailbox without pagination.
  """
  def list_all_reply_later_messages(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id)
    |> where([m], not is_nil(m.reply_later_at))
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Searches messages in a mailbox.
  Supports searching in from, to, cc, subject, and body content.
  Returns paginated results with metadata.
  """
  def search_messages(mailbox_id, query, page \\ 1, per_page \\ 20) do
    page = max(page, 1)
    offset = (page - 1) * per_page

    # Split query into terms for better matching
    search_terms = String.split(String.trim(query), " ")

    # Build search query
    base_query =
      Message
      |> where(mailbox_id: ^mailbox_id)
      |> where([m], not m.spam and not m.archived)

    # Apply search filters - search across multiple fields
    search_query =
      Enum.reduce(search_terms, base_query, fn term, acc_query ->
        search_term = "%#{String.downcase(term)}%"

        where(
          acc_query,
          [m],
          ilike(fragment("LOWER(?)", m.from), ^search_term) or
            ilike(fragment("LOWER(?)", m.to), ^search_term) or
            ilike(fragment("LOWER(?)", m.cc), ^search_term) or
            ilike(fragment("LOWER(?)", m.subject), ^search_term) or
            ilike(fragment("LOWER(?)", m.text_body), ^search_term) or
            ilike(fragment("LOWER(?)", m.html_body), ^search_term)
        )
      end)

    # Get total count
    total_count = search_query |> Repo.aggregate(:count)

    # Get messages for current page
    messages =
      search_query
      |> order_by(desc: :inserted_at)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Calculate pagination metadata
    total_pages = ceil(total_count / per_page)
    has_next = page < total_pages
    has_prev = page > 1

    %{
      messages: messages,
      query: query,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev
    }
  end

  @doc """
  Approves a sender in The Screener.
  """
  def approve_sender(%Message{} = message) do
    result =
      message
      |> Message.approve_sender_changeset()
      |> Repo.update()

    case result do
      {:ok, updated_message} ->
        # Add sender to approved list
        create_approved_sender(%{
          email_address: updated_message.from,
          mailbox_id: updated_message.mailbox_id,
          approved_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        {:ok, updated_message}

      error ->
        error
    end
  end

  @doc """
  Rejects a sender in The Screener.
  """
  def reject_sender(%Message{} = message) do
    # First update the message
    with {:ok, updated_message} <- message |> Message.reject_sender_changeset() |> Repo.update(),
         # Then add to rejected senders list
         {:ok, _rejected_sender} <- create_or_update_rejected_sender(message.from, message.mailbox_id) do
      {:ok, updated_message}
    end
  end

  @doc """
  Sets aside a message for later processing.
  """
  def set_aside_message(%Message{} = message, reason \\ nil) do
    message
    |> Message.set_aside_changeset(%{set_aside_reason: reason})
    |> Repo.update()
  end

  @doc """
  Removes a message from set aside.
  """
  def unset_aside_message(%Message{} = message) do
    message
    |> Message.unset_aside_changeset()
    |> Repo.update()
  end

  @doc """
  Sets a message for reply later.
  """
  def reply_later_message(%Message{} = message, reply_at, reminder \\ false) do
    message
    |> Message.reply_later_changeset(%{
      reply_later_at: reply_at,
      reply_later_reminder: reminder
    })
    |> Repo.update()
  end

  @doc """
  Clears reply later for a message.
  """
  def clear_reply_later(%Message{} = message) do
    message
    |> Message.clear_reply_later_changeset()
    |> Repo.update()
  end

  @doc """
  Tracks when a message is opened.
  """
  def track_message_open(%Message{} = message) do
    message
    |> Message.track_open_changeset()
    |> Repo.update()
  end

  @doc """
  Checks if a sender is approved for a mailbox.
  """
  def sender_approved?(email_address, mailbox_id) do
    ApprovedSender
    |> where(email_address: ^email_address, mailbox_id: ^mailbox_id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a sender is rejected for a mailbox.
  """
  def sender_rejected?(email_address, mailbox_id) do
    RejectedSender
    |> where(email_address: ^email_address, mailbox_id: ^mailbox_id)
    |> Repo.exists?()
  end

  @doc """
  Creates an approved sender.
  """
  def create_approved_sender(attrs \\ %{}) do
    %ApprovedSender{}
    |> ApprovedSender.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all approved senders for a mailbox.
  """
  def list_approved_senders(mailbox_id) do
    ApprovedSender
    |> where(mailbox_id: ^mailbox_id)
    |> order_by(desc: :approved_at)
    |> Repo.all()
  end

  @doc """
  Gets a single approved sender.
  """
  def get_approved_sender(id), do: Repo.get(ApprovedSender, id)

  @doc """
  Deletes an approved sender.
  """
  def delete_approved_sender(%ApprovedSender{} = approved_sender) do
    Repo.delete(approved_sender)
  end

  @doc """
  Updates an approved sender.
  """
  def update_approved_sender(%ApprovedSender{} = approved_sender, attrs) do
    approved_sender
    |> ApprovedSender.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates tracking for an approved sender when they send an email.
  """
  def track_approved_sender_email(email_address, mailbox_id) do
    case Repo.get_by(ApprovedSender, email_address: email_address, mailbox_id: mailbox_id) do
      # Sender not approved, nothing to track
      nil ->
        :ok

      sender ->
        sender
        |> ApprovedSender.track_email_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Creates or updates a rejected sender record.
  """
  def create_or_update_rejected_sender(email_address, mailbox_id) do
    case Repo.get_by(RejectedSender, email_address: email_address, mailbox_id: mailbox_id) do
      nil ->
        # Create new rejected sender
        %RejectedSender{}
        |> RejectedSender.changeset(%{
          email_address: email_address,
          mailbox_id: mailbox_id,
          rejected_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      rejected_sender ->
        # Update existing rejected sender
        rejected_sender
        |> RejectedSender.track_rejection_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Lists all blocked/rejected senders for a mailbox.
  Returns unique senders who have been rejected in the screener.
  """
  def list_blocked_senders(mailbox_id) do
    Message
    |> where(mailbox_id: ^mailbox_id, screener_status: "rejected")
    |> group_by(:from)
    |> select([m], %{
      email_address: m.from,
      rejected_at: max(m.updated_at),
      message_count: count(m.id)
    })
    |> order_by([m], desc: max(m.updated_at))
    |> Repo.all()
  end

  @doc """
  Blocks a sender by rejecting all their messages and marking them as blocked.
  """
  def block_sender(email_address, mailbox_id) do
    # First, reject any pending messages from this sender
    Message
    |> where(mailbox_id: ^mailbox_id, from: ^email_address, screener_status: "pending")
    |> Repo.update_all(set: [screener_status: "rejected", updated_at: DateTime.utc_now()])

    # Mark all future messages from this sender as spam
    Message
    |> where(mailbox_id: ^mailbox_id, from: ^email_address)
    |> Repo.update_all(set: [spam: true, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Unblocks a sender by removing their rejected status and allowing their messages.
  """
  def unblock_sender(email_address, mailbox_id) do
    # Reset rejected messages to pending for re-screening
    Message
    |> where(mailbox_id: ^mailbox_id, from: ^email_address, screener_status: "rejected")
    |> Repo.update_all(
      set: [screener_status: "pending", spam: false, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  @doc """
  Categorizes an incoming message based on content analysis.
  """
  def categorize_message(message_attrs) do
    subject = String.downcase(message_attrs["subject"] || "")
    from = String.downcase(message_attrs["from"] || "")
    body = String.downcase(message_attrs["text_body"] || "")
    html_body = String.downcase(message_attrs["html_body"] || "")

    # Combine text and HTML body for analysis
    combined_body = "#{body} #{html_body}"

    cond do
      # Receipt detection
      receipt_keywords?(subject, combined_body) ->
        Map.merge(message_attrs, %{
          "category" => "paper_trail",
          "is_receipt" => true
        })

      # Newsletter detection  
      newsletter_keywords?(subject, from, combined_body) ->
        Map.merge(message_attrs, %{
          "category" => "feed",
          "is_newsletter" => true
        })

      # Notification detection
      notification_keywords?(subject, from, combined_body) ->
        Map.merge(message_attrs, %{
          "category" => "feed",
          "is_notification" => true
        })

      # Additional automated message detection
      automated_message?(subject, from, combined_body) ->
        Map.merge(message_attrs, %{
          "category" => "feed",
          "is_notification" => true
        })

      true ->
        message_attrs
    end
  end

  # Private helper functions for categorization
  defp receipt_keywords?(subject, body) do
    receipt_terms = [
      "receipt",
      "invoice",
      "payment",
      "confirmation",
      "order",
      "purchase",
      "transaction",
      "billing",
      "refund",
      "shipping"
    ]

    Enum.any?(receipt_terms, fn term ->
      String.contains?(subject, term) or String.contains?(body, term)
    end)
  end

  defp newsletter_keywords?(subject, from, body) do
    newsletter_terms = [
      "newsletter",
      "unsubscribe",
      "weekly",
      "monthly",
      "digest",
      "news",
      "update",
      "announcement",
      "bulletin",
      "briefing",
      "roundup",
      "daily",
      "summary",
      "edition",
      "issues",
      "subscribe",
      "mailing list",
      "manage your subscription",
      "view in browser",
      "click here to unsubscribe",
      "promotional",
      "marketing",
      "campaign",
      "deal",
      "offer",
      "sale",
      "discount",
      "special offer"
    ]

    newsletter_domains = [
      "newsletter",
      "news",
      "updates",
      "marketing",
      "promo",
      "campaign",
      "mail",
      "email",
      "bulk",
      "broadcast",
      "list",
      "digest",
      "marketing",
      "deals",
      "offers",
      "sales"
    ]

    has_newsletter_terms =
      Enum.any?(newsletter_terms, fn term ->
        String.contains?(subject, term) or String.contains?(body, term)
      end)

    has_newsletter_domain =
      Enum.any?(newsletter_domains, fn domain ->
        String.contains?(from, domain)
      end)

    has_newsletter_terms or has_newsletter_domain
  end

  defp notification_keywords?(subject, from, body) do
    notification_terms = [
      "notification",
      "alert",
      "reminder",
      "notice",
      "security",
      "login",
      "password",
      "reset",
      "account",
      "verify",
      "welcome",
      "password reset",
      "forgot password",
      "reset password",
      "verification",
      "activate",
      "activation",
      "confirm",
      "confirmation",
      "important",
      "urgent",
      "action required",
      "please verify",
      "click to verify",
      "automated",
      "automatic",
      "system generated",
      "do not reply",
      "support",
      "help",
      "service",
      "update",
      "change",
      "new device",
      "new location",
      "signin",
      "sign in",
      "login attempt",
      "suspicious activity",
      "2fa",
      "two factor",
      "code",
      "otp",
      "token"
    ]

    notification_domains = [
      "no-reply",
      "noreply",
      "notification",
      "alert",
      "system",
      "security",
      "auth",
      "account",
      "support",
      "help",
      "service",
      "admin",
      "automated",
      "auto",
      "bot",
      "daemon",
      "robot",
      "notifications",
      "alerts",
      "updates",
      "info",
      "donotreply",
      "do-not-reply"
    ]

    has_notification_terms =
      Enum.any?(notification_terms, fn term ->
        String.contains?(subject, term) or String.contains?(body, term)
      end)

    has_notification_domain =
      Enum.any?(notification_domains, fn domain ->
        String.contains?(from, domain)
      end)

    has_notification_terms or has_notification_domain
  end

  defp automated_message?(subject, from, body) do
    # Additional patterns for automated messages that might not be caught by notifications
    automated_patterns = [
      # Common automated senders
      "github.com",
      "gitlab.com", 
      "atlassian.com",
      "slack.com",
      "discord.com",
      "linkedin.com",
      "twitter.com",
      "facebook.com",
      "instagram.com",
      "youtube.com",
      "medium.com",
      "substack.com",
      "mailchimp.com",
      "constantcontact.com",
      "sendgrid.com",
      "mailgun.com",
      
      # Social media patterns
      "mentioned you",
      "tagged you",
      "liked your",
      "commented on",
      "shared your",
      "followed you",
      "friend request",
      "connection request",
      
      # Automated service patterns
      "backup completed",
      "deployment",
      "build failed",
      "build successful",
      "server alert",
      "monitoring",
      "log alert",
      "status update",
      "maintenance",
      "downtime",
      "uptime",
      
      # Subscription/service updates
      "subscription",
      "renewal",
      "expired",
      "trial ending",
      "upgrade",
      "plan change",
      "billing cycle",
      
      # E-commerce patterns
      "shipped",
      "delivered",
      "tracking",
      "order status",
      "return",
      "refund processed",
      "wishlist",
      "cart reminder",
      "price drop",
      "back in stock"
    ]
    
    # Check if sender domain or message content matches automated patterns
    Enum.any?(automated_patterns, fn pattern ->
      String.contains?(from, pattern) or 
      String.contains?(subject, pattern) or 
      String.contains?(body, pattern)
    end) or
    # Check for no-reply patterns that might not be caught by notification detection
    String.contains?(from, "@") and (
      String.starts_with?(from, "no-reply") or
      String.starts_with?(from, "noreply") or
      String.starts_with?(from, "donotreply") or
      String.starts_with?(from, "do-not-reply") or
      String.starts_with?(from, "automated") or
      String.starts_with?(from, "auto-") or
      String.starts_with?(from, "bot@") or
      String.starts_with?(from, "robot@")
    )
  end

  @doc """
  Re-categorizes existing messages in a mailbox based on current categorization rules.
  Useful for applying updated categorization logic to existing messages.
  """
  def recategorize_messages(mailbox_id) do
    messages =
      Message
      |> where(mailbox_id: ^mailbox_id)
      |> where([m], not m.spam)
      |> Repo.all()

    processed = length(messages)
    
    changed = Enum.count(messages, fn message ->
      # Create attrs map similar to what's used during message creation
      message_attrs = %{
        "subject" => message.subject || "",
        "from" => message.from || "",
        "text_body" => message.text_body || "",
        "html_body" => message.html_body || ""
      }

      # Apply categorization
      categorized_attrs = categorize_message(message_attrs)

      # Check if anything would change
      would_change_category = categorized_attrs["category"] != message.category
      would_change_receipt = Map.get(categorized_attrs, "is_receipt", false) != message.is_receipt
      would_change_newsletter = Map.get(categorized_attrs, "is_newsletter", false) != message.is_newsletter
      would_change_notification = Map.get(categorized_attrs, "is_notification", false) != message.is_notification

      if would_change_category or would_change_receipt or would_change_newsletter or would_change_notification do
        # Extract only the categorization fields
        update_attrs =
          %{}
          |> maybe_put(:category, categorized_attrs["category"])
          |> maybe_put(:is_receipt, categorized_attrs["is_receipt"])
          |> maybe_put(:is_newsletter, categorized_attrs["is_newsletter"])
          |> maybe_put(:is_notification, categorized_attrs["is_notification"])

        # Update the message
        message
        |> Message.changeset(update_attrs)
        |> Repo.update()
        
        true
      else
        false
      end
    end)

    {processed, changed}
  end

  # Helper function to conditionally put values in a map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  ## Email Aliases

  @doc """
  Returns the list of email aliases for a user.
  """
  def list_aliases(user_id) do
    Alias
    |> where(user_id: ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single alias by ID for a specific user.
  """
  def get_alias(id, user_id) do
    Alias
    |> where(id: ^id, user_id: ^user_id)
    |> Repo.one()
  end

  @doc """
  Gets an alias by alias email address.
  """
  def get_alias_by_email(alias_email) do
    Alias
    |> where(alias_email: ^alias_email, enabled: true)
    |> Repo.one()
  end

  @doc """
  Creates an email alias.
  """
  def create_alias(attrs \\ %{}) do
    %Alias{}
    |> Alias.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an email alias.
  """
  def update_alias(%Alias{} = alias, attrs) do
    alias
    |> Alias.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an email alias.
  """
  def delete_alias(%Alias{} = alias) do
    Repo.delete(alias)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking alias changes.
  """
  def change_alias(%Alias{} = alias, attrs \\ %{}) do
    Alias.changeset(alias, attrs)
  end

  @doc """
  Checks if an email address is an alias and returns the target email.
  Returns nil if not an alias or if alias has no forwarding target.
  Returns :no_forward if alias exists but should deliver to main mailbox.
  """
  def resolve_alias(email) do
    case get_alias_by_email(email) do
      %Alias{target_email: target_email} when is_binary(target_email) and target_email != "" ->
        target_email

      %Alias{target_email: target_email} when is_nil(target_email) or target_email == "" ->
        :no_forward

      nil ->
        nil
    end
  end

  ## Mailbox Forwarding

  @doc """
  Updates mailbox forwarding settings.
  """
  def update_mailbox_forwarding(%Mailbox{} = mailbox, attrs) do
    mailbox
    |> Mailbox.forwarding_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking mailbox forwarding changes.
  """
  def change_mailbox_forwarding(%Mailbox{} = mailbox, attrs \\ %{}) do
    Mailbox.forwarding_changeset(mailbox, attrs)
  end

  @doc """
  Checks if a mailbox has forwarding enabled and returns the target email.
  Returns nil if forwarding is disabled or not configured.
  """
  def get_mailbox_forward_target(%Mailbox{forward_enabled: true, forward_to: target})
      when is_binary(target) do
    target
  end

  def get_mailbox_forward_target(_mailbox), do: nil
end
