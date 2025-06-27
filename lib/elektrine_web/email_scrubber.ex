defmodule ElektrineWeb.EmailScrubber do
  @moduledoc """
  HTML scrubber for email content that allows rich formatting while maintaining security.
  
  This scrubber is designed to handle modern HTML emails by preserving:
  - Background colors and images
  - Table-based layouts common in emails
  - Inline CSS styling
  - Images with proper attributes
  - Rich text formatting
  
  While blocking:
  - JavaScript and event handlers
  - Form elements
  - Dangerous protocols
  - Meta and script tags
  """

  require HtmlSanitizeEx.Scrubber.Meta
  alias HtmlSanitizeEx.Scrubber.Meta

  # Allow most common HTML tags used in emails
  Meta.remove_cdata_sections_before_scrub()
  Meta.strip_comments()

  # Allow common HTML elements with their attributes
  Meta.allow_tag_with_these_attributes("html", ["lang", "dir"])
  Meta.allow_tag_with_these_attributes("head", [])
  Meta.allow_tag_with_these_attributes("body", ["style", "class", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("div", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("span", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("p", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("hr", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("strong", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("b", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("em", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("i", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("u", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("s", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("strike", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("sub", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("sup", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("small", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("big", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("font", ["style", "class", "align", "bgcolor", "background", "face", "size", "color"])
  Meta.allow_tag_with_these_attributes("h1", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("h2", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("h3", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("h4", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("h5", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("h6", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("ul", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("ol", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("li", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("a", ["href", "title", "style", "class", "target"])
  Meta.allow_tag_with_these_attributes("img", [
    "src", "alt", "title", "width", "height", "style", "class",
    "border", "align", "hspace", "vspace"
  ])
  Meta.allow_tag_with_these_attributes("table", [
    "style", "class", "width", "height", "border", "cellpadding", "cellspacing",
    "align", "valign", "bgcolor", "background"
  ])
  Meta.allow_tag_with_these_attributes("tbody", ["style", "class", "align", "valign", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("thead", ["style", "class", "align", "valign", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("tfoot", ["style", "class", "align", "valign", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("tr", ["style", "class", "align", "valign", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("td", [
    "style", "class", "width", "height", "align", "valign", "bgcolor", "background",
    "border", "colspan", "rowspan", "nowrap"
  ])
  Meta.allow_tag_with_these_attributes("th", [
    "style", "class", "width", "height", "align", "valign", "bgcolor", "background",
    "border", "colspan", "rowspan", "nowrap", "scope"
  ])
  Meta.allow_tag_with_these_attributes("blockquote", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("pre", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("code", ["style", "class", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("center", ["style", "class", "align", "bgcolor", "background"])

  # Block dangerous protocols in href and src
  Meta.allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto"])
  Meta.allow_tag_with_uri_attributes("img", ["src"], ["http", "https", "data"])

  # Strip everything else
  Meta.strip_everything_not_covered()
end