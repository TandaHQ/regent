# frozen_string_literal: true

module Regent
  module Engine
    class React < Base
      SEQUENCES = {
        answer: "Answer:",
        action: "Action:",
        observation: "Observation:",
        stop: "PAUSE"
      }.freeze

      def reason(task)
        session.exec(Span::Type::INPUT, top_level: true, message: task) { task }
        
        # Only add system prompt if this is a new conversation
        if session.messages.empty? || session.messages.none? { |msg| msg[:role] == :system }
          session.add_message({role: :system, content: Regent::Engine::React::PromptTemplate.system_prompt(context, toolchain.to_s)})
        end
        
        # Only add user message if it's not already the last message (from continue method)
        unless session.messages.last && session.messages.last[:role] == :user && session.messages.last[:content] == task
          session.add_message({role: :user, content: task})
        end

        with_max_iterations do
          content = llm_call_response(stop: [SEQUENCES[:stop]])
          session.add_message({role: :assistant, content: content })

          return extract_answer(content) if answer_present?(content)

          if action_present?(content)
            tool_name, arguments = parse_tool_signature(content)
            tool = find_tool(tool_name)
            return unless tool
            result = tool_call_response(tool, arguments)
            session.add_message({ role: :user, content: "#{SEQUENCES[:observation]} #{result}" })
          end
        end
      end

      private

      def answer_present?(content)
        content.include?(SEQUENCES[:answer])
      end

      def action_present?(content)
        content.include?(SEQUENCES[:action])
      end

      def extract_answer(content)
        success_answer content.split(SEQUENCES[:answer])[1]&.strip
      end

      def parse_tool_signature(content)
        return [nil, nil] unless match = content.match(/Action:.*?\{.*"tool".*\}/m)

        # Extract just the JSON part using a second regex
        json = JSON.parse(match[0].match(/\{.*\}/m)[0])
        [json["tool"], json["args"] || []]
      rescue JSON::ParserError
        [nil, nil]
      end
    end
  end
end
