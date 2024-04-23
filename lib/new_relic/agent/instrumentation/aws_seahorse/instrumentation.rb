# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSeahorse

    def build_request_with_new_relic(*args)
      # add instrumentation content here
      binding.irb
      puts "+" * 100
      puts "seahorse: #{self.class.name}#build_request"
      puts args
      access_key = config.credentials.access_key_id

      
      puts "+" * 100
      yield
    end

    def initialize_with_new_relic(*args)
      # add instrumentation content here
      puts "+" * 100
      puts "seahorse: #{self.class.name}#initialize"
      puts args
      puts "+" * 100
      yield
    end


# arn = Aws::ARN.new( partition: 'aws', service: 's3', region: 'us-west-2', account_id: '12345678910', resource: 'foo/bar' ) # => #

# arn:#{Partition}:#{Service}:#{Region}:#{Account}:#{resource}


# partition: is it always 'aws', or does it change
# service: dynamodb or whatever is being used
# region: can get from config?
# account: can get access key from config, so then we have this?
# resource: like table/tablename for dynamo db

# dynamodb:
# arn:${Partition}:dynamodb:${Region}:${Account}:table/${TableName}

  end
end
