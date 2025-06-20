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

    # Continues a conversation with existing messages
    # @param messages [Array<Hash>] Array of message hashes from previous conversation
    # @param new_task [String] The new user input to continue the conversation
    # @return [String] The assistant's response
    def continue(messages, new_task)
      raise ArgumentError, "Messages cannot be empty" if messages.nil? || messages.empty?
      raise ArgumentError, "New task cannot be empty" if new_task.to_s.strip.empty?

      # Create session from messages
      @sessions << Session.from_messages(messages)
      session.reactivate
      
      # Add the new user message
      session.add_user_message(new_task)
      
      # Run reasoning to get response
      reason(new_task)
    ensure
      complete_session
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
