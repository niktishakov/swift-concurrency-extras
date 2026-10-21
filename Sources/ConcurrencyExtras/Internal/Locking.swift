#if canImport(Darwin) || os(WASI)
  import Foundation

  typealias _Lock = NSLock
  typealias _RecursiveLock = NSRecursiveLock

  #if !(os(iOS) || os(macOS) || os(tvOS) || os(watchOS))
    extension NSLock {
      func withLock<R>(_ body: () throws -> R) rethrows -> R {
        self.lock()
        defer { self.unlock() }
        return try body()
      }
    }
  #endif
#else
  #if canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #elseif canImport(Android)
    import Android
  #elseif os(Windows)
    import WinSDK
  #endif
  import Synchronization

  /// A non-recursive lock, like `NSLock`. A class, so escaping closures can capture it.
  final class _Lock: Sendable {
    private let mutex = Mutex(())

    func withLock(_ body: () -> Void) {
      self.mutex.withLock { _ in body() }
    }
  }

  /// A recursive lock, like `NSRecursiveLock`, that does not depend on Foundation.
  final class _RecursiveLock: @unchecked Sendable {
    #if os(Windows)
      private let mutex = UnsafeMutablePointer<CRITICAL_SECTION>.allocate(capacity: 1)
    #else
      private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    #endif

    init() {
      #if os(Windows)
        InitializeCriticalSection(self.mutex)
      #else
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(self.mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
      #endif
    }

    deinit {
      #if os(Windows)
        DeleteCriticalSection(self.mutex)
        self.mutex.deallocate()
      #else
        pthread_mutex_destroy(self.mutex)
        self.mutex.deallocate()
      #endif
    }

    func lock() {
      #if os(Windows)
        EnterCriticalSection(self.mutex)
      #else
        pthread_mutex_lock(self.mutex)
      #endif
    }

    func unlock() {
      #if os(Windows)
        LeaveCriticalSection(self.mutex)
      #else
        pthread_mutex_unlock(self.mutex)
      #endif
    }

    @discardableResult
    func sync<R>(work: () throws -> R) rethrows -> R {
      self.lock()
      defer { self.unlock() }
      return try work()
    }
  }
#endif
