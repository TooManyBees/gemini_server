$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemini_server"

require "minitest/autorun"

Dir.chdir("test")
