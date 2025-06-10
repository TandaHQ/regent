# Regent Conversational Architecture Implementation Plan

## Overview

This document outlines the implementation plan for adding conversational capabilities to Regent, enabling persistent conversations across requests in Rails applications.

## Current State Analysis

### What We Have
- `Regent::Agent` - Creates fresh sessions for each `run()` call
- `Regent::Session` - Contains messages, spans, timing (perfect for persistence)
- `Regent::Engine::React` - Already manages message history within sessions
- Clean tool and LLM abstractions

### What We Need
- Session persistence and restoration
- Conversation continuation without losing context
- Rails-friendly API for new vs continuing conversations
- Backward compatibility with existing `agent.run()` API

## Implementation Plan

### Phase 1: Core Session Enhancements

#### 1.1 Enhance Session Class (`lib/regent/session.rb`)

**New Methods:**
```ruby
class Session
  # Persistence
  def to_h
  def self.from_h(hash)
  
  # Conversation management
  def continue(task)
  def reactivate
  def completed?
  def last_answer
  
  # Rails integration
  def associate_conversation(conversation_record)
  def persist!
end
```

**Implementation Details:**
- `to_h` - Serialize session state including messages, spans, metadata
- `from_h` - Reconstruct session from persisted hash data
- `continue(task)` - Add new user message and reactivate if completed
- `reactivate` - Reset `@end_time` to nil to make session active again
- `last_answer` - Extract last assistant response from messages or answer span
- Rails integration methods for ActiveRecord association

#### 1.2 Enhance Agent Class (`lib/regent/agent.rb`)

**New Methods:**
```ruby
class Agent
  # Class methods for conversation management
  def self.start_conversation(context, user: nil, **options)
  
  # Instance methods for session continuation
  def continue_session(session, task)
  
  # Modified run method to return both answer and session
  def run(task)
    # Returns [answer, session] instead of just answer
end
```

**Implementation Details:**
- `start_conversation` - Create new persisted conversation record
- `continue_session` - Reactivate session, add message, run reasoning
- Modified `run` to optionally return session for immediate continuation
- Preserve existing behavior for backward compatibility

### Phase 2: Rails Integration Layer

#### 2.1 ActiveRecord Model

**Migration:**
```ruby
class CreateRegentConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :regent_conversations do |t|
      t.string :agent_class, null: false      # "WeatherAgent"
      t.text :context, null: false            # Agent's system context
      t.json :agent_config, default: {}       # model, tools, options
      t.json :messages, default: []           # Full conversation history
      t.json :spans, default: []              # Execution traces
      t.references :user, foreign_key: true, null: true
      t.string :title                         # Optional conversation title
      t.timestamps
    end
    
    add_index :regent_conversations, [:user_id, :created_at]
    add_index :regent_conversations, :agent_class
  end
end
```

**Model Implementation:**
```ruby
class RegentConversation < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :agent_class, :context, presence: true
  validate :agent_class_exists
  
  scope :by_agent, ->(agent_class) { where(agent_class: agent_class.name) }
  scope :recent, -> { order(updated_at: :desc) }
  
  # Core conversation methods
  def ask(question)
  def agent_instance
  def to_regent_session
  
  # Utility methods
  def message_count
  def tokens_used
  def last_answer
  
  private
  
  def agent_class_exists
    agent_class.constantize
  rescue NameError
    errors.add(:agent_class, "is not a valid agent class")
  end
end
```

#### 2.2 Engine Compatibility

**React Engine Updates (`lib/regent/engine/react.rb`):**
- Ensure message history preservation across session continuations
- Handle session reactivation in reasoning loop
- Maintain tool execution context across conversations

**Base Engine Updates (`lib/regent/engine/base.rb`):**
- Update span creation to handle session restoration
- Ensure LLM calls work with restored message history

### Phase 3: API Design and Implementation

#### 3.1 Primary Usage Patterns

**Pattern 1: Rails Controller Integration**
```ruby
class ConversationsController < ApplicationController
  # POST /conversations
  def create
    @conversation = WeatherAgent.start_conversation(
      "You are a helpful weather assistant",
      user: current_user,
      model: params[:model] || "gpt-4o"
    )
    
    if params[:message].present?
      answer = @conversation.ask(params[:message])
      render json: { answer: answer, conversation_id: @conversation.id }
    else
      render json: { conversation_id: @conversation.id }
    end
  end
  
  # POST /conversations/:id/messages
  def message
    @conversation = current_user.regent_conversations.find(params[:id])
    answer = @conversation.ask(params[:message])
    
    render json: { 
      answer: answer, 
      conversation_id: @conversation.id,
      message_count: @conversation.message_count
    }
  end
end
```

**Pattern 2: Direct Ruby Usage**
```ruby
# Start new conversation
conversation = WeatherAgent.start_conversation(
  "You are a weather assistant", 
  user: current_user,
  model: "gpt-4o"
)

answer = conversation.ask("What's the weather in London?")
# => "It's currently 15°C and rainy in London"

# Continue conversation in another request
conversation = RegentConversation.find(123)
answer = conversation.ask("Is that colder than usual?")
# => "Yes, that's about 5 degrees colder than average"
```

**Pattern 3: Backward Compatibility**
```ruby
# Existing API continues to work unchanged
agent = WeatherAgent.new("You are a weather assistant", model: "gpt-4o")
answer = agent.run("What's the weather?")
# => Works exactly as before

# New session-aware API
answer, session = agent.run("What's the weather?")
next_answer = agent.continue_session(session, "Is it going to rain?")
```

#### 3.2 Advanced Usage Patterns

**Conversation Management:**
```ruby
# List user's conversations
user.regent_conversations.by_agent(WeatherAgent).recent

# Conversation metadata
conversation.message_count  # => 5
conversation.tokens_used   # => 1247
conversation.last_answer   # => "Yes, that's colder than usual"

# Export conversation
conversation.to_h  # Full conversation export

# Clone conversation with new context
new_conversation = conversation.clone_with_context("You are now a travel assistant")
```

### Phase 4: Testing Strategy

#### 4.1 Unit Tests
- Session serialization/deserialization (`to_h`/`from_h`)
- Session continuation and reactivation
- Agent conversation management
- ActiveRecord model validations and associations

#### 4.2 Integration Tests
- Full conversation flows across multiple requests
- Rails controller integration
- Error handling (invalid sessions, missing conversations)
- User scoping and permissions

#### 4.3 Backward Compatibility Tests
- Ensure existing `agent.run()` behavior unchanged
- Verify all existing specs continue to pass
- Test migration paths for existing code

### Phase 5: Documentation and Examples

#### 5.1 README Updates
- Add conversational usage examples
- Document Rails integration patterns
- Show migration from single-run to conversational usage

#### 5.2 Example Applications
- Rails API example with conversation management
- Background job integration for long-running conversations
- Multi-user conversation scenarios

## Implementation Order

### Sprint 1: Core Infrastructure
1. Enhance `Session` class with persistence methods
2. Add `Agent` conversation management methods
3. Create basic ActiveRecord model
4. Write comprehensive tests

### Sprint 2: Rails Integration
1. Complete ActiveRecord model with all features
2. Update engines for conversation compatibility
3. Add controller patterns and examples
4. Integration testing

### Sprint 3: Polish and Documentation
1. Backward compatibility verification
2. Performance optimization
3. Documentation updates
4. Example applications

## Technical Considerations

### Performance
- JSON serialization for messages/spans should be efficient
- Index conversations by user and recency
- Consider pagination for long conversations
- Lazy loading of spans for large conversation histories

### Security
- Ensure user can only access their own conversations
- Validate agent class names to prevent code injection
- Sanitize conversation data before persistence

### Error Handling
- Graceful handling of corrupted session data
- Fallback behavior when session restoration fails
- Clear error messages for invalid conversation states

### Scalability
- Design for horizontal scaling (stateless requests)
- Consider separate storage for large conversation histories
- Plan for conversation archival and cleanup

## Migration Strategy

### For Existing Users
1. All existing code continues to work unchanged
2. Opt-in to conversational features via new methods
3. Gradual migration path with examples and guides
4. No breaking changes to current API

### Database Migrations
1. Add `regent_conversations` table
2. Optional: Add indexes for performance
3. Provide generator for Rails applications

## Success Metrics

### Functional Requirements
- [ ] Can start new conversations and persist them
- [ ] Can continue conversations across requests
- [ ] Full message history preserved
- [ ] Execution traces (spans) available for debugging
- [ ] Backward compatibility maintained

### Non-Functional Requirements
- [ ] Performance comparable to current single-run behavior
- [ ] Memory usage doesn't grow with conversation length
- [ ] Rails integration feels natural and idiomatic
- [ ] Clear error messages and debugging capabilities

## Future Enhancements

### Phase 6+: Advanced Features
- Conversation branching and forking
- Conversation templates and presets
- Real-time conversation streaming
- Conversation analytics and insights
- Multi-agent conversations
- Conversation export/import formats

This plan provides a comprehensive roadmap for implementing conversational capabilities while maintaining Regent's elegant simplicity and Ruby idioms.