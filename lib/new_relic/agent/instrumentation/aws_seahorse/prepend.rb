# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSeahorse::Prepend
    include NewRelic::Agent::Instrumentation::AwsSeahorse

    def build_request(*args)
      puts "........."
      build_request_with_new_relic(*args) { super }
    end

    def initialize(*args)
      initialize_with_new_relic(*args) { super }
    end
  end
end
