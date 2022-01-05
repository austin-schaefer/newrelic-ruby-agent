# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'logger/instrumentation'
require_relative 'logger/chain'
require_relative 'logger/prepend'

DependencyDetection.defer do
  named :logger

  depends_on { defined?(::Logger) }

  executes do
    ::NewRelic::Agent.logger.info "Installing Logger instrumentation"
  end

  executes do
    if use_prepend?
      prepend_instrument ::Logger, NewRelic::Agent::Instrumentation::Logger::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Logger
    end
  end
end