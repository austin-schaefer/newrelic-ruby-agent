# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/active_record_helper'

class ActiveRecordTest < Performance::TestCase
  NAME = 'Model Load'
  SQL = 'SELECT * FROM star'
  ADAPTER = 'mysql2'
  ITERATIONS = 100_000

  def test_helper_by_name
    measure(ITERATIONS) do
      NewRelic::Agent::Instrumentation::ActiveRecordHelper.product_operation_collection_for(NAME, SQL, ADAPTER)
    end
  end

  UNKNOWN_NAME = 'Blah'

  def test_helper_by_sql
    measure(ITERATIONS) do
      NewRelic::Agent::Instrumentation::ActiveRecordHelper.product_operation_collection_for(UNKNOWN_NAME, SQL, ADAPTER)
    end
  end
end
