require_relative 'lib/gemini_server/version'

Gem::Specification.new do |s|
  s.name = "gemini_server"
  s.version = GeminiServer::VERSION
  s.authors = ["Jess Bees"]
  s.email = ["hi@toomanybees.com"]

  s.summary = "Simple server for the Gemini protocol"
  s.description = ""
  s.homepage = "http://github.com/TooManyBees/gemini_server"
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage
  # s.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  s.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  s.require_paths = ["lib"]
  s.date = "2020-11-16"
  s.licenses = ["MIT".freeze]

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency("addressable", ["~> 2.7"])
    s.add_runtime_dependency("async-io", ["~> 1.30"])
    s.add_runtime_dependency("mime-types", ["~> 3.3"])
    s.add_runtime_dependency("mustermann", ["~> 1.1"])
    s.add_development_dependency("localhost", ["~> 1.1"])
  else
    s.add_dependency("addressable", ["~> 2.7"])
    s.add_dependency("async-io", ["~> 1.30"])
    s.add_dependency("mime-types", ["~> 3.3"])
    s.add_dependency("mustermann", ["~> 1.1"])
    s.add_dependency("localhost", ["~> 1.1"])
  end
end

