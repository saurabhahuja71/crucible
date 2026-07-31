# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "forge"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
