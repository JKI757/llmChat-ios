# LLM Chat App Refactoring Plan

## Overview
This document outlines the plan to refactor the LLM Chat app to use SwiftOpenAI for remote API calls and LLM.swift for local model execution, while maintaining a clean and user-friendly interface.

## Table of Contents
1. [Architecture Changes](#architecture-changes)
2. [Key Components](#key-components)
3. [UI/UX Improvements](#uiux-improvements)
4. [Implementation Phases](#implementation-phases)
5. [Local Model Support](#local-model-support)
6. [Error Handling](#error-handling--user-feedback)
7. [Future Enhancements](#future-enhancements)

## Architecture Changes

### Service Layer Restructuring
- Replace custom `LLMService` with two specialized services:
  - `OpenAIService`: Handles remote API calls using SwiftOpenAI
  - `LocalLLMService`: Manages local model execution using LLM.swift
- Create `LLMServiceProtocol` for a unified interface
- Implement a service factory for creating appropriate service instances

### Model Layer Updates
- Extend `SavedEndpoint` to support local model paths
- Add model type (remote/local) to endpoint configuration
- Support for both system and user prompts in `SavedPrompt`
- Add model metadata and validation

## Key Components

### Service Protocols
```swift
protocol LLMServiceProtocol {
    func sendMessage(_ message: String, 
                    systemPrompt: String, 
                    userPrompt: String,
                    model: String,
                    temperature: Double,
                    history: [ChatMessage]) async throws -> AsyncThrowingStream<String, Error>
    
    func cancelRequest()
    func getAvailableModels() async throws -> [String]
}
```

### OpenAI Service
- Use SwiftOpenAI for API communication
- Handle streaming responses
- Support both chat and completion endpoints
- Model listing from API

### Local LLM Service
- Use LLM.swift for local model execution
- Support GGUF model format
- Model management (import, delete, list)
- Resource management

### Model Management
- Model import functionality
- Model validation and metadata extraction
- Storage management for local models

## UI/UX Improvements

### Model Selection
- Unified interface for both remote and local models
- Visual indicators for model type
- Model details view

### Endpoint Management
- Support for local model paths
- Model type selector (remote API/local)
- Model validation

### Settings
- Local model storage management
- Default model settings
- Performance settings for local models

## Implementation Phases

### Phase 1: Core Service Implementation
1. Set up SwiftOpenAI and LLM.swift dependencies
2. Implement `OpenAIService` using SwiftOpenAI
3. Implement `LocalLLMService` using LLM.swift
4. Create service factory for creating appropriate service instances

### Phase 2: Model Management
1. Add model import functionality
2. Implement model storage and management
3. Add model validation

### Phase 3: UI Integration
1. Update endpoint management UI
2. Add model import/management screens
3. Update chat view to work with both service types

### Phase 4: Testing & Optimization
1. Test with various models and endpoints
2. Optimize local model performance
3. Handle error cases and edge conditions

## Local Model Support

### Model Import
- File picker for GGUF models
- Copy models to app's documents directory
- Validate model files

### Local Model Execution
- Configure LLM.swift with model path
- Handle context window and token limits
- Manage system resources

### Performance Considerations
- Memory management for large models
- Background processing
- Model quantization options

## Error Handling & User Feedback
- Clear error messages for API and local model issues
- Progress indicators for model loading
- Resource usage monitoring

## Future Enhancements
- Model quantization tools
- Advanced prompt templates
- Conversation history management
- Model fine-tuning support
- Batch processing for local models
- Model comparison tools
- Offline mode with local models

## Progress Tracking
- [ ] Phase 1: Core Service Implementation
  - [ ] Set up dependencies
  - [ ] Implement OpenAIService
  - [ ] Implement LocalLLMService
  - [ ] Create service factory
- [ ] Phase 2: Model Management
- [ ] Phase 3: UI Integration
- [ ] Phase 4: Testing & Optimization
