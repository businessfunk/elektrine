defmodule ElektrineWeb.TemporaryMailboxHTML do
  use ElektrineWeb, :html

  embed_templates "temporary_mailbox_html/*"

  def format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  def truncate(text, max_length \\ 50) do
    if String.length(text || "") > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  def message_class(message) do
    if message.read do
      "hover:bg-base-200"
    else
      "bg-base-200 font-semibold hover:bg-base-300"
    end
  end
end
