# frozen_string_literal: true

module Forge
  class Hooks
    def initialize
      @hooks = Hash.new { |h, k| h[k] = [] }
    end

    def on(event, &block)
      @hooks[event] << block
      self
    end

    def run(event, **payload)
      @hooks[event].each { |hook| hook.call(**payload) }
    end
  end
end
