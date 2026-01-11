#!/usr/bin/env python3
"""
Sample Python Script for QW Editor Testing
A comprehensive example demonstrating Python syntax highlighting.

This module implements a simple task management system with:
- Task creation and management
- Priority queuing
- Data persistence
- Async operations
"""

import json
import asyncio
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any, Callable
from datetime import datetime, timedelta
from enum import Enum, auto
from pathlib import Path
from abc import ABC, abstractmethod
import functools
import threading
import queue

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class Priority(Enum):
    """Task priority levels."""
    LOW = auto()
    MEDIUM = auto()
    HIGH = auto()
    CRITICAL = auto()


class TaskStatus(Enum):
    """Task status enumeration."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"


@dataclass
class Task:
    """Represents a task in the task management system."""
    id: int
    title: str
    description: str = ""
    priority: Priority = Priority.MEDIUM
    status: TaskStatus = TaskStatus.PENDING
    created_at: datetime = field(default_factory=datetime.now)
    due_date: Optional[datetime] = None
    tags: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def __post_init__(self):
        """Validate task after initialization."""
        if not self.title:
            raise ValueError("Task title cannot be empty")
        if self.due_date and self.due_date < self.created_at:
            raise ValueError("Due date cannot be before creation date")
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert task to dictionary for serialization."""
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "priority": self.priority.name,
            "status": self.status.value,
            "created_at": self.created_at.isoformat(),
            "due_date": self.due_date.isoformat() if self.due_date else None,
            "tags": self.tags,
            "metadata": self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Task":
        """Create task from dictionary."""
        return cls(
            id=data["id"],
            title=data["title"],
            description=data.get("description", ""),
            priority=Priority[data.get("priority", "MEDIUM")],
            status=TaskStatus(data.get("status", "pending")),
            created_at=datetime.fromisoformat(data["created_at"]),
            due_date=datetime.fromisoformat(data["due_date"]) if data.get("due_date") else None,
            tags=data.get("tags", []),
            metadata=data.get("metadata", {})
        )
    
    def is_overdue(self) -> bool:
        """Check if task is overdue."""
        if self.due_date and self.status not in (TaskStatus.COMPLETED, TaskStatus.CANCELLED):
            return datetime.now() > self.due_date
        return False


class TaskObserver(ABC):
    """Abstract base class for task observers."""
    
    @abstractmethod
    def on_task_created(self, task: Task) -> None:
        """Called when a task is created."""
        pass
    
    @abstractmethod
    def on_task_updated(self, task: Task) -> None:
        """Called when a task is updated."""
        pass
    
    @abstractmethod
    def on_task_deleted(self, task_id: int) -> None:
        """Called when a task is deleted."""
        pass


class ConsoleTaskObserver(TaskObserver):
    """Console-based task observer for logging."""
    
    def on_task_created(self, task: Task) -> None:
        logger.info(f"Task created: {task.title} (ID: {task.id})")
    
    def on_task_updated(self, task: Task) -> None:
        logger.info(f"Task updated: {task.title} (Status: {task.status.value})")
    
    def on_task_deleted(self, task_id: int) -> None:
        logger.info(f"Task deleted: ID {task_id}")


def retry(max_attempts: int = 3, delay: float = 1.0):
    """Decorator for retrying failed operations."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_exception = None
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last_exception = e
                    logger.warning(f"Attempt {attempt + 1} failed: {e}")
                    if attempt < max_attempts - 1:
                        import time
                        time.sleep(delay)
            raise last_exception
        return wrapper
    return decorator


class TaskManager:
    """Main task management class with thread-safe operations."""
    
    def __init__(self, storage_path: Optional[Path] = None):
        self._tasks: Dict[int, Task] = {}
        self._next_id: int = 1
        self._lock = threading.RLock()
        self._observers: List[TaskObserver] = []
        self._storage_path = storage_path
        self._task_queue = queue.PriorityQueue()
        
        if storage_path and storage_path.exists():
            self._load_tasks()
    
    def add_observer(self, observer: TaskObserver) -> None:
        """Add an observer for task events."""
        self._observers.append(observer)
    
    def remove_observer(self, observer: TaskObserver) -> None:
        """Remove an observer."""
        self._observers.remove(observer)
    
    def _notify_created(self, task: Task) -> None:
        """Notify observers of task creation."""
        for observer in self._observers:
            try:
                observer.on_task_created(task)
            except Exception as e:
                logger.error(f"Observer notification failed: {e}")
    
    def _notify_updated(self, task: Task) -> None:
        """Notify observers of task update."""
        for observer in self._observers:
            try:
                observer.on_task_updated(task)
            except Exception as e:
                logger.error(f"Observer notification failed: {e}")
    
    def _notify_deleted(self, task_id: int) -> None:
        """Notify observers of task deletion."""
        for observer in self._observers:
            try:
                observer.on_task_deleted(task_id)
            except Exception as e:
                logger.error(f"Observer notification failed: {e}")
    
    def create_task(
        self,
        title: str,
        description: str = "",
        priority: Priority = Priority.MEDIUM,
        due_date: Optional[datetime] = None,
        tags: Optional[List[str]] = None
    ) -> Task:
        """Create a new task."""
        with self._lock:
            task = Task(
                id=self._next_id,
                title=title,
                description=description,
                priority=priority,
                due_date=due_date,
                tags=tags or []
            )
            self._tasks[task.id] = task
            self._next_id += 1
            self._notify_created(task)
            
            # Add to priority queue
            priority_value = -task.priority.value  # Negative for max-heap behavior
            self._task_queue.put((priority_value, task.id))
            
            return task
    
    def get_task(self, task_id: int) -> Optional[Task]:
        """Get a task by ID."""
        with self._lock:
            return self._tasks.get(task_id)
    
    def update_task(self, task_id: int, **updates) -> Optional[Task]:
        """Update a task with given fields."""
        with self._lock:
            task = self._tasks.get(task_id)
            if not task:
                return None
            
            for key, value in updates.items():
                if hasattr(task, key):
                    setattr(task, key, value)
            
            self._notify_updated(task)
            return task
    
    def delete_task(self, task_id: int) -> bool:
        """Delete a task by ID."""
        with self._lock:
            if task_id in self._tasks:
                del self._tasks[task_id]
                self._notify_deleted(task_id)
                return True
            return False
    
    def get_all_tasks(self) -> List[Task]:
        """Get all tasks."""
        with self._lock:
            return list(self._tasks.values())
    
    def get_tasks_by_status(self, status: TaskStatus) -> List[Task]:
        """Get tasks filtered by status."""
        with self._lock:
            return [t for t in self._tasks.values() if t.status == status]
    
    def get_tasks_by_priority(self, priority: Priority) -> List[Task]:
        """Get tasks filtered by priority."""
        with self._lock:
            return [t for t in self._tasks.values() if t.priority == priority]
    
    def get_overdue_tasks(self) -> List[Task]:
        """Get all overdue tasks."""
        with self._lock:
            return [t for t in self._tasks.values() if t.is_overdue()]
    
    def search_tasks(self, query: str) -> List[Task]:
        """Search tasks by title or description."""
        query_lower = query.lower()
        with self._lock:
            return [
                t for t in self._tasks.values()
                if query_lower in t.title.lower() or query_lower in t.description.lower()
            ]
    
    def get_next_priority_task(self) -> Optional[Task]:
        """Get the next highest priority task."""
        while not self._task_queue.empty():
            _, task_id = self._task_queue.get()
            task = self._tasks.get(task_id)
            if task and task.status == TaskStatus.PENDING:
                return task
        return None
    
    @retry(max_attempts=3, delay=0.5)
    def _save_tasks(self) -> None:
        """Save tasks to storage."""
        if not self._storage_path:
            return
        
        with self._lock:
            data = {
                "next_id": self._next_id,
                "tasks": [t.to_dict() for t in self._tasks.values()]
            }
            with open(self._storage_path, 'w') as f:
                json.dump(data, f, indent=2)
    
    def _load_tasks(self) -> None:
        """Load tasks from storage."""
        if not self._storage_path or not self._storage_path.exists():
            return
        
        try:
            with open(self._storage_path, 'r') as f:
                data = json.load(f)
            
            self._next_id = data.get("next_id", 1)
            for task_data in data.get("tasks", []):
                task = Task.from_dict(task_data)
                self._tasks[task.id] = task
            
            logger.info(f"Loaded {len(self._tasks)} tasks from storage")
        except Exception as e:
            logger.error(f"Failed to load tasks: {e}")
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get task statistics."""
        with self._lock:
            total = len(self._tasks)
            by_status = {s.value: 0 for s in TaskStatus}
            by_priority = {p.name: 0 for p in Priority}
            overdue = 0
            
            for task in self._tasks.values():
                by_status[task.status.value] += 1
                by_priority[task.priority.name] += 1
                if task.is_overdue():
                    overdue += 1
            
            return {
                "total": total,
                "by_status": by_status,
                "by_priority": by_priority,
                "overdue": overdue
            }


async def process_tasks_async(manager: TaskManager, batch_size: int = 5) -> None:
    """Asynchronously process pending tasks in batches."""
    pending = manager.get_tasks_by_status(TaskStatus.PENDING)
    
    for i in range(0, len(pending), batch_size):
        batch = pending[i:i + batch_size]
        tasks = [process_single_task(manager, task) for task in batch]
        await asyncio.gather(*tasks)


async def process_single_task(manager: TaskManager, task: Task) -> None:
    """Process a single task asynchronously."""
    logger.info(f"Processing task: {task.title}")
    manager.update_task(task.id, status=TaskStatus.IN_PROGRESS)
    
    # Simulate async work
    await asyncio.sleep(0.1)
    
    manager.update_task(task.id, status=TaskStatus.COMPLETED)
    logger.info(f"Completed task: {task.title}")


def main():
    """Main entry point for the task manager demo."""
    # Create task manager with console observer
    manager = TaskManager()
    observer = ConsoleTaskObserver()
    manager.add_observer(observer)
    
    # Create sample tasks
    tasks = [
        ("Implement user authentication", "Add OAuth2 support", Priority.HIGH),
        ("Write unit tests", "Cover all edge cases", Priority.MEDIUM),
        ("Update documentation", "Add API reference", Priority.LOW),
        ("Fix critical bug", "Memory leak in worker", Priority.CRITICAL),
        ("Refactor database layer", "Use async queries", Priority.MEDIUM),
    ]
    
    for title, desc, priority in tasks:
        due_date = datetime.now() + timedelta(days=priority.value)
        manager.create_task(title, desc, priority, due_date)
    
    # Display statistics
    stats = manager.get_statistics()
    print("\n=== Task Statistics ===")
    print(f"Total tasks: {stats['total']}")
    print(f"By status: {stats['by_status']}")
    print(f"By priority: {stats['by_priority']}")
    
    # Search tasks
    results = manager.search_tasks("test")
    print(f"\nSearch results for 'test': {len(results)} found")
    
    # Process tasks asynchronously
    print("\n=== Processing Tasks ===")
    asyncio.run(process_tasks_async(manager))
    
    # Final statistics
    stats = manager.get_statistics()
    print("\n=== Final Statistics ===")
    print(f"Completed: {stats['by_status']['completed']}")
    print(f"Pending: {stats['by_status']['pending']}")


if __name__ == "__main__":
    main()
