# frozen_string_literal: true

module Regent
  class Session
    include Concerns::Identifiable
    include Concerns::Durationable

    class SessionError < StandardError; end
    class InactiveSessionError < SessionError; end
    class AlreadyStartedError < SessionError; end

    def initialize
      super()

      @spans = []
      @messages = []
      @start_time = nil
      @end_time = nil
    end

    # Creates a new session from existing messages
    # @param messages [Array<Hash>] Array of message hashes with :role and :content keys
    # @return [Session] A new session with the provided message history
    def self.from_messages(messages)
      session = new
      messages.each do |msg|
        session.add_message(msg)
      end
      session
    end

    # Validates message format
    # @param message [Hash] The message to validate
    # @raise [ArgumentError] if message format is invalid
    def self.validate_message_format(message)
      raise ArgumentError, "Message must be a Hash" unless message.is_a?(Hash)
      raise ArgumentError, "Message must have :role key" unless message.key?(:role)
      raise ArgumentError, "Message must have :content key" unless message.key?(:content)
      raise ArgumentError, "Message role must be :user, :assistant, or :system" unless [:user, :assistant, :system].include?(message[:role])
      raise ArgumentError, "Message content cannot be empty" if message[:content].to_s.strip.empty?
    end

    attr_reader :id, :spans, :messages, :start_time, :end_time

    # Starts the session
    # @raise [AlreadyStartedError] if session is already started
    # @return [void]
    def start
      raise AlreadyStartedError, "Session already started" if @start_time

      @start_time = Time.now.freeze
    end

    # Executes a new span in the session
    # @param type [Symbol, String] The type of span
    # @param options [Hash] Options for the span
    # @raise [InactiveSessionError] if session is not active
    # @return [String] The output of the span
    def exec(type, options = {}, &block)
      raise InactiveSessionError, "Cannot execute span in inactive session" unless active?

      @spans << Span.new(type: type, arguments: options)
      current_span.run(&block)
    end

    # Replays the session
    # @return [String] The result of the session
    def replay
      spans.each { |span| span.replay }
      result
    end

    # Completes the session and returns the result
    # @return [Object] The result of the last span
    # @raise [InactiveSessionError] if session is not active
    # @return [String] The result of the last span
    def complete
      raise InactiveSessionError, "Cannot complete inactive session" unless active?

      @end_time = Time.now.freeze
      result
    end

    # @return [Span, nil] The current span or nil if no spans exist
    def current_span
      @spans.last
    end

    # @return [String, nil] The output of the current span or nil if no spans exist
    def result
      current_span&.output
    end

    # @return [Boolean] Whether the session is currently active
    def active?
      start_time && end_time.nil?
    end

    # Adds a message to the session
    # @param message [Hash] The message to add with :role and :content keys
    # @raise [ArgumentError] if message is nil or invalid format
    def add_message(message)
      raise ArgumentError, "Message cannot be nil" if message.nil?
      self.class.validate_message_format(message)

      @messages << message
    end

    # Adds a user message to the conversation
    # @param content [String] The message content
    # @return [void]
    def add_user_message(content)
      add_message({ role: :user, content: content })
    end

    # Adds an assistant message to the conversation
    # @param content [String] The message content
    # @return [void]
    def add_assistant_message(content)
      add_message({ role: :assistant, content: content })
    end

    # Checks if the session has been completed
    # @return [Boolean] true if session has ended
    def completed?
      !end_time.nil?
    end

    # Retrieves the last assistant answer from messages or spans
    # @return [String, nil] The last assistant response or nil if none found
    def last_answer
      # First check messages for assistant responses
      last_assistant_msg = messages.reverse.find { |msg| msg[:role] == :assistant }
      return last_assistant_msg[:content] if last_assistant_msg

      # Fallback to spans with answer type
      answer_span = spans.reverse.find { |span| span.type == Span::Type::ANSWER }
      answer_span&.output
    end

    # Exports messages in a format suitable for storage
    # @return [Array<Hash>] Array of message hashes with role, content, and timestamp
    def messages_for_export
      messages.map.with_index do |msg, index|
        # Calculate approximate timestamp based on session timing and message position
        timestamp = if start_time
                      if messages.length > 1
                        duration = (end_time || Time.now) - start_time
                        start_time + (duration * index.to_f / (messages.length - 1))
                      else
                        start_time
                      end
                    else
                      Time.now
                    end

        {
          role: msg[:role].to_s,
          content: msg[:content],
          timestamp: timestamp.iso8601
        }
      end
    end

    # Reactivates a completed session for continuation
    # @return [void]
    def reactivate
      @end_time = nil
      @start_time ||= Time.now.freeze
    end
  end
end
