defmodule ElektrineWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: ElektrineWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook="FlashMessage"
      role="alert"
      class={[
        "fixed bottom-4 left-4 w-80 sm:w-96 z-[9999] shadow-xl rounded-lg relative transition-opacity duration-200",
        @kind == :info && "alert alert-info",
        @kind == :error && "alert alert-error"
      ]}
      {@rest}
    >
      <!-- Progress bar -->
      <div class="absolute bottom-0 left-0 h-1 bg-white/30 w-full rounded-b-lg overflow-hidden">
        <div class="flash-progress h-full bg-white/60 w-full origin-left"></div>
      </div>

      <div class="flex items-center gap-3">
        <div :if={@kind == :info} class="flex-shrink-0">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            class="h-6 w-6 stroke-current"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            >
            </path>
          </svg>
        </div>
        <div :if={@kind == :error} class="flex-shrink-0">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            class="h-6 w-6 stroke-current"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
            >
            </path>
          </svg>
        </div>
        <div class="flex-grow">
          <h3 :if={@title} class="font-bold">{@title}</h3>
          <div class="text-sm">{msg}</div>
        </div>
        <button
          type="button"
          class="btn btn-sm btn-ghost btn-circle self-start"
          aria-label={gettext("close")}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="card bg-base-100 shadow-sm p-6">
        <div class="space-y-4">
          {render_slot(@inner_block, f)}
          <div :for={action <- @actions} class="mt-6">
            {render_slot(action, f)}
          </div>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "btn btn-primary phx-submit-loading:opacity-75",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-3">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="checkbox checkbox-primary"
          {@rest}
        />
        <span class="label-text">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="form-control w-full">
      <.label for={@id}>{@label}</.label>
      <select id={@id} name={@name} class="select select-bordered w-full" multiple={@multiple} {@rest}>
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="form-control w-full">
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "textarea textarea-bordered min-h-[6rem]",
          @errors == [] && "",
          @errors != [] && "textarea-error"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="form-control w-full">
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "input input-bordered w-full",
          @errors == [] && "",
          @errors != [] && "input-error"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="label">
      <span class="label-text">{render_slot(@inner_block)}</span>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="label">
      <span class="label-text-alt text-error flex items-center gap-1">
        <.icon name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {render_slot(@inner_block)}
      </span>
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ElektrineWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ElektrineWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Processes email HTML content, handling various encodings and cleaning up display issues.
  """
  def process_email_html(html_content) when is_binary(html_content) do
    html_content
    |> ensure_valid_utf8()
    |> decode_if_base64()
    |> decode_if_quoted_printable()
    |> ensure_valid_utf8()
    |> remove_css_before_html()
    |> clean_email_artifacts()
    |> String.trim()
  end

  def process_email_html(nil), do: nil

  # Simple aggressive CSS removal - removes everything before first HTML tag
  defp remove_css_before_html(content) do
    cond do
      # If it starts with Facebook@media, remove everything up to actual content
      String.starts_with?(content, "Facebook@media") ->
        # Find the first HTML tag
        case Regex.run(~r/(<[a-zA-Z][^>]*>.*)/s, content) do
          [_, html] -> html
          _ -> ""  # No HTML found, return empty
        end
      
      # If it starts with any CSS-like pattern, remove it
      String.starts_with?(content, "@media") or 
      String.starts_with?(content, ".") and String.contains?(String.slice(content, 0, 100), "{") ->
        case Regex.run(~r/(<[a-zA-Z][^>]*>.*)/s, content) do
          [_, html] -> html
          _ -> content
        end
      
      true ->
        content
    end
  end

  @doc """
  Cleans email artifacts like standalone CSS and MIME headers from email content.
  """
  def clean_email_artifacts(content) when is_binary(content) do
    content
    |> remove_facebook_css_text()
    |> remove_standalone_css()
    |> clean_mime_artifacts()
    |> normalize_whitespace()
  end

  def clean_email_artifacts(nil), do: nil

  # Specifically remove Facebook email CSS that appears as text
  defp remove_facebook_css_text(content) do
    # Remove ALL CSS that appears before actual content
    # This handles any CSS text that appears at the beginning
    
    # First, try to find where HTML content starts
    case Regex.run(~r/^(.*?)(<[a-zA-Z].*)/s, content) do
      [_, prefix, html_content] ->
        # Check if the prefix contains CSS-like patterns
        if contains_css_patterns?(prefix) do
          # Remove the CSS prefix entirely, keep only HTML
          html_content
        else
          # No CSS patterns, keep original content
          content
        end
      
      _ ->
        # No HTML found, check if entire content is CSS
        if contains_css_patterns?(content) and not String.contains?(content, "<") do
          # It's all CSS, remove it entirely
          ""
        else
          # Try to find any text after CSS blocks
          content
          |> remove_all_css_blocks()
        end
    end
  end
  
  # Check if content contains CSS patterns
  defp contains_css_patterns?(text) do
    String.contains?(text, "{") and String.contains?(text, "}") or
    String.contains?(text, "@media") or
    String.contains?(text, ".d_mb_") or
    String.contains?(text, ".mb_") or
    Regex.match?(~r/\.[a-zA-Z_-]+\s*\{/, text) or
    Regex.match?(~r/\*\[class\]/, text)
  end
  
  # Remove all CSS blocks from content
  defp remove_all_css_blocks(content) do
    content
    # Remove any CSS-like content before first real text
    |> String.replace(~r/^[^<>]*\{[^}]*\}[^<>]*/s, "")
    # Remove @media queries and their content
    |> String.replace(~r/@media[^{]*\{[^}]*\}/s, "")
    # Remove class selectors and their rules
    |> String.replace(~r/\.[a-zA-Z_-]+[^{]*\{[^}]*\}/s, "")
    # Remove any remaining CSS selectors
    |> String.replace(~r/[a-zA-Z0-9_\-\.\#\*\[\]]+\s*\{[^}]*\}/s, "")
    |> String.trim()
  end

  # Remove standalone CSS blocks that appear outside of proper HTML structure
  defp remove_standalone_css(content) do
    content
    # Remove the specific Facebook CSS pattern that appears as text
    |> String.replace(~r/Facebook@media all and \(max-width: 480px\)\{.*?\}[^<]*/s, "")
    # Remove general @media patterns
    |> String.replace(~r/^[^<]*@media[^{]*\{.*?\}[^<]*/s, "")
    # Remove CSS class definitions
    |> String.replace(~r/^[^<]*\.[a-zA-Z_][^{]*\{.*?\}[^<]*/s, "")
    # Remove orphaned CSS rules with selectors like *[class]
    |> String.replace(~r/^[^<]*\*\[[^]]*\][^{]*\{.*?\}[^<]*/s, "")
    # Remove any text that starts with CSS selectors and contains curly braces
    |> String.replace(~r/^[^<]*[a-zA-Z_\*\.\#\[].*?\{.*?\}[^<]*/s, "")
    # Remove multiple CSS blocks in sequence
    |> remove_sequential_css_blocks()
    # Remove CSS blocks that appear before HTML content
    |> remove_leading_css_blocks()
    |> String.trim()
  end

  # Remove multiple CSS blocks that appear in sequence
  defp remove_sequential_css_blocks(content) do
    # This handles cases where there are multiple @media or CSS rules in a row
    content
    |> String.replace(~r/@media[^{]*\{[^}]*\}\.d_mb_show\{[^}]*\}\.d_mb_flex\{[^}]*\}@media[^{]*\{[^}]*\}/s, "")
    |> String.replace(~r/\*\[class\][^{]*\{[^}]*\}(\*\[class\][^{]*\{[^}]*\})+/s, "")
  end

  # Remove CSS blocks that appear before any HTML content
  defp remove_leading_css_blocks(content) do
    # Split content to find where HTML actually starts
    case String.split(content, ~r/<[a-zA-Z]/, parts: 2) do
      [css_part, html_part] ->
        # If the first part contains CSS rules or CSS-like patterns, remove them
        if (String.contains?(css_part, "{") and String.contains?(css_part, "}")) or
           String.contains?(css_part, "@media") or
           String.contains?(css_part, "Facebook@media") or
           Regex.match?(~r/\*\[class\]/, css_part) do
          "<" <> html_part
        else
          content
        end
      
      [_] ->
        # No HTML tags found, check if it's all CSS-like content
        if (String.contains?(content, "{") and String.contains?(content, "}") and not String.contains?(content, "<")) or
           String.contains?(content, "Facebook@media") or
           (String.contains?(content, "@media") and not String.contains?(content, "<")) do
          ""
        else
          content
        end
    end
  end

  # Clean MIME artifacts and headers
  defp clean_mime_artifacts(content) do
    content
    # Remove MIME boundary markers
    |> String.replace(~r/^--[^\r\n]+[\r\n]*/m, "")
    # Remove Content-Type headers that might be mixed in
    |> String.replace(~r/Content-Type:[^\r\n]*[\r\n]*/i, "")
    |> String.replace(~r/Content-Transfer-Encoding:[^\r\n]*[\r\n]*/i, "")
    |> String.replace(~r/Content-Disposition:[^\r\n]*[\r\n]*/i, "")
    # Remove other common MIME headers
    |> String.replace(~r/^[A-Za-z-]+:\s*[^\r\n]*[\r\n]*/m, "")
    |> String.trim()
  end

  # Normalize whitespace and line breaks
  defp normalize_whitespace(content) do
    content
    |> String.replace(~r/\r\n|\r|\n/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  @doc """
  Safely processes and sanitizes email HTML content, with error handling for encoding issues.
  """
  def safe_sanitize_email_html(html_content) do
    try do
      html_content
      |> process_email_html()
      |> permissive_email_sanitize()
    rescue
      UnicodeConversionError ->
        # Fallback: return a safe error message
        "<p><em>Email content contains invalid encoding and cannot be displayed safely.</em></p>"
      ArgumentError ->
        # Fallback for other argument errors
        "<p><em>Email content could not be processed safely.</em></p>"
      _ ->
        # Fallback for any other errors
        "<p><em>Error processing email content.</em></p>"
    end
  end

  @doc """
  Permissive HTML sanitization that preserves styling while maintaining security.
  Allows background colors, images, tables, and most formatting for rich email display.
  """
  def permissive_email_sanitize(html_content) when is_binary(html_content) do
    # Don't process again - it's already processed by safe_sanitize_email_html
    # Try a much more permissive approach using our custom scrubber
    try do
      HtmlSanitizeEx.Scrubber.scrub(html_content, ElektrineWeb.EmailScrubber)
    rescue
      _ ->
        # If custom scrubber fails, fall back to basic_html but don't lose all content
        case HtmlSanitizeEx.basic_html(html_content) do
          "" -> 
            # If basic_html strips everything, try stripping only scripts/dangerous tags
            html_content
            |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
            |> String.replace(~r/<link[^>]*>/is, "")
            |> String.replace(~r/<meta[^>]*>/is, "")
            |> String.replace(~r/<form[^>]*>.*?<\/form>/is, "")
            |> String.replace(~r/javascript:/i, "")
            |> String.replace(~r/on\w+\s*=/i, "")
          result -> result
        end
    end
  end
  
  def permissive_email_sanitize(nil), do: nil

  @doc """
  Safely converts an email message to JSON, excluding associations and metadata.
  """
  def safe_message_to_json(message) do
    try do
      # Convert struct to map and clean up associations
      clean_map = message
      |> Map.from_struct()
      |> Map.drop([:__meta__, :mailbox, :user])  # Drop common associations
      |> sanitize_map_for_json()
      
      Jason.encode!(clean_map, pretty: true)
    rescue
      error ->
        # Fallback: create a simplified JSON representation
        fallback = %{
          error: "Could not serialize message to JSON: #{inspect(error)}",
          id: safe_get(message, :id),
          subject: safe_get(message, :subject),
          from: safe_get(message, :from),
          to: safe_get(message, :to),
          cc: safe_get(message, :cc),
          bcc: safe_get(message, :bcc),
          status: safe_get(message, :status),
          inserted_at: safe_get(message, :inserted_at) |> format_datetime_for_json()
        }
        
        Jason.encode!(fallback, pretty: true)
    end
  end
  
  # Helper to safely get values from maps/structs
  defp safe_get(data, key) do
    try do
      Map.get(data, key)
    rescue
      _ -> nil
    end
  end
  
  # Helper to sanitize map values for JSON encoding
  defp sanitize_map_for_json(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, sanitize_value_for_json(value))
    end)
  end
  
  # Helper to sanitize individual values for JSON
  defp sanitize_value_for_json(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize_value_for_json(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp sanitize_value_for_json(%Date{} = d), do: Date.to_iso8601(d)
  defp sanitize_value_for_json(%Time{} = t), do: Time.to_iso8601(t)
  defp sanitize_value_for_json(value) when is_map(value) do
    # For nested maps, recursively sanitize
    if Map.has_key?(value, :__struct__) do
      "#{inspect(value.__struct__)}"  # Just show the struct name
    else
      sanitize_map_for_json(value)
    end
  end
  defp sanitize_value_for_json(value), do: value
  
  # Helper to format DateTime for JSON safely
  defp format_datetime_for_json(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime_for_json(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_datetime_for_json(value), do: value

  @doc """
  Decodes email subject that may be RFC 2047 encoded.
  """
  def decode_email_subject(subject) when is_binary(subject) do
    # Pattern: =?charset?encoding?encoded-text?=
    subject
    |> ensure_valid_utf8()
    |> String.replace(~r/=\?([^?]+)\?([QqBb])\?([^?]*)\?=/, fn match ->
      case Regex.run(~r/=\?([^?]+)\?([QqBb])\?([^?]*)\?=/, match) do
        [_, _charset, encoding, encoded_text] ->
          decoded = case String.upcase(encoding) do
            "Q" ->
              decode_quoted_printable_simple(encoded_text |> String.replace("_", " "))

            "B" ->
              case Base.decode64(encoded_text) do
                {:ok, decoded} -> decoded
                :error -> match
              end

            _ ->
              match
          end
          # Ensure the decoded result is valid UTF-8
          ensure_valid_utf8(decoded)

        _ ->
          match
      end
    end)
    |> ensure_valid_utf8()
    |> String.trim()
  end

  def decode_email_subject(subject), do: subject

  # Simple quoted-printable decoding for subjects
  defp decode_quoted_printable_simple(content) when is_binary(content) do
    result = content
    # Remove soft line breaks
    |> String.replace(~r/=\r?\n/, "")
    |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn match ->
      hex = String.slice(match, 1, 2)

      case Integer.parse(hex, 16) do
        {value, ""} -> <<value>>
        _ -> match
      end
    end)
    
    # Ensure result is valid UTF-8
    ensure_valid_utf8(result)
  end

  # Try to decode content if it appears to be base64
  defp decode_if_base64(content) when is_binary(content) do
    # Check if content looks like base64 (only contains base64 chars and is reasonably long)
    if String.match?(content, ~r/^[A-Za-z0-9+\/=\s]+$/) and String.length(content) > 100 and
         rem(String.length(String.replace(content, ~r/\s/, "")), 4) == 0 do
      case Base.decode64(String.replace(content, ~r/\s/, "")) do
        {:ok, decoded} ->
          # Ensure decoded content is valid UTF-8
          decoded = ensure_valid_utf8(decoded)
          # Check if decoded content looks like HTML
          if String.contains?(decoded, "<") and String.contains?(decoded, ">") do
            decoded
          else
            content
          end

        :error ->
          content
      end
    else
      content
    end
  end

  defp decode_if_base64(content), do: content

  # Ensures the content is valid UTF-8, converting invalid sequences to replacement characters
  defp ensure_valid_utf8(content) when is_binary(content) do
    case String.valid?(content) do
      true -> 
        # Even if valid UTF-8, might have double-encoding issues
        fix_common_encoding_issues(content)
      false ->
        # Convert invalid UTF-8 to valid UTF-8 by replacing invalid sequences
        # This prevents UnicodeConversionError while preserving as much content as possible
        :unicode.characters_to_binary(content, :latin1, :utf8)
        |> case do
          result when is_binary(result) -> fix_common_encoding_issues(result)
          {:error, _valid, _rest} -> 
            # Fallback: try to scrub the content
            scrub_invalid_utf8(content)
          {:incomplete, _valid, _rest} ->
            # Fallback: try to scrub the content  
            scrub_invalid_utf8(content)
        end
    end
  end

  defp ensure_valid_utf8(content), do: content

  # Fix common UTF-8 encoding issues often seen in emails
  defp fix_common_encoding_issues(content) when is_binary(content) do
    content
    # Fix common double-encoded UTF-8 issues
    |> fix_encoding_patterns()
    # Fix some quoted-printable remnants that might have been missed
    |> String.replace("=\r\n", "")
    |> String.replace("=\n", "")
  end
  
  # Fix encoding patterns using binary matching to avoid source code issues
  defp fix_encoding_patterns(content) do
    content
    |> String.replace(~r/â€™/, "'")      # Smart single quote
    |> String.replace(~r/â€œ/, "\"")     # Smart double quote open
    |> String.replace(~r/â€/, "\"")      # Smart double quote close  
    |> String.replace(~r/â€"/, "-")      # En dash -> regular dash
    |> String.replace(~r/â€"/, "-")      # Em dash -> regular dash
    |> String.replace(~r/â€¦/, "...")    # Ellipsis
    |> String.replace(~r/Â©/, "©")       # Copyright
    |> String.replace(~r/Â®/, "®")       # Registered
    |> String.replace(~r/Â /, " ")       # Non-breaking space to regular space
    |> String.replace(~r/Â/, " ")        # Standalone Â to space
    |> String.replace(~r/â¯/, " ")       # Thin space variations
    |> String.replace(~r/â/, "-")        # Em dash variations
    |> String.replace(~r/â€ž/, "\"")     # German quote
  end

  # Fallback function to scrub invalid UTF-8 characters
  defp scrub_invalid_utf8(content) do
    content
    |> :binary.bin_to_list()
    |> Enum.map(fn byte ->
      # Replace bytes that would cause UTF-8 issues with space
      if byte < 32 and byte not in [9, 10, 13] do
        32  # space
      else
        byte
      end
    end)
    |> :binary.list_to_bin()
    |> then(fn result ->
      # If still invalid, use a more aggressive approach
      case String.valid?(result) do
        true -> result
        false -> 
          # Last resort: convert each byte to a safe representation
          for <<byte <- content>>, into: "", do: 
            if(byte >= 32 and byte <= 126, do: <<byte>>, else: "?")
      end
    end)
  end

  # Try to decode content if it appears to be quoted-printable
  defp decode_if_quoted_printable(content) when is_binary(content) do
    # Check if content looks like quoted-printable
    # Look for =XX hex patterns, soft line breaks (= at end of line), or common QP sequences
    has_hex_encoding = String.match?(content, ~r/=[0-9A-Fa-f]{2}/)
    has_soft_breaks = String.match?(content, ~r/=\r?\n/)
    has_common_qp = String.contains?(content, "=3D") or String.contains?(content, "=20") or 
                    String.contains?(content, "=E2=80") or String.contains?(content, "=C2=A0")
    
    # For emails, be more aggressive about QP detection
    has_email_qp_indicators = String.contains?(content, "href=3D") or 
                             String.contains?(content, "style=3D") or
                             String.contains?(content, "&amp;") or
                             String.contains?(content, "=\r\n") or
                             String.contains?(content, "=\n")
    
    if has_hex_encoding or has_soft_breaks or has_common_qp or has_email_qp_indicators do
      decode_quoted_printable_full(content)
    else
      content
    end
  end

  defp decode_if_quoted_printable(content), do: content

  # Full quoted-printable decoding for email bodies
  defp decode_quoted_printable_full(content) when is_binary(content) do
    result = content
    # Remove soft line breaks (= at end of line) - handle both CRLF and LF
    |> String.replace(~r/=\r?\n/, "")
    |> String.replace(~r/=\r/, "")
    # Decode =XX hex sequences
    |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn match ->
      hex = String.slice(match, 1, 2)
      case Integer.parse(hex, 16) do
        {value, ""} -> <<value>>
        _ -> match
      end
    end)
    # Handle any remaining = at end of lines that might have been missed
    |> String.replace(~r/=(?=\s*$)/m, "")
    
    # Ensure result is valid UTF-8
    ensure_valid_utf8(result)
  end
end
