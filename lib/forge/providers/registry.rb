# frozen_string_literal: true

module Forge
  module Providers
    class Registry
      TYPES = {
        "openai_compatible" => OpenAICompatible,
        "ollama" => Ollama
      }.freeze

      def self.build(config, global_config:)
        type = config["type"] || "openai_compatible"
        klass = TYPES[type]
        raise ConfigurationError, "Unknown provider type: #{type}" unless klass

        klass.new(config, global_config: global_config)
      end

      def self.build_failover_chain(configuration)
        configuration.failover_providers.map do |provider_config|
          build(provider_config, global_config: configuration)
        end
      end
    end

    class Failover
      def initialize(providers)
        @providers = providers
        raise ConfigurationError, "No providers configured" if @providers.empty?
      end

      def chat(messages:, tools: nil, stream: false, &block)
        errors = []

        @providers.each do |provider|
          Forge.logger.info("Using provider: #{provider.name} (#{provider.model})")
          return provider.chat(messages: messages, tools: tools, stream: stream, &block)
        rescue ProviderError, Faraday::Error => e
          errors << "#{provider.name}: #{e.message}"
          Forge.logger.warn("Provider #{provider.name} failed: #{e.message}")
        end

        raise ProviderError, "All providers failed:\n#{errors.join("\n")}"
      end

      attr_reader :providers

      def primary
        @providers.first
      end
    end
  end
end

require "faraday"
