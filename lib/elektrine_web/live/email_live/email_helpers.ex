defmodule ElektrineWeb.EmailLive.EmailHelpers do
  @moduledoc """
  Helper functions for working with emails in the LiveView components.
  """

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
      "hover:bg-base-200"
    else
      "bg-base-200 font-semibold hover:bg-base-300"
    end
  end
end