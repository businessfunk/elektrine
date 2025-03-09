defmodule ElektrineWeb.Components.Logo do
  use Phoenix.Component

  @doc """
  Renders the Elektrine logo.

  ## Examples

      <.logo />
      <.logo variant="large" />
      <.logo variant="large" class="w-32 h-32 animate-float" />

  ## Options

    * `variant` - The size variant of the logo. Options: "small", "medium", "large". Default: "medium".
    * `class` - Additional CSS classes to apply to the logo container.
  """
  attr :variant, :string, default: "medium"
  attr :class, :string, default: ""

  def logo(assigns) do
    size_class = case assigns.variant do
      "small" -> "text-xl"
      "medium" -> "text-3xl"
      "large" -> "text-5xl"
      _ -> "text-3xl"
    end

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class={"flex items-center justify-center #{@class}"}>
      <div class={@size_class <> " text-theme-light font-bold transform -rotate-45 inline-block"}>E</div>
    </div>
    """
  end
end 