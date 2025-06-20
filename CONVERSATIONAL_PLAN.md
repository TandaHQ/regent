# Regent Conversational Architecture Implementation Plan

## Overview

This document outlines the implementation plan for adding conversational capabilities to Regent, enabling stateless conversation continuation by allowing users to provide existing message history.

## Current State Analysis

### What We Have
- `Regent::Agent` - Creates fresh sessions for each `run()` call
- `Regent::Session` - Contains messages, spans, timing
- `Regent::Engine::React` - Already manages message history within sessions
- Clean tool and LLM abstractions

### What We Need
- Session restoration from provided messages
- Conversation continuation without losing context
- Simple API for continuing conversations
- Backward compatibility with existing `agent.run()` API

## Implementation Plan

### Phase 1: Core Session Enhancements

#### 1.1 Enhance Session Class (`lib/regent/session.rb`)

**New Methods:**
```ruby
class Session
  # Message-based initialization
  def self.from_messages(messages)
  
  # Conversation management
  def add_user_message(content)
  def add_assistant_message(content)
  def completed?
  def last_answer
  
  # Export for storage
  def messages_for_export
end
```

**Implementation Details:**
- `from_messages` - Create a new session with provided message history
- `add_user_message` - Add a new user message to the conversation
- `add_assistant_message` - Add assistant response (used by engine)
- `completed?` - Check if session has ended
- `last_answer` - Extract last assistant response from messages
- `messages_for_export` - Return messages in a format suitable for storage

#### 1.2 Enhance Agent Class (`lib/regent/agent.rb`)

**New Methods:**
```ruby
class Agent
  # Continue conversation with existing messages
  def continue(messages, new_task)
  
  # Modified run method to optionally return session
  def run(task, return_session: false)
    # Returns answer by default, or [answer, session] if requested
end
```

**Implementation Details:**
- `continue` - Create session from messages, add new task, run reasoning
- Modified `run` to optionally return session for continuation
- Preserve existing behavior for backward compatibility

### Phase 2: Engine Compatibility

#### 2.1 React Engine Updates (`lib/regent/engine/react.rb`)

**Required Changes:**
- Accept sessions with pre-existing message history
- Ensure reasoning loop works with restored sessions
- Maintain tool execution context across conversations

#### 2.2 Base Engine Updates (`lib/regent/engine/base.rb`)

**Required Changes:**
- Handle sessions that start with existing messages
- Ensure LLM calls include full conversation history
- Support message continuity in span creation

### Phase 3: API Design and Implementation

#### 3.1 Primary Usage Patterns

**Pattern 1: Simple Continuation**
```ruby
# Start new conversation
agent = WeatherAgent.new("You are a helpful weather assistant", model: "gpt-4o")
answer = agent.run("What's the weather in London?")
# => "It's currently 15°C and rainy in London"

# Get session for continuation
answer, session = agent.run("What's the weather in London?", return_session: true)

# Export messages for storage (user handles persistence)
messages = session.messages_for_export
# Store messages in your database, Redis, session, etc.

# Later, continue the conversation with stored messages
answer = agent.continue(messages, "Is that colder than usual?")
# => "Yes, that's about 5 degrees colder than average"
```

**Pattern 2: Rails Controller Integration**
```ruby
class ConversationsController < ApplicationController
  # POST /conversations/:id/messages
  def create
    # Load messages from your storage (database, Redis, etc.)
    messages = load_conversation_messages(params[:id])
    
    agent = WeatherAgent.new("You are a helpful weather assistant")
    answer = agent.continue(messages, params[:message])
    
    # Store updated messages
    save_conversation_messages(params[:id], agent.session.messages_for_export)
    
    render json: { answer: answer }
  end
  
  private
  
  def load_conversation_messages(conversation_id)
    # Your implementation - could be ActiveRecord, Redis, etc.
    Conversation.find(conversation_id).messages
  end
  
  def save_conversation_messages(conversation_id, messages)
    # Your implementation
    Conversation.find(conversation_id).update(messages: messages)
  end
end
```

**Pattern 3: Backward Compatibility**
```ruby
# Existing API continues to work unchanged
agent = WeatherAgent.new("You are a weather assistant", model: "gpt-4o")
answer = agent.run("What's the weather?")
# => Works exactly as before, returns just the answer

# Access session after run (existing behavior)
agent.session.messages
# => Array of messages from the conversation
```

#### 3.2 Message Format

**Standard Message Structure:**
```ruby
# Messages should follow this format
messages = [
  { role: "user", content: "What's the weather?" },
  { role: "assistant", content: "It's sunny and 22°C" },
  { role: "user", content: "Should I bring an umbrella?" },
  { role: "assistant", content: "No need for an umbrella today!" }
]

# The agent handles converting these to internal Message objects
```

**Session Export Format:**
```ruby
# session.messages_for_export returns a simple array
exported = session.messages_for_export
# => [
#   { role: "user", content: "...", timestamp: "2024-01-15T10:30:00Z" },
#   { role: "assistant", content: "...", timestamp: "2024-01-15T10:30:05Z" }
# ]
```

### Phase 4: Testing Strategy

#### 4.1 Unit Tests
- Session creation from messages (`Session.from_messages`)
- Message addition and export functionality
- Agent continuation methods
- Message format validation

#### 4.2 Integration Tests
- Full conversation flows with message passing
- Error handling (invalid messages, malformed data)
- Context preservation across continuations
- Tool state handling in continued conversations

#### 4.3 Backward Compatibility Tests
- Ensure existing `agent.run()` behavior unchanged
- Verify all existing specs continue to pass
- Test that new parameters don't break existing usage

### Phase 5: Documentation and Examples

#### 5.1 README Updates
- Add conversational usage examples
- Document message format requirements
- Show different storage strategies (Redis, database, etc.)

#### 5.2 Example Applications
- Simple conversation with in-memory storage
- Rails API with database-backed conversations
- Stateless API with client-side message storage

## Implementation Order

### Sprint 1: Core Infrastructure
1. Add `Session.from_messages` method
2. Implement `Agent#continue` method
3. Add message export functionality to Session
4. Write comprehensive tests

### Sprint 2: Engine Updates
1. Update engines for message history support
2. Ensure proper context handling
3. Test conversation continuity
4. Integration testing

### Sprint 3: Polish and Documentation
1. Backward compatibility verification
2. Performance testing with large message histories
3. Documentation updates
4. Example applications

## Technical Considerations

### Performance
- Message array processing should be efficient
- Consider limiting message history size
- Minimize memory usage for large conversations
- Only include necessary message data in exports

### Security
- Validate message format and content
- Ensure no code injection through message content
- Users responsible for securing their own message storage

### Error Handling
- Validate message structure on import
- Handle missing or malformed message data gracefully
- Clear error messages for invalid formats

### Scalability
- Stateless design enables horizontal scaling
- Message storage strategy determined by user
- No built-in persistence overhead

## Migration Strategy

### For Existing Users
1. All existing code continues to work unchanged
2. Opt-in to conversational features via new methods
3. No database requirements or migrations needed
4. Simple upgrade path with examples

## Success Metrics

### Functional Requirements
- [ ] Can continue conversations using provided messages
- [ ] Message history properly restored in sessions
- [ ] Context preserved across continuations
- [ ] Simple API for message export/import
- [ ] Backward compatibility maintained

### Non-Functional Requirements
- [ ] Performance comparable to current single-run behavior
- [ ] Minimal memory overhead for message handling
- [ ] Clear, simple API that follows Ruby conventions
- [ ] Clear error messages for invalid inputs

## Future Enhancements

### Potential Extensions
- Message compression for large histories
- Automatic message pruning strategies
- Conversation branching support
- Streaming conversation updates
- Multi-agent conversation coordination
- Standard export formats (OpenAI, Anthropic, etc.)

## Summary

This simplified approach removes all database and persistence requirements, making Regent conversations completely stateless. Users provide their existing messages when continuing conversations, and the Agent class handles creating sessions with the proper context. This design:

1. **Simplifies the API** - No database migrations or ActiveRecord models needed
2. **Increases flexibility** - Users can store messages anywhere (database, Redis, sessions, client-side)
3. **Maintains simplicity** - Follows Regent's philosophy of elegant, simple abstractions
4. **Ensures compatibility** - Existing code continues to work without changes

The implementation focuses on enhancing the Session and Agent classes to accept and work with provided message histories, making conversational AI accessible without infrastructure overhead.