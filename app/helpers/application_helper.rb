module ApplicationHelper
  # Render a JSON-LD <script> tag from a Ruby hash. Escapes the `</` sequence so
  # the inline JSON cannot prematurely close the surrounding <script> element.
  def jsonld_tag(data)
    json = JSON.generate(data).gsub("</", "<\\/")
    content_tag(:script, json.html_safe, type: "application/ld+json")
  end
end
