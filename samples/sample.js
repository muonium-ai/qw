/**
 * Sample JavaScript Module for QW Editor Testing
 * A comprehensive example demonstrating JavaScript syntax highlighting.
 * 
 * This module implements a state management system with:
 * - Reactive state updates
 * - Event handling
 * - Middleware support
 * - Persistence layer
 */

// Constants and Configuration
const CONFIG = {
    DEBUG: true,
    MAX_HISTORY: 100,
    DEBOUNCE_MS: 300,
    STORAGE_KEY: 'app_state',
    VERSION: '1.0.0'
};

// Utility Functions
const utils = {
    /**
     * Deep clone an object
     * @param {Object} obj - Object to clone
     * @returns {Object} Cloned object
     */
    deepClone(obj) {
        if (obj === null || typeof obj !== 'object') {
            return obj;
        }
        
        if (Array.isArray(obj)) {
            return obj.map(item => this.deepClone(item));
        }
        
        const cloned = {};
        for (const [key, value] of Object.entries(obj)) {
            cloned[key] = this.deepClone(value);
        }
        return cloned;
    },
    
    /**
     * Debounce a function
     * @param {Function} fn - Function to debounce
     * @param {number} delay - Delay in milliseconds
     * @returns {Function} Debounced function
     */
    debounce(fn, delay = CONFIG.DEBOUNCE_MS) {
        let timeoutId = null;
        return function(...args) {
            clearTimeout(timeoutId);
            timeoutId = setTimeout(() => fn.apply(this, args), delay);
        };
    },
    
    /**
     * Generate a unique ID
     * @returns {string} Unique identifier
     */
    generateId() {
        return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    },
    
    /**
     * Check if two values are deeply equal
     * @param {*} a - First value
     * @param {*} b - Second value
     * @returns {boolean} True if equal
     */
    isEqual(a, b) {
        if (a === b) return true;
        if (typeof a !== typeof b) return false;
        if (typeof a !== 'object' || a === null || b === null) return false;
        
        const keysA = Object.keys(a);
        const keysB = Object.keys(b);
        
        if (keysA.length !== keysB.length) return false;
        
        return keysA.every(key => this.isEqual(a[key], b[key]));
    }
};

// Event Emitter Class
class EventEmitter {
    constructor() {
        this._events = new Map();
        this._maxListeners = 10;
    }
    
    /**
     * Subscribe to an event
     * @param {string} event - Event name
     * @param {Function} listener - Event listener
     * @returns {Function} Unsubscribe function
     */
    on(event, listener) {
        if (!this._events.has(event)) {
            this._events.set(event, []);
        }
        
        const listeners = this._events.get(event);
        
        if (CONFIG.DEBUG && listeners.length >= this._maxListeners) {
            console.warn(`MaxListenersExceeded: ${event} has ${listeners.length} listeners`);
        }
        
        listeners.push(listener);
        
        return () => this.off(event, listener);
    }
    
    /**
     * Subscribe to an event once
     * @param {string} event - Event name
     * @param {Function} listener - Event listener
     */
    once(event, listener) {
        const wrapper = (...args) => {
            this.off(event, wrapper);
            listener.apply(this, args);
        };
        this.on(event, wrapper);
    }
    
    /**
     * Unsubscribe from an event
     * @param {string} event - Event name
     * @param {Function} listener - Event listener
     */
    off(event, listener) {
        const listeners = this._events.get(event);
        if (listeners) {
            const index = listeners.indexOf(listener);
            if (index > -1) {
                listeners.splice(index, 1);
            }
        }
    }
    
    /**
     * Emit an event
     * @param {string} event - Event name
     * @param {...*} args - Event arguments
     */
    emit(event, ...args) {
        const listeners = this._events.get(event);
        if (listeners) {
            listeners.forEach(listener => {
                try {
                    listener.apply(this, args);
                } catch (error) {
                    console.error(`Error in event listener for ${event}:`, error);
                }
            });
        }
    }
    
    /**
     * Remove all listeners
     * @param {string} [event] - Optional event name
     */
    removeAllListeners(event) {
        if (event) {
            this._events.delete(event);
        } else {
            this._events.clear();
        }
    }
}

// State Container Class
class Store extends EventEmitter {
    /**
     * Create a new store
     * @param {Object} initialState - Initial state
     * @param {Object} options - Store options
     */
    constructor(initialState = {}, options = {}) {
        super();
        
        this._state = utils.deepClone(initialState);
        this._history = [];
        this._historyIndex = -1;
        this._middleware = [];
        this._computed = new Map();
        this._watchers = new Map();
        this._options = {
            enableHistory: true,
            maxHistory: CONFIG.MAX_HISTORY,
            persist: false,
            ...options
        };
        
        if (this._options.persist) {
            this._loadFromStorage();
        }
        
        this._saveToStorage = utils.debounce(this._saveToStorage.bind(this));
    }
    
    /**
     * Get the current state
     * @returns {Object} Current state
     */
    getState() {
        return utils.deepClone(this._state);
    }
    
    /**
     * Get a specific value from state
     * @param {string} path - Dot-notation path
     * @returns {*} Value at path
     */
    get(path) {
        return path.split('.').reduce((obj, key) => obj?.[key], this._state);
    }
    
    /**
     * Set state with an update object or function
     * @param {Object|Function} update - State update
     */
    setState(update) {
        const prevState = utils.deepClone(this._state);
        
        let nextState;
        if (typeof update === 'function') {
            nextState = update(prevState);
        } else {
            nextState = { ...this._state, ...update };
        }
        
        // Apply middleware
        for (const middleware of this._middleware) {
            const result = middleware(prevState, nextState);
            if (result === false) {
                return; // Middleware rejected update
            }
            if (result !== undefined && result !== true) {
                nextState = result;
            }
        }
        
        this._state = nextState;
        
        // Track history
        if (this._options.enableHistory) {
            this._addToHistory(prevState);
        }
        
        // Persist
        if (this._options.persist) {
            this._saveToStorage();
        }
        
        // Emit change event
        this.emit('change', this._state, prevState);
        
        // Notify watchers
        this._notifyWatchers(prevState);
    }
    
    /**
     * Add middleware
     * @param {Function} middleware - Middleware function
     */
    use(middleware) {
        this._middleware.push(middleware);
    }
    
    /**
     * Register a computed property
     * @param {string} name - Property name
     * @param {Function} getter - Getter function
     */
    computed(name, getter) {
        this._computed.set(name, getter);
    }
    
    /**
     * Get a computed property
     * @param {string} name - Property name
     * @returns {*} Computed value
     */
    getComputed(name) {
        const getter = this._computed.get(name);
        if (getter) {
            return getter(this._state);
        }
        return undefined;
    }
    
    /**
     * Watch for changes to a specific path
     * @param {string} path - Dot-notation path
     * @param {Function} callback - Callback function
     * @returns {Function} Unwatch function
     */
    watch(path, callback) {
        if (!this._watchers.has(path)) {
            this._watchers.set(path, []);
        }
        this._watchers.get(path).push(callback);
        
        return () => {
            const watchers = this._watchers.get(path);
            const index = watchers.indexOf(callback);
            if (index > -1) {
                watchers.splice(index, 1);
            }
        };
    }
    
    /**
     * Notify watchers of state changes
     * @param {Object} prevState - Previous state
     * @private
     */
    _notifyWatchers(prevState) {
        for (const [path, watchers] of this._watchers) {
            const prevValue = path.split('.').reduce((obj, key) => obj?.[key], prevState);
            const currValue = this.get(path);
            
            if (!utils.isEqual(prevValue, currValue)) {
                watchers.forEach(cb => cb(currValue, prevValue));
            }
        }
    }
    
    /**
     * Add state to history
     * @param {Object} state - State to add
     * @private
     */
    _addToHistory(state) {
        // Remove any forward history
        if (this._historyIndex < this._history.length - 1) {
            this._history = this._history.slice(0, this._historyIndex + 1);
        }
        
        this._history.push(state);
        
        // Limit history size
        if (this._history.length > this._options.maxHistory) {
            this._history.shift();
        } else {
            this._historyIndex++;
        }
    }
    
    /**
     * Undo the last state change
     * @returns {boolean} True if undo was performed
     */
    undo() {
        if (this._historyIndex >= 0) {
            this._state = utils.deepClone(this._history[this._historyIndex]);
            this._historyIndex--;
            this.emit('change', this._state);
            return true;
        }
        return false;
    }
    
    /**
     * Redo the last undone state change
     * @returns {boolean} True if redo was performed
     */
    redo() {
        if (this._historyIndex < this._history.length - 2) {
            this._historyIndex++;
            this._state = utils.deepClone(this._history[this._historyIndex + 1]);
            this.emit('change', this._state);
            return true;
        }
        return false;
    }
    
    /**
     * Save state to local storage
     * @private
     */
    _saveToStorage() {
        try {
            localStorage.setItem(CONFIG.STORAGE_KEY, JSON.stringify(this._state));
        } catch (error) {
            console.error('Failed to save state:', error);
        }
    }
    
    /**
     * Load state from local storage
     * @private
     */
    _loadFromStorage() {
        try {
            const saved = localStorage.getItem(CONFIG.STORAGE_KEY);
            if (saved) {
                this._state = JSON.parse(saved);
            }
        } catch (error) {
            console.error('Failed to load state:', error);
        }
    }
    
    /**
     * Reset state to initial value
     * @param {Object} initialState - New initial state
     */
    reset(initialState = {}) {
        this._state = utils.deepClone(initialState);
        this._history = [];
        this._historyIndex = -1;
        this.emit('reset', this._state);
    }
}

// Action creators
const createAction = (type, payloadCreator = x => x) => {
    const actionCreator = (...args) => ({
        type,
        payload: payloadCreator(...args),
        timestamp: Date.now()
    });
    actionCreator.type = type;
    return actionCreator;
};

// Async action helper
const createAsyncAction = (type, asyncFn) => {
    return async (store, ...args) => {
        store.emit('action:start', type);
        try {
            const result = await asyncFn(...args);
            store.emit('action:success', type, result);
            return result;
        } catch (error) {
            store.emit('action:error', type, error);
            throw error;
        } finally {
            store.emit('action:end', type);
        }
    };
};

// Logging middleware
const loggerMiddleware = (prevState, nextState) => {
    if (CONFIG.DEBUG) {
        console.group('State Update');
        console.log('Previous:', prevState);
        console.log('Next:', nextState);
        console.groupEnd();
    }
    return true;
};

// Validation middleware factory
const createValidator = (rules) => {
    return (prevState, nextState) => {
        for (const [path, validate] of Object.entries(rules)) {
            const value = path.split('.').reduce((obj, key) => obj?.[key], nextState);
            if (!validate(value)) {
                console.error(`Validation failed for ${path}`);
                return false;
            }
        }
        return true;
    };
};

// Example usage and demo
function demo() {
    // Create store with initial state
    const store = new Store({
        user: null,
        todos: [],
        settings: {
            theme: 'light',
            notifications: true
        },
        loading: false
    }, { persist: true });
    
    // Add middleware
    store.use(loggerMiddleware);
    store.use(createValidator({
        'settings.theme': v => ['light', 'dark'].includes(v)
    }));
    
    // Add computed property
    store.computed('completedTodos', state => 
        state.todos.filter(t => t.completed).length
    );
    
    // Watch for theme changes
    store.watch('settings.theme', (newTheme, oldTheme) => {
        console.log(`Theme changed from ${oldTheme} to ${newTheme}`);
    });
    
    // Subscribe to all changes
    const unsubscribe = store.on('change', (state) => {
        console.log('State updated:', state);
    });
    
    // Make some updates
    store.setState({ loading: true });
    
    store.setState(state => ({
        ...state,
        user: { id: 1, name: 'John Doe' },
        loading: false
    }));
    
    store.setState(state => ({
        ...state,
        todos: [
            ...state.todos,
            { id: utils.generateId(), text: 'Learn JavaScript', completed: false }
        ]
    }));
    
    console.log('Completed todos:', store.getComputed('completedTodos'));
    
    // Test undo/redo
    store.undo();
    console.log('After undo:', store.getState());
    
    store.redo();
    console.log('After redo:', store.getState());
    
    // Cleanup
    unsubscribe();
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { Store, EventEmitter, utils, createAction, createAsyncAction };
}

// Run demo if executed directly
if (typeof require !== 'undefined' && require.main === module) {
    demo();
}
