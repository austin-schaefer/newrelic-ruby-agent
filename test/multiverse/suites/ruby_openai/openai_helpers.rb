# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module OpenAIHelpers
  class ChatResponse
    def body(return_value: false)
      if Gem::Version.new(::OpenAI::VERSION) >= Gem::Version.new('6.0.0') || return_value
        {'id' => 'chatcmpl-8nEZg6Gb5WFOwAz34Hivh4IXH0GHq',
         'object' => 'chat.completion',
         'created' => 1706744788,
         'model' => 'gpt-3.5-turbo-0613',
         'choices' =>
          [{'index' => 0,
            'message' => {'role' => 'assistant', 'content' => 'The 2020 World Series was played at Globe'},
            'logprobs' => nil,
            'finish_reason' => 'length'}],
         'usage' => {'prompt_tokens' => 53, 'completion_tokens' => 10, 'total_tokens' => 63},
         'system_fingerprint' => nil}
      else
        "{\n  \"id\": \"chatcmpl-8nEZg6Gb5WFOwAz34Hivh4IXH0GHq\",\n  \"object\": \"chat.completion\",\n  \"created\": 1706744788,\n  \"model\": \"gpt-3.5-turbo-0613\",\n  \"choices\": [\n    {\n      \"index\": 0,\n      \"message\": {\n        \"role\": \"assistant\",\n        \"content\": \"The 2020 World Series was played at Globe\"\n      },\n      \"logprobs\": null,\n      \"finish_reason\": \"length\"\n    }\n  ],\n  \"usage\": {\n    \"prompt_tokens\": 53,\n    \"completion_tokens\": 10,\n    \"total_tokens\": 63\n  },\n  \"system_fingerprint\": null\n}\n"
      end
    end
  end

  def client
    @client ||= OpenAI::Client.new(access_token: 'FAKE_ACCESS_TOKEN')
  end

  def connection_client
    Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('4.3.2') ? OpenAI::Client : client
  end

  def embeddings_params
    {
      model: 'text-embedding-ada-002', # Required.
      input: 'The food was delicious and the waiter...'
    }
  end

  def chat_params
    {
      model: 'gpt-3.5-turbo', # Required.
      messages: [ # Required.
        {'role' => 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content' => 'Who won the world series in 2020?'},
        {'role': 'assistant', 'content': 'The Los Angeles Dodgers won the World Series in 2020.'},
        {'role': 'user', 'content': 'Where was it played?'}
      ],
      temperature: 0.7,
      max_tokens: 10
    }
  end

  def chat_completion_net_http_response_headers
    {'date' => ['Fri, 02 Feb 2024 17:37:16 GMT'],
     'content-type' => ['application/json'],
     'transfer-encoding' => ['chunked'],
     'connection' => ['keep-alive'],
     'access-control-allow-origin' => ['*'],
     'cache-control' => ['no-cache, must-revalidate'],
     'openai-model' => ['gpt-3.5-turbo-0613'],
     'openai-organization' => ['user-gr8l0l'],
     'openai-processing-ms' => ['242'],
     'openai-version' => ['2020-10-01'],
     'strict-transport-security' => ['max-age=15724800; includeSubDomains'],
     'x-ratelimit-limit-requests' => ['5000'],
     'x-ratelimit-limit-tokens' => ['80000'],
     'x-ratelimit-remaining-requests' => ['4999'],
     'x-ratelimit-remaining-tokens' => ['79952'],
     'x-ratelimit-reset-requests' => ['12ms'],
     'x-ratelimit-reset-tokens' => ['36ms'],
     'x-request-id' => ['cabbag3'],
     'cf-cache-status' => ['DYNAMIC'],
     'set-cookie' =>
  ['__cf_bm=8fake_value; path=/; expires=Fri, 02-Feb-24 18:07:16 GMT; domain=.api.openai.com; HttpOnly; Secure; SameSite=None',
    '_cfuvid=fake_value; path=/; domain=.api.openai.com; HttpOnly; Secure; SameSite=None'],
     'server' => ['cloudflare'],
     'cf-ray' => ['g2g-SJC'],
     'alt-svc' => ['h3=":443"; ma=86400']}
  end

  def edits_params
    {
      model: 'text-davinci-edit-001',
      input: 'What day of the wek is it?',
      instruction: 'Fix the spelling mistakes'
    }
  end

  def edits_request
    in_transaction do
      stub_post_request do
        connection_client.json_post(path: '/edits', parameters: edits_params)
      end
    end
  end

  # ruby-openai uses Faraday to make requests to the OpenAI API
  # by stubbing the connection, we can avoid making HTTP requests
  def faraday_connection
    faraday_connection = Faraday.new
    def faraday_connection.post(*args); ChatResponse.new; end

    faraday_connection
  end

  def error_faraday_connection
    faraday_connection = Faraday.new
    def faraday_connection.post(*args); raise 'deception'; end

    faraday_connection
  end

  def error_httparty_connection
    def HTTParty.post(*args); raise 'deception'; end
  end

  def simulate_chat_json_post_error
    if Gem::Version.new(::Ruby::OpenAI::VERSION) < Gem::Version.new('4.0.0')
      error_httparty_connection
      client.chat(parameters: chat_params)
    else
      connection_client.stub(:conn, error_faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end
  end

  def simulate_embedding_json_post_error
    if Gem::Version.new(::Ruby::OpenAI::VERSION) < Gem::Version.new('4.0.0')
      error_httparty_connection
      client.embeddings(parameters: embeddings_params)
    else
      connection_client.stub(:conn, error_faraday_connection) do
        client.embeddings(parameters: embeddings_params)
      end
    end
  end

  def embedding_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/embedding/OpenAI/create' }
  end

  def chat_completion_segment(txn)
    txn.segments.find { |s| s.name == 'Llm/completion/OpenAI/create' }
  end

  def raise_chat_segment_error
    txn = nil

    begin
      in_transaction('OpenAI') do |ai_txn|
        txn = ai_txn
        simulate_chat_json_post_error
      end
    rescue StandardError
      # NOOP - allow span and transaction to notice error
    end

    txn
  end

  def raise_embedding_segment_error
    txn = nil

    begin
      in_transaction('OpenAI') do |ai_txn|
        txn = ai_txn
        simulate_embedding_json_post_error
      end
    rescue StandardError
      # NOOP - allow span and transaction to notice error
    end

    txn
  end

  def stub_post_request(&blk)
    if Gem::Version.new(::OpenAI::VERSION) <= Gem::Version.new('3.4.0')
      HTTParty.stub(:post, ChatResponse.new.body(return_value: true)) do
        yield
      end
    else
      connection_client.stub(:conn, faraday_connection) do
        yield
      end
    end
  end
end