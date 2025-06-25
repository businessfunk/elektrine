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

  # Block dangerous tags completely
  Meta.strip_everything_not_covered()

  # Allow safe structural tags
  Meta.allow_tag_with_these_attributes("html", [])
  Meta.allow_tag_with_these_attributes("head", [])
  Meta.allow_tag_with_these_attributes("body", ["bgcolor", "background", "style", "class"])
  Meta.allow_tag_with_these_attributes("div", ["style", "class", "id", "align", "bgcolor", "background"])
  Meta.allow_tag_with_these_attributes("span", ["style", "class", "color"])
  Meta.allow_tag_with_these_attributes("p", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("br", [])
  Meta.allow_tag_with_these_attributes("hr", ["style", "class", "color", "size", "width"])

  # Allow text formatting tags
  Meta.allow_tag_with_these_attributes("strong", ["style", "class"])
  Meta.allow_tag_with_these_attributes("b", ["style", "class"])
  Meta.allow_tag_with_these_attributes("em", ["style", "class"])
  Meta.allow_tag_with_these_attributes("i", ["style", "class"])
  Meta.allow_tag_with_these_attributes("u", ["style", "class"])
  Meta.allow_tag_with_these_attributes("s", ["style", "class"])
  Meta.allow_tag_with_these_attributes("strike", ["style", "class"])
  Meta.allow_tag_with_these_attributes("sub", ["style", "class"])
  Meta.allow_tag_with_these_attributes("sup", ["style", "class"])
  Meta.allow_tag_with_these_attributes("small", ["style", "class"])
  Meta.allow_tag_with_these_attributes("big", ["style", "class"])
  Meta.allow_tag_with_these_attributes("font", ["style", "class", "color", "face", "size"])

  # Allow heading tags
  Meta.allow_tag_with_these_attributes("h1", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("h2", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("h3", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("h4", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("h5", ["style", "class", "align"])
  Meta.allow_tag_with_these_attributes("h6", ["style", "class", "align"])

  # Allow list tags
  Meta.allow_tag_with_these_attributes("ul", ["style", "class", "type"])
  Meta.allow_tag_with_these_attributes("ol", ["style", "class", "type", "start"])
  Meta.allow_tag_with_these_attributes("li", ["style", "class", "type", "value"])

  # Allow link tags (but scrub dangerous protocols)
  Meta.allow_tag_with_these_attributes("a", ["href", "title", "style", "class", "name", "target"])

  # Allow images with comprehensive attributes
  Meta.allow_tag_with_these_attributes("img", [
    "src", "alt", "title", "width", "height", "style", "class",
    "border", "align", "hspace", "vspace", "usemap", "ismap"
  ])

  # Allow table tags with full styling support
  Meta.allow_tag_with_these_attributes("table", [
    "style", "class", "width", "height", "border", "cellpadding", "cellspacing",
    "align", "valign", "bgcolor", "background", "bordercolor", "bordercolordark", "bordercolorlight"
  ])
  Meta.allow_tag_with_these_attributes("tbody", ["style", "class", "align", "valign"])
  Meta.allow_tag_with_these_attributes("thead", ["style", "class", "align", "valign"])
  Meta.allow_tag_with_these_attributes("tfoot", ["style", "class", "align", "valign"])
  Meta.allow_tag_with_these_attributes("tr", [
    "style", "class", "height", "align", "valign", "bgcolor", "background", "bordercolor"
  ])
  Meta.allow_tag_with_these_attributes("td", [
    "style", "class", "width", "height", "align", "valign", "bgcolor", "background",
    "border", "bordercolor", "colspan", "rowspan", "nowrap"
  ])
  Meta.allow_tag_with_these_attributes("th", [
    "style", "class", "width", "height", "align", "valign", "bgcolor", "background",
    "border", "bordercolor", "colspan", "rowspan", "nowrap", "scope"
  ])

  # Allow block quote and pre tags
  Meta.allow_tag_with_these_attributes("blockquote", ["style", "class", "cite"])
  Meta.allow_tag_with_these_attributes("pre", ["style", "class"])
  Meta.allow_tag_with_these_attributes("code", ["style", "class"])

  # Allow center tag (commonly used in emails)
  Meta.allow_tag_with_these_attributes("center", ["style", "class"])

  # Block dangerous protocols in href and src
  Meta.allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto"])
  Meta.allow_tag_with_uri_attributes("img", ["src"], ["http", "https", "data"])

end