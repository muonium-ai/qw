/**
 * Sample Swift Module for QW Editor Testing
 * A comprehensive example demonstrating Swift syntax highlighting.
 *
 * This module implements a task scheduling system with:
 * - Protocol-oriented design
 * - Generics and type constraints
 * - Async/await patterns
 * - Property wrappers
 * - Result builders
 */

import Foundation

// MARK: - Configuration

/// Application configuration settings
enum Configuration {
    static let maxConcurrentTasks = 4
    static let defaultTimeout: TimeInterval = 30.0
    static let retryCount = 3
    static let enableLogging = true
}

// MARK: - Property Wrappers

/// A property wrapper that validates values
@propertyWrapper
struct Validated<Value> {
    private var value: Value
    private let validator: (Value) -> Bool
    private let defaultValue: Value
    
    var wrappedValue: Value {
        get { value }
        set {
            if validator(newValue) {
                value = newValue
            } else {
                print("Validation failed, keeping default value")
                value = defaultValue
            }
        }
    }
    
    init(wrappedValue: Value, validator: @escaping (Value) -> Bool) {
        self.defaultValue = wrappedValue
        self.validator = validator
        self.value = wrappedValue
    }
}

/// A property wrapper for atomic access
@propertyWrapper
final class Atomic<Value> {
    private var value: Value
    private let lock = NSLock()
    
    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
    
    init(wrappedValue: Value) {
        self.value = wrappedValue
    }
}

// MARK: - Protocols

/// Protocol for identifiable entities
protocol Identifiable {
    associatedtype ID: Hashable
    var id: ID { get }
}

/// Protocol for executable tasks
protocol Executable {
    associatedtype Output
    func execute() async throws -> Output
}

/// Protocol for task prioritization
protocol Prioritizable: Comparable {
    var priority: TaskPriority { get }
}

extension Prioritizable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.priority.rawValue < rhs.priority.rawValue
    }
}

/// Protocol for retry policies
protocol RetryPolicy {
    var maxAttempts: Int { get }
    var delay: TimeInterval { get }
    func shouldRetry(attempt: Int, error: Error) -> Bool
}

// MARK: - Enums

/// Task priority levels
enum TaskPriority: Int, CaseIterable, Codable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    var description: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

/// Task execution status
enum TaskStatus: Equatable {
    case pending
    case running
    case completed(Date)
    case failed(Error)
    case cancelled
    
    static func == (lhs: TaskStatus, rhs: TaskStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.running, .running),
             (.cancelled, .cancelled):
            return true
        case (.completed(let d1), .completed(let d2)):
            return d1 == d2
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

/// Task-related errors
enum TaskError: Error, LocalizedError {
    case timeout
    case cancelled
    case maxRetriesExceeded
    case dependencyFailed(String)
    case invalidInput(String)
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Task timed out"
        case .cancelled:
            return "Task was cancelled"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .dependencyFailed(let name):
            return "Dependency '\(name)' failed"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Models

/// Represents an executable task
struct ScheduledTask<Output>: Identifiable, Prioritizable {
    let id: UUID
    let name: String
    let priority: TaskPriority
    let createdAt: Date
    let timeout: TimeInterval
    var status: TaskStatus
    let execute: () async throws -> Output
    
    init(
        id: UUID = UUID(),
        name: String,
        priority: TaskPriority = .normal,
        timeout: TimeInterval = Configuration.defaultTimeout,
        execute: @escaping () async throws -> Output
    ) {
        self.id = id
        self.name = name
        self.priority = priority
        self.createdAt = Date()
        self.timeout = timeout
        self.status = .pending
        self.execute = execute
    }
}

/// Task execution result
struct TaskResult<Output> {
    let taskId: UUID
    let output: Output?
    let error: Error?
    let startTime: Date
    let endTime: Date
    let attempts: Int
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var isSuccess: Bool {
        output != nil && error == nil
    }
}

// MARK: - Retry Policies

/// Exponential backoff retry policy
struct ExponentialBackoffPolicy: RetryPolicy {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let multiplier: Double
    
    var delay: TimeInterval { initialDelay }
    
    init(maxAttempts: Int = 3, initialDelay: TimeInterval = 1.0, multiplier: Double = 2.0) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
    }
    
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        return attempt < maxAttempts
    }
    
    func delayForAttempt(_ attempt: Int) -> TimeInterval {
        initialDelay * pow(multiplier, Double(attempt - 1))
    }
}

/// Simple fixed delay retry policy
struct FixedDelayPolicy: RetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        return attempt < maxAttempts
    }
}

// MARK: - Task Scheduler

/// A concurrent task scheduler with priority support
actor TaskScheduler {
    private var tasks: [UUID: any Identifiable] = [:]
    private var runningCount = 0
    private let maxConcurrent: Int
    private var completedResults: [UUID: Any] = [:]
    
    init(maxConcurrent: Int = Configuration.maxConcurrentTasks) {
        self.maxConcurrent = maxConcurrent
    }
    
    /// Schedule a new task
    func schedule<Output>(_ task: ScheduledTask<Output>) -> UUID {
        log("Scheduling task: \(task.name)")
        return task.id
    }
    
    /// Execute a task with retry support
    func execute<Output>(
        _ task: ScheduledTask<Output>,
        retryPolicy: some RetryPolicy = FixedDelayPolicy(maxAttempts: 1, delay: 0)
    ) async throws -> TaskResult<Output> {
        log("Starting task: \(task.name)")
        
        let startTime = Date()
        var lastError: Error?
        var attempts = 0
        
        while attempts < retryPolicy.maxAttempts {
            attempts += 1
            
            do {
                runningCount += 1
                defer { runningCount -= 1 }
                
                let output = try await withTimeout(task.timeout) {
                    try await task.execute()
                }
                
                let result = TaskResult(
                    taskId: task.id,
                    output: output,
                    error: nil,
                    startTime: startTime,
                    endTime: Date(),
                    attempts: attempts
                )
                
                log("Task \(task.name) completed successfully after \(attempts) attempt(s)")
                return result
                
            } catch {
                lastError = error
                log("Task \(task.name) failed attempt \(attempts): \(error)")
                
                if retryPolicy.shouldRetry(attempt: attempts, error: error) {
                    try await Task.sleep(nanoseconds: UInt64(retryPolicy.delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? TaskError.maxRetriesExceeded
    }
    
    /// Execute with a timeout
    private func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TaskError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Get running task count
    func getRunningCount() -> Int {
        runningCount
    }
    
    /// Log a message
    private func log(_ message: String) {
        if Configuration.enableLogging {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("[\(timestamp)] TaskScheduler: \(message)")
        }
    }
}

// MARK: - Task Builder

/// Result builder for composing tasks
@resultBuilder
struct TaskListBuilder<Output> {
    static func buildBlock(_ components: ScheduledTask<Output>...) -> [ScheduledTask<Output>] {
        components
    }
    
    static func buildOptional(_ component: [ScheduledTask<Output>]?) -> [ScheduledTask<Output>] {
        component ?? []
    }
    
    static func buildEither(first component: [ScheduledTask<Output>]) -> [ScheduledTask<Output>] {
        component
    }
    
    static func buildEither(second component: [ScheduledTask<Output>]) -> [ScheduledTask<Output>] {
        component
    }
    
    static func buildArray(_ components: [[ScheduledTask<Output>]]) -> [ScheduledTask<Output>] {
        components.flatMap { $0 }
    }
}

/// A pipeline for executing multiple tasks
struct TaskPipeline<Output> {
    private let tasks: [ScheduledTask<Output>]
    
    init(@TaskListBuilder<Output> builder: () -> [ScheduledTask<Output>]) {
        self.tasks = builder()
    }
    
    func execute(on scheduler: TaskScheduler) async throws -> [TaskResult<Output>] {
        var results: [TaskResult<Output>] = []
        
        for task in tasks.sorted(by: >) {
            let result = try await scheduler.execute(task)
            results.append(result)
        }
        
        return results
    }
}

// MARK: - Extensions

extension Array where Element: Prioritizable {
    /// Sort by priority (highest first)
    func sortedByPriority() -> [Element] {
        sorted(by: >)
    }
}

extension Date {
    /// Format date for logging
    var logFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: self)
    }
}

extension String {
    /// Truncate string with ellipsis
    func truncated(to length: Int) -> String {
        if count <= length { return self }
        return String(prefix(length - 3)) + "..."
    }
}

// MARK: - Demo

/// Example usage
func runDemo() async {
    let scheduler = TaskScheduler()
    
    // Create individual tasks
    let task1 = ScheduledTask(name: "Fetch Data", priority: .high) {
        try await Task.sleep(nanoseconds: 500_000_000)
        return "Data fetched"
    }
    
    let task2 = ScheduledTask(name: "Process", priority: .normal) {
        try await Task.sleep(nanoseconds: 300_000_000)
        return "Processed"
    }
    
    // Use task builder
    let pipeline = TaskPipeline {
        task1
        task2
        
        ScheduledTask(name: "Cleanup", priority: .low) {
            "Cleaned up"
        }
    }
    
    do {
        let results = try await pipeline.execute(on: scheduler)
        for result in results {
            if let output = result.output {
                print("Task \(result.taskId) completed: \(output)")
            }
        }
    } catch {
        print("Pipeline failed: \(error)")
    }
}

// Entry point
@main
struct SampleApp {
    static func main() async {
        await runDemo()
    }
}
