# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../lib/new_relic/agent/instrumentation/rails_notifications/action_cable'

module NewRelic
  module Agent
    module Instrumentation
      class ActionCableSubscriberTest < Minitest::Test
        class TestConnection < ActionCable::Connection::Base; end

        class TestChannel < ActionCable::Channel::Base
          def do_it; end
        end

        def setup
          nr_freeze_process_time
          @subscriber = ActionCableSubscriber.new

          NewRelic::Agent.drop_buffered_data
          @stats_engine = NewRelic::Agent.instance.stats_engine
          @stats_engine.clear_stats
          NewRelic::Agent.manual_start
          NewRelic::Agent::Tracer.clear_state
        end

        def teardown
          NewRelic::Agent.shutdown
          @stats_engine.clear_stats
        end

        def test_creates_web_transaction
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)

          assert_predicate NewRelic::Agent::Tracer.current_transaction, :recording_web_transaction?
          advance_process_time(1.0)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          assert_equal('Controller/ActionCable/TestChannel/test_action',
            last_transaction_trace.transaction_name)
          assert_equal('Controller/ActionCable/TestChannel/test_action',
            last_transaction_trace.root_node.children[0].metric_name)
        end

        def test_records_apdex_metrics
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          advance_process_time(1.5)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          expected_values = {:apdex_f => 0, :apdex_t => 1, :apdex_s => 0}

          assert_metrics_recorded(
            'Apdex/ActionCable/TestChannel/test_action' => expected_values,
            'Apdex' => expected_values
          )
        end

        def test_sets_default_transaction_name_on_start
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)

          assert_equal 'Controller/ActionCable/TestChannel/test_action', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
        end

        def test_sets_default_transaction_keeps_name_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          txn = NewRelic::Agent::Transaction.tl_current
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          assert_equal 'Controller/ActionCable/TestChannel/test_action', txn.best_name
        end

        def test_sets_transaction_name
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          NewRelic::Agent.set_transaction_name('something/else')

          assert_equal 'Controller/ActionCable/something/else', NewRelic::Agent::Transaction.tl_current.best_name
        ensure
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)
        end

        def test_sets_transaction_name_holds_through_stop
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)
          txn = NewRelic::Agent::Transaction.tl_current
          NewRelic::Agent.set_transaction_name('something/else')
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          assert_equal 'Controller/ActionCable/something/else', txn.best_name
        end

        def test_creates_tt_node_for_transmit
          @subscriber.start('perform_action.action_cable', :id, payload_for_perform_action)

          assert_predicate NewRelic::Agent::Tracer.current_transaction, :recording_web_transaction?
          @subscriber.start('transmit.action_cable', :id, payload_for_transmit)
          advance_process_time(1.0)
          @subscriber.finish('transmit.action_cable', :id, payload_for_transmit)
          @subscriber.finish('perform_action.action_cable', :id, payload_for_perform_action)

          sample = last_transaction_trace

          assert_equal('Controller/ActionCable/TestChannel/test_action', sample.transaction_name)
          metric_name = 'Ruby/ActionCable/TestChannel/transmit'

          refute_nil(find_node_with_name(sample, metric_name), "Expected trace to have node with name: #{metric_name}")
        end

        def test_does_not_record_unscoped_metrics_nor_create_trace_for_transmit_outside_of_active_txn
          @subscriber.start('transmit.action_cable', :id, payload_for_transmit)
          advance_process_time(1.0)
          @subscriber.finish('transmit.action_cable', :id, payload_for_transmit)

          sample = last_transaction_trace

          assert_nil sample, 'Did not expect a transaction to be created for transmit'
          refute_metrics_recorded ['Ruby/ActionCable/TestChannel/transmit']
        end

        def test_does_not_record_unscoped_metrics_nor_create_trace_for_broadcast_outside_of_active_txn
          @subscriber.start('broadcast.action_cable', :id, payload_for_broadcast)
          advance_process_time(1.0)
          @subscriber.finish('broadcast.action_cable', :id, payload_for_broadcast)

          sample = last_transaction_trace

          assert_nil sample, 'Did not expect a transaction to be created for broadcast'
          refute_metrics_recorded ['Ruby/ActionCable/TestBroadcasting/broadcast']
        end

        def test_actual_call_to_broadcast_method_records_segment_in_txn
          in_transaction do |txn|
            @subscriber.start('broadcast.action_cable', :id, payload_for_broadcast)
            advance_process_time(1.0)
            @subscriber.finish('broadcast.action_cable', :id, payload_for_broadcast)
          end

          metric_name = 'Ruby/ActionCable/TestBroadcasting/broadcast'

          assert_metrics_recorded metric_name
          assert find_node_with_name(last_transaction_trace, metric_name),
            'Could not find a node with desired name.'
        end

        def test_metric_name_correctly_names_payload_for_broadcast
          assert_equal 'TestBroadcasting', @subscriber.send(:metric_name, payload_for_broadcast)
        end

        def test_metric_name_correctly_names_payload_for_channel
          assert_equal 'TestChannel', @subscriber.send(:metric_name, payload_for_perform_action)
        end

        def test_actual_call_to_action_cable
          # TODO: Remove when we no longer support Rails 5.0
          # error in rails 5.0
          # No more expects available for :config: []
          skip('this test is flakey in rails 5.0') if defined?(Rails::VERSION) &&
            Rails::VERSION::MAJOR == 5 &&
            Rails::VERSION::MINOR == 0

          config = MiniTest::Mock.new
          config.expect(:log_tags, {})

          logger = ::Logger.new('/dev/null')

          server = MiniTest::Mock.new
          server.expect(:worker_pool, 'dinosaur')
          server.expect(:config, config)
          server.expect(:logger, logger)
          server.expect(:event_loop, nil)

          env = {}
          connection = TestConnection.new(server, env)
          identifier = nil

          channel = TestChannel.new(connection, identifier)
          data = {'action' => 'do_it'}

          in_transaction do |txn|
            channel.perform_action(data)
          end

          metric_name = "Nested/Controller/ActionCable/#{TestChannel.name}/do_it"

          assert_metrics_recorded metric_name
          assert find_node_with_name(last_transaction_trace, metric_name)
          config.verify
          server.verify
        end

        private

        def payload_for_perform_action(action = 'test_action')
          {:channel_class => 'TestChannel', :action => action.to_sym, :data => {'action' => "#{action}"}}
        end

        def payload_for_transmit(data = {}, via = nil)
          {:channel_class => 'TestChannel', :data => data, :via => via}
        end

        def payload_for_broadcast
          {
            broadcasting: 'TestBroadcasting',
            message: {message: 'test_message'},
            coder: 'idk-we-dont-save-this'
          }
        end
      end
    end
  end
end
