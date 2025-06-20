# frozen_string_literal: true

RSpec.describe "Conversational Features" do
  describe Regent::Session do
    describe ".from_messages" do
      it "creates a session with provided message history" do
        messages = [
          { role: :user, content: "Hello" },
          { role: :assistant, content: "Hi there!" },
          { role: :user, content: "How are you?" }
        ]
        
        session = Regent::Session.from_messages(messages)
        
        expect(session.messages).to eq(messages)
        expect(session.messages.count).to eq(3)
      end
      
      it "validates message format" do
        expect {
          Regent::Session.from_messages([{ role: :user }])
        }.to raise_error(ArgumentError, "Message must have :content key")
        
        expect {
          Regent::Session.from_messages([{ content: "Hello" }])
        }.to raise_error(ArgumentError, "Message must have :role key")
        
        expect {
          Regent::Session.from_messages([{ role: :invalid, content: "Hello" }])
        }.to raise_error(ArgumentError, "Message role must be :user, :assistant, or :system")
      end
    end
    
    describe "#messages_for_export" do
      it "exports messages with timestamps" do
        session = Regent::Session.new
        session.start
        session.add_user_message("Hello")
        session.add_assistant_message("Hi there!")
        
        exported = session.messages_for_export
        
        # Just check structure, not exact timestamps since they're dynamic
        expect(exported).to match([
          hash_including(
            role: "user",
            content: "Hello",
            timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          ),
          hash_including(
            role: "assistant", 
            content: "Hi there!",
            timestamp: match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          )
        ])
      end
    end
    
    describe "#add_user_message and #add_assistant_message" do
      it "adds messages with correct roles" do
        session = Regent::Session.new
        
        session.add_user_message("User question")
        session.add_assistant_message("Assistant response")
        
        expect(session.messages[0]).to eq({ role: :user, content: "User question" })
        expect(session.messages[1]).to eq({ role: :assistant, content: "Assistant response" })
      end
    end
    
    describe "#last_answer" do
      it "returns the last assistant message" do
        session = Regent::Session.new
        session.add_user_message("Question 1")
        session.add_assistant_message("Answer 1")
        session.add_user_message("Question 2")
        session.add_assistant_message("Answer 2")
        
        expect(session.last_answer).to eq("Answer 2")
      end
      
      it "returns nil if no assistant messages" do
        session = Regent::Session.new
        session.add_user_message("Question")
        
        expect(session.last_answer).to be_nil
      end
    end
    
    describe "#completed? and #reactivate" do
      it "tracks session completion state" do
        session = Regent::Session.new
        session.start
        
        expect(session.completed?).to be false
        
        session.complete
        expect(session.completed?).to be true
        
        session.reactivate
        expect(session.completed?).to be false
        expect(session.active?).to be true
      end
    end
  end
  
  describe Regent::Agent do
    let(:llm_result) { double("result", content: "Answer: The answer", input_tokens: 10, output_tokens: 20) }
    let(:llm) { double("llm", model: "gpt-4o-mini", invoke: llm_result) }
    let(:agent) { Regent::Agent.new("You are a helpful assistant", model: llm) }
    
    describe "#run with return_session option" do
      it "returns just the answer by default" do
        result = agent.run("Question")
        expect(result).to eq("The answer")
      end
      
      it "returns both answer and session when requested" do
        answer, session = agent.run("Question", return_session: true)
        
        expect(answer).to eq("The answer")
        expect(session).to be_a(Regent::Session)
        expect(session.messages).to include(hash_including(role: :user, content: "Question"))
      end
    end
    
    describe "#continue" do
      it "continues a conversation with existing messages" do
        messages = [
          { role: :system, content: "You are a helpful assistant" },
          { role: :user, content: "What's 2+2?" },
          { role: :assistant, content: "2+2 equals 4" }
        ]
        
        llm_result2 = double("result", content: "Answer: Yes, that's correct!", input_tokens: 10, output_tokens: 20)
        allow(llm).to receive(:invoke).and_return(llm_result2)
        
        answer = agent.continue(messages, "Is that right?")
        
        expect(answer).to eq("Yes, that's correct!")
        expect(agent.session.messages.count).to be >= 4 # Original 3 + new user message + any system prompts
        expect(agent.session.messages.last).to eq({ role: :assistant, content: "Answer: Yes, that's correct!" })
      end
      
      it "validates inputs" do
        expect {
          agent.continue([], "Question")
        }.to raise_error(ArgumentError, "Messages cannot be empty")
        
        expect {
          agent.continue([{ role: :user, content: "Hi" }], "")
        }.to raise_error(ArgumentError, "New task cannot be empty")
      end
    end
  end
  
  describe "End-to-end conversation flow" do
    let(:llm_result1) { double("result", content: "Answer: 2+2 equals 4", input_tokens: 10, output_tokens: 20) }
    let(:llm_result2) { double("result", content: "Answer: Great job! 3+3 equals 6", input_tokens: 10, output_tokens: 20) }
    let(:llm) { double("llm", model: "gpt-4o-mini") }
    let(:agent) { Regent::Agent.new("You are a helpful math tutor", model: llm) }
    
    it "maintains conversation context across multiple interactions" do
      # First interaction
      allow(llm).to receive(:invoke).and_return(llm_result1)
      answer1, session1 = agent.run("What's 2+2?", return_session: true)
      
      expect(answer1).to include("4")
      
      # Export messages - they should have string roles
      messages = session1.messages_for_export
      expect(messages.first[:role]).to be_a(String)
      
      # Continue conversation - strip timestamps and convert roles to symbols
      allow(llm).to receive(:invoke).and_return(llm_result2)
      answer2 = agent.continue(messages.map { |m| { role: m[:role].to_sym, content: m[:content] } }, "Good! Now what's 3+3?")
      
      expect(answer2).to include("6")
      expect(agent.session.messages.any? { |m| m[:content].include?("2+2") }).to be true
    end
  end
end
