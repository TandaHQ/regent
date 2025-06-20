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

    def run(task, return_session: false)
      raise ArgumentError, "Task cannot be empty" if task.to_s.strip.empty?

      start_session
      result = reason(task)
      
      return_session ? [result, session] : result
    ensure
      complete_session
    end

    # Continues a conversation with existing messages or adds to current conversation
    # @param messages_or_task [Array<Hash>, String] Either message history or new task
    # @param new_task [String, nil] New task if first param is messages
    # @return [String] The assistant's response
    def continue(messages_or_task, new_task = nil)
      # If first argument is a string, we're continuing the current session
      if messages_or_task.is_a?(String)
        raise ArgumentError, "No active conversation to continue" unless @continuing_session
        raise ArgumentError, "Task cannot be empty" if messages_or_task.to_s.strip.empty?
        
        # Reactivate the session if it was completed
        session.reactivate if session.completed?
        
        # Run reasoning with the new task
        reason(messages_or_task)
      else
        # Otherwise, we're starting a new conversation from messages
        messages = messages_or_task
        raise ArgumentError, "Messages cannot be empty" if messages.nil? || messages.empty?
        raise ArgumentError, "New task cannot be empty" if new_task.to_s.strip.empty?

        # Create session from messages
        @sessions << Session.from_messages(messages)
        session.reactivate
        @continuing_session = true
        
        # Run reasoning to get response
        reason(new_task)
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
      @continuing_session = false  # Reset continuation flag
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
