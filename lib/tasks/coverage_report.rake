# frozen_string_literal: true
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

namespace :coverage do
  desc "Collates all result sets generated by the different test runners"
  task :report do
    require 'simplecov'
    require 'fileutils'

    SimpleCov.coverage_dir('coverage_results')

    if ENV['CI']
      SimpleCov.collate(Dir['*/coverage_*/.resultset.json']) do
        formatter SimpleCov::Formatter::HTMLFormatter
        refuse_coverage_drop
      end
    else
      SimpleCov.collate(Dir['lib/coverage_*/.resultset.json']) do
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end

    Dir['lib/coverage_{[!r][!e][!s][!u][!l][!t][!s]}*'].each { |dir| FileUtils.rm_rf(dir) }
  end

  desc "Removes all coverage_* directories"
  task :clear do
    require 'fileutils'
    Dir["lib/coverage_*"].each { |dir| FileUtils.rm_rf(dir) }
  end
end
