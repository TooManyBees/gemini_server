# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'juwelier'
Juwelier::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://guides.rubygems.org/specification-reference/ for more options
  gem.name = "gemini_server"
  gem.homepage = "http://github.com/TooManyBees/gemini_server"
  gem.license = "MIT"
  gem.summary = %Q{Simple server for the Gemini protocol}
  gem.description = %Q{}
  gem.email = "hi@toomanybees.com"
  gem.authors = ["Jess Bees"]
end
Juwelier::RubygemsDotOrgTasks.new
