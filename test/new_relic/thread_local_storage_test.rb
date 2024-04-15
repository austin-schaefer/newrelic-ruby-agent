# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'
require 'new_relic/thread_local_storage'

class NewRelic::ThreadLocalStorageTest < Minitest::Test
  def test_basic_ops
    assert_nil NewRelic::ThreadLocalStorage.get(Thread.current, :basic)
    NewRelic::ThreadLocalStorage.set(Thread.current, :basic, 'foobar')

    assert_equal('foobar', NewRelic::ThreadLocalStorage.get(Thread.current, :basic))
    NewRelic::ThreadLocalStorage.set(Thread.current, :basic, 12345)

    assert_equal(12345, NewRelic::ThreadLocalStorage.get(Thread.current, :basic))
  end

  def test_shortcut_ops
    assert_nil NewRelic::ThreadLocalStorage[:shortcut]
    NewRelic::ThreadLocalStorage[:shortcut] = 'baz'

    assert_equal('baz', NewRelic::ThreadLocalStorage[:shortcut])
    NewRelic::ThreadLocalStorage[:shortcut] = 98765

    assert_equal(98765, NewRelic::ThreadLocalStorage[:shortcut])
  end

  def test_new_thread
    NewRelic::ThreadLocalStorage[:new_thread] = :parent
    thread = Thread.new do
      Thread.current.abort_on_exception = true

      assert_nil NewRelic::ThreadLocalStorage[:new_thread]
      NewRelic::ThreadLocalStorage[:new_thread] = :child
      sleep
    end
    sleep 0.2

    assert_equal(:parent, NewRelic::ThreadLocalStorage[:new_thread])
    assert_equal(:child, NewRelic::ThreadLocalStorage.get(thread, :new_thread))
    thread.exit
  end

  def test_new_fiber_without_thread_local_tracer_state_flag
    with_config(:thread_local_tracer_state => false) do
      NewRelic::ThreadLocalStorage[:new_fiber_no_flag] = 1
      fiber = Fiber.new do
        assert_nil NewRelic::ThreadLocalStorage[:new_fiber_no_flag]
        NewRelic::ThreadLocalStorage[:new_fiber_no_flag] = 2
      end
      fiber.resume

      assert_equal(1, NewRelic::ThreadLocalStorage[:new_fiber_no_flag])
    end
  end

  def test_new_fiber_with_thread_local_tracer_state_flag
    with_config(:thread_local_tracer_state => true) do
      NewRelic::ThreadLocalStorage[:new_fiber_with_flag] = 1
      fiber = Fiber.new do
        assert_equal(1, NewRelic::ThreadLocalStorage[:new_fiber_with_flag])
        NewRelic::ThreadLocalStorage[:new_fiber_with_flag] = 2
      end
      fiber.resume

      assert_equal(2, NewRelic::ThreadLocalStorage[:new_fiber_with_flag])
    end
  end
end
