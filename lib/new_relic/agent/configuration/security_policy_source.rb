# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration/dotted_hash'

module NewRelic
  module Agent
    module Configuration
      class SecurityPolicySource < DottedHash
        ENABLED_PROC = proc { |option| Agent.config[option] }

        RECORD_SQL_ENABLED_PROC = proc do |option|
          Agent.config[option] == 'obfuscated' ||
            Agent.config[option] == 'raw' ||
            false
        end

        NOT_EMPTY_PROC = proc { |option| Agent.config[option].empty? }

        CHANGE_SETTING_PROC = proc do |policies, option, new_value|
          current_value = Agent.config[option]
          unless current_value == new_value
            NewRelic::Agent.logger.info \
              "Setting changed: {#{option}: from #{current_value} " \
              "to #{new_value}}. Source: SecurityPolicySource"
          end
          policies[option] = new_value
        end

        SECURITY_SETTINGS_MAP = {
          "record_sql" => [
            {
              option:         :'transaction_tracer.record_sql',
              supported:      true,
              enabled_fn:     RECORD_SQL_ENABLED_PROC,
              disabled_value: 'off',
              permitted_fn:   proc { |policies|
                CHANGE_SETTING_PROC.call(policies, :'transaction_tracer.record_sql', 'obfuscated')
              }
            },
            {
              option:         :'slow_sql.record_sql',
              supported:      true,
              enabled_fn:     RECORD_SQL_ENABLED_PROC,
              disabled_value: 'off',
              permitted_fn:   proc { |policies|
                CHANGE_SETTING_PROC.call(policies, :'slow_sql.record_sql', 'obfuscated')
              }
            },
            {
              option:         :'mongo.capture_queries',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   proc{ |policies|
                CHANGE_SETTING_PROC.call(policies, :'mongo.obfuscate_queries', true)
              }
            },
            {
              option:         :'transaction_tracer.record_redis_arguments',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ],
          "attributes_include" => [
            {
              option:         :'attributes.include',
              supported:      true,
              enabled_fn:     NOT_EMPTY_PROC,
              disabled_value: [],
              permitted_fn:   nil
            },
            {
              option:         :'transaction_tracer.attributes.include',
              supported:      true,
              enabled_fn:     NOT_EMPTY_PROC,
              disabled_value: [],
              permitted_fn:   nil
            },
            {
              option:         :'transaction_events.attributes.include',
              supported:      true,
              enabled_fn:     NOT_EMPTY_PROC,
              disabled_value: [],
              permitted_fn:   nil
            },
            {
              option:         :'error_collector.attributes.include',
              supported:      true,
              enabled_fn:     NOT_EMPTY_PROC,
              disabled_value: [],
              permitted_fn:   nil
            },
            {
              option:         :'browser_monitoring.attributes.include',
              supported:      true,
              enabled_fn:     NOT_EMPTY_PROC,
              disabled_value: [],
              permitted_fn:   nil
            }
          ],
          "allow_raw_exception_messages" => [
            {
              option:         :'strip_exception_messages.enabled',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ],
          "custom_events" => [
            {
              option:         :'custom_insights_events.enabled',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ],
          "custom_parameters" => [
            {
              option:         :'custom_attributes.enabled',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ],
          "custom_instrumentation_editor" => [
            {
              option:         nil,
              supported:      false,
              enabled_fn:     nil,
              disabled_value: nil,
              permitted_fn:   nil
            }
          ],
          "message_parameters" => [
            {
              option:         :'message_tracer.segment_parameters.enabled',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ],
          "job_arguments" => [
            {
              option:         :'resque.capture_params',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            },
            {
              option:         :'sidekiq.capture_params',
              supported:      true,
              enabled_fn:     ENABLED_PROC,
              disabled_value: false,
              permitted_fn:   nil
            }
          ]
        }

        def initialize(security_policies)
          super(build_overrides(security_policies))
        end

        ENABLED = "enabled".freeze
        COLON_COLON = "::".freeze

        def build_overrides(security_policies)
          security_policies.inject({}) do |settings, (policy_name, policy_settings)|
            policy = SECURITY_SETTINGS_MAP[policy_name].each do |policy|
              next unless policy[:supported]
              if policy_settings[ENABLED]
                if policy[:enabled_fn].call(policy[:option])
                  if permitted_fn = policy[:permitted_fn]
                    permitted_fn.call(settings)
                  end
                else
                  config_source = Agent.config.source(policy[:option]).class.name.split(COLON_COLON).last
                  NewRelic::Agent.logger.info \
                    "Setting applied: {#{policy[:option]}: #{policy[:disabled_value]}}. " \
                    "Source: #{config_source}"
                end
              else
                settings[policy[:option]] =  policy[:disabled_value]
                NewRelic::Agent.logger.info \
                  "Setting applied: {#{policy[:option]}: #{policy[:disabled_value]}}. " \
                  "Source: SecurityPolicySource"
              end
            end
            settings
          end
        end
      end
    end
  end
end
