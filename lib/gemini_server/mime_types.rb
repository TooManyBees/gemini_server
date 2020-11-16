require "mime/types"

GEMINI_MIME_TYPE = MIME::Type.new({
  "content-type" => "text/gemini",
  "extensions" => ["gmi", "gemini"],
  "preferred-extension" => "gemini",
  "friendly" => "Gemtext"
})

MIME::Types.add(GEMINI_MIME_TYPE, :silent)
