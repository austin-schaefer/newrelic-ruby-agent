# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'aws_seahorse/instrumentation'
require_relative 'aws_seahorse/chain'
require_relative 'aws_seahorse/prepend'

DependencyDetection.defer do
  named :'aws_seahorse'

  depends_on do
    # The class that needs to be defined to prepend/chain onto. This can be used
    # to determine whether the library is installed.
    defined?(::Seahorse::Client::Base)
    # Add any additional requirements to verify whether this instrumentation
    # should be installed
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing aws_seahorse instrumentation')

    if use_prepend?
      # Seahorse::Client::Request
      classes = [
        ::Seahorse::Client::Base,
        ::Aws::BedrockRuntime::Client
      ]
      classes.each do |klass|
        prepend_instrument klass, NewRelic::Agent::Instrumentation::AwsSeahorse::Prepend

      end

      # prepend_instrument ::Seahorse::Client::Base, NewRelic::Agent::Instrumentation::AwsSeahorse::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::AwsSeahorse::Chain
    end
  end
end
