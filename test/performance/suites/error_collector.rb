# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ErrorCollectorTests < Performance::TestCase
  ITERATIONS = 15_000

  def setup
    @txn_name = 'Controller/blogs/index'.freeze
    @err_msg = 'Sorry!'.freeze
  end

  def test_notice_error
    measure(ITERATIONS) do
      in_transaction(:name => @txn_name) do
        NewRelic::Agent.notice_error(StandardError.new(@err_msg))
      end
    end
  end

  def test_notice_error_with_custom_attributes
    opts = {:custom_params => {:name => 'Wes Mantooth', :channel => 9}}

    measure(ITERATIONS) do
      in_transaction(:name => @txn_name) do
        NewRelic::Agent.notice_error(StandardError.new(@err_msg), opts)
      end
    end
  end
end
