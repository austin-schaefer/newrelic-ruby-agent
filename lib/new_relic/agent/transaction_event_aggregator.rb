# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'monitor'

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )
require 'new_relic/agent/payload_metric_mapping'

class NewRelic::Agent::TransactionEventAggregator
  include NewRelic::Coerce,
          MonitorMixin

  # The type field of the sample
  SAMPLE_TYPE              = 'Transaction'.freeze

  # Strings for static keys of the sample structure
  TYPE_KEY                       = 'type'.freeze
  TIMESTAMP_KEY                  = 'timestamp'.freeze
  NAME_KEY                       = 'name'.freeze
  DURATION_KEY                   = 'duration'.freeze
  ERROR_KEY                      = 'error'.freeze
  GUID_KEY                       = 'nr.guid'.freeze
  REFERRING_TRANSACTION_GUID_KEY = 'nr.referringTransactionGuid'.freeze
  CAT_TRIP_ID_KEY                = 'nr.tripId'.freeze
  CAT_PATH_HASH_KEY              = 'nr.pathHash'.freeze
  CAT_REFERRING_PATH_HASH_KEY    = 'nr.referringPathHash'.freeze
  CAT_ALTERNATE_PATH_HASHES_KEY  = 'nr.alternatePathHashes'.freeze
  APDEX_PERF_ZONE_KEY            = 'nr.apdexPerfZone'.freeze
  SYNTHETICS_RESOURCE_ID_KEY     = "nr.syntheticsResourceId".freeze
  SYNTHETICS_JOB_ID_KEY          = "nr.syntheticsJobId".freeze
  SYNTHETICS_MONITOR_ID_KEY      = "nr.syntheticsMonitorId".freeze

  # To avoid allocations when we have empty custom or agent attributes
  EMPTY_HASH = {}.freeze

  def initialize( event_listener )
    super()

    @enabled       = false
    @notified_full = false

    @samples            = ::NewRelic::Agent::SampledBuffer.new(NewRelic::Agent.config[:'analytics_events.max_samples_stored'])
    @synthetics_samples = ::NewRelic::Agent::SyntheticsEventBuffer.new(NewRelic::Agent.config[:'synthetics.events_limit'])

    event_listener.subscribe( :transaction_finished, &method(:on_transaction_finished) )
    self.register_config_callbacks
  end


  ######
  public
  ######

  # Fetch a copy of the sampler's gathered samples. (Synchronized)
  def samples
    return self.synchronize { @samples.to_a.concat(@synthetics_samples.to_a) }
  end

  def reset!
    sample_count, request_count, synthetics_dropped = 0
    old_samples = nil

    self.synchronize do
      sample_count = @samples.size
      request_count = @samples.num_seen

      synthetics_dropped = @synthetics_samples.num_dropped

      old_samples = @samples.to_a + @synthetics_samples.to_a
      @samples.reset!
      @synthetics_samples.reset!

      @notified_full = false
    end

    [old_samples, sample_count, request_count, synthetics_dropped]
  end

  # Clear any existing samples, reset the last sample time, and return the
  # previous set of samples. (Synchronized)
  def harvest!
    old_samples, sample_count, request_count, synthetics_dropped = reset!
    record_sampling_rate(request_count, sample_count) if @enabled
    record_dropped_synthetics(synthetics_dropped)
    old_samples
  end

  # Merge samples back into the buffer, for example after a failed
  # transmission to the collector. (Synchronized)
  def merge!(old_samples)
    self.synchronize do
      old_samples.each { |s| append_event(s) }
    end
  end

  def record_sampling_rate(request_count, sample_count) #THREAD_LOCAL_ACCESS
    request_count_lifetime = @samples.seen_lifetime
    sample_count_lifetime = @samples.captured_lifetime
    NewRelic::Agent.logger.debug("Sampled %d / %d (%.1f %%) requests this cycle, %d / %d (%.1f %%) since startup" % [
      sample_count,
      request_count,
      (sample_count.to_f / request_count * 100.0),
      sample_count_lifetime,
      request_count_lifetime,
      (sample_count_lifetime.to_f / request_count_lifetime * 100.0)
    ])

    engine = NewRelic::Agent.instance.stats_engine
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/requests", request_count)
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/samples", sample_count)
  end

  def record_dropped_synthetics(synthetics_dropped)
    return unless synthetics_dropped > 0

    NewRelic::Agent.logger.debug("Synthetics transaction event limit (#{@samples.capacity}) reached. Further synthetics events this harvest period dropped.")

    engine = NewRelic::Agent.instance.stats_engine
    engine.tl_record_supportability_metric_count("TransactionEventAggregator/synthetics_events_dropped", synthetics_dropped)
  end

  def register_config_callbacks
    NewRelic::Agent.config.register_callback(:'analytics_events.max_samples_stored') do |max_samples|
      NewRelic::Agent.logger.debug "TransactionEventAggregator max_samples set to #{max_samples}"
      self.synchronize { @samples.capacity = max_samples }
    end

    NewRelic::Agent.config.register_callback(:'synthetics.events_limit') do |max_samples|
      NewRelic::Agent.logger.debug "TransactionEventAggregator limit for synthetics events set to #{max_samples}"
      self.synchronize { @synthetics_samples.capacity = max_samples }
    end

    NewRelic::Agent.config.register_callback(:'analytics_events.enabled') do |enabled|
      @enabled = enabled
    end
  end

  def notify_full
    NewRelic::Agent.logger.debug "Transaction event capacity of #{@samples.capacity} reached, beginning sampling"
    @notified_full = true
  end

  # Event handler for the :transaction_finished event.
  def on_transaction_finished(payload)
    return unless @enabled

    attributes = payload[:attributes]
    main_event = create_main_event(payload)
    custom_attributes = create_custom_attributes(attributes)
    agent_attributes  = create_agent_attributes(attributes)

    self.synchronize { append_event([main_event, custom_attributes, agent_attributes]) }
    notify_full if !@notified_full && @samples.full?
  end

  def append_event(event)
    main_event, _ = event

    if main_event.include?(SYNTHETICS_RESOURCE_ID_KEY)
      # Try adding to synthetics buffer. If anything is rejected, give it a
      # shot in the main transaction events (where it may get sampled)
      _, rejected = @synthetics_samples.append_with_reject(event)

      if rejected
        @samples.append(rejected)
      end
    else
      @samples.append(event)
    end
  end

  def create_main_event(payload)
    sample = {
      TIMESTAMP_KEY => float(payload[:start_timestamp]),
      NAME_KEY      => string(payload[:name]),
      DURATION_KEY  => float(payload[:duration]),
      TYPE_KEY      => SAMPLE_TYPE,
      ERROR_KEY     => payload[:error]
    }
    NewRelic::Agent::PayloadMetricMapping.append_mapped_metrics(payload[:metrics], sample)
    optionally_append(GUID_KEY,                       :guid, sample, payload)
    optionally_append(REFERRING_TRANSACTION_GUID_KEY, :referring_transaction_guid, sample, payload)
    optionally_append(CAT_TRIP_ID_KEY,                :cat_trip_id, sample, payload)
    optionally_append(CAT_PATH_HASH_KEY,              :cat_path_hash, sample, payload)
    optionally_append(CAT_REFERRING_PATH_HASH_KEY,    :cat_referring_path_hash, sample, payload)
    optionally_append(APDEX_PERF_ZONE_KEY,            :apdex_perf_zone, sample, payload)
    optionally_append(SYNTHETICS_RESOURCE_ID_KEY,     :synthetics_resource_id, sample, payload)
    optionally_append(SYNTHETICS_JOB_ID_KEY,          :synthetics_job_id, sample, payload)
    optionally_append(SYNTHETICS_MONITOR_ID_KEY,      :synthetics_monitor_id, sample, payload)
    append_cat_alternate_path_hashes(sample, payload)
    sample
  end

  def append_cat_alternate_path_hashes(sample, payload)
    if payload.include?(:cat_alternate_path_hashes)
      sample[CAT_ALTERNATE_PATH_HASHES_KEY] = payload[:cat_alternate_path_hashes].sort.join(',')
    end
  end

  def optionally_append(sample_key, payload_key, sample, payload)
    if payload.include?(payload_key)
      sample[sample_key] = string(payload[payload_key])
    end
  end

  def create_custom_attributes(attributes)
    if attributes
      custom_attributes = attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
      custom_attributes = custom_attributes
      custom_attributes.freeze
    else
      EMPTY_HASH
    end
  end

  def create_agent_attributes(attributes)
    if attributes
      agent_attributes = attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
      agent_attributes = agent_attributes
      agent_attributes.freeze
    else
      EMPTY_HASH
    end
  end
end
