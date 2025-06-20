# frozen_string_literal: true

module Regent
  class Agent
    include Concerns::Identifiable
    include Concerns::Toolable

    DEFAULT_MAX_ITERATIONS = 10

    def initialize(context, model:, tools: [], engine: Regent::Engine::React, **options)
      super()

      @context = context
      @model = model.is_a?(String) ? Regent::LLM.new(model) : model
      @engine = engine
      @sessions = []
      @tools = build_toolchain(tools)
      @max_iterations = options[:max_iterations] || DEFAULT_MAX_ITERATIONS
      @continuing_session = false
    end

    attr_reader :context, :sessions, :model, :tools, :inline_tools

    # Runs an agent task or continues a conversation
    # @param task [String] The task or message to process
    # @param messages [Array<Hash>, nil] Optional message history to continue from
    # @param return_session [Boolean] Whether to return both result and session
    # @return [String, Array<String, Session>] The result or [result, session] if return_session is true
    def run(task, messages: nil, return_session: false)
      raise ArgumentError, "Task cannot be empty" if task.to_s.strip.empty?

      if !messages.nil? && messages.any?
        # Continue from provided message history
        @sessions << Session.from_messages(messages)
        session.reactivate
        @continuing_session = true
      elsif @continuing_session
        # Continue current conversation
        raise ArgumentError, "No active conversation to continue" unless session
        session.reactivate if session.completed?
      else
        # Start new session
        start_session
      end

      result = reason(task)
      return_session ? [result, session] : result
    ensure
      complete_session unless @continuing_session
    end

    # Legacy method for backward compatibility
    # @deprecated Use {#run} with messages parameter instead
    def continue(messages_or_task, new_task = nil)
      if messages_or_task.is_a?(String)
        run(messages_or_task)
      else
        run(new_task, messages: messages_or_task)
      end
    end

    def running?
      session&.active? || false
    end

    def session
      @sessions.last
    end

    private

    def reason(task)
      engine.reason(task)
    end

    def start_session
      complete_session
      @sessions << Session.new
      session.start
      @continuing_session = false
    end

    def complete_session
      session&.complete if running?
    end

    def build_toolchain(tools)
      context = self

      toolchain = Toolchain.new(Array(tools))

      self.class.function_tools.each do |entry|
        toolchain.add(entry, context)
      end

      toolchain
    end

    def engine
      @engine.new(context, model, tools, session, @max_iterations)
    end
  end
end
