defmodule ElektrineWeb.EmailHTML do
  use ElektrineWeb, :html

  embed_templates "email_html/*"

  def format_date(datetime) do
    case datetime do
      %DateTime{} ->
        Calendar.strftime(datetime, "%b %d, %Y %H:%M")
      _ ->
        ""
    end
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
      "bg-white"
    else
      "bg-blue-50 font-semibold"
    end
  end
end