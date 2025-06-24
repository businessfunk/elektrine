defmodule ElektrineWeb.PageController do
  use ElektrineWeb, :controller

  alias Elektrine.Contact
  alias Elektrine.Contact.Message

  def home(conn, _params) do
    # Always skip layout for homepage to maintain fullscreen design
    render(conn, :home, layout: false)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def contact(conn, _params) do
    changeset = Message.changeset(%Message{}, %{})
    render(conn, :contact, changeset: changeset)
  end

  def send_message(conn, %{"message" => message_params}) do
    case Contact.send_message(message_params) do
      {:ok, _message} ->
        # Create a clean changeset for a new form
        changeset = Message.changeset(%Message{}, %{})

        conn
        |> put_flash(:info, "Thank you for your message! We'll get back to you soon.")
        |> render(:contact, changeset: changeset, success: true)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(
          :error,
          "There was a problem with your submission. Please check the form for errors."
        )
        |> render(:contact, changeset: changeset)
    end
  end
end
