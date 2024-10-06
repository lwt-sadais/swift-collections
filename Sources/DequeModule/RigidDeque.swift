//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if !COLLECTIONS_SINGLE_MODULE
import InternalCollectionsUtilities
import Future
#endif

@frozen
public struct RigidDeque<Element: ~Copyable>: ~Copyable {
  @usableFromInline
  internal typealias _Slot = _DequeSlot

  @usableFromInline
  internal typealias _UnsafeHandle = _UnsafeDequeHandle<Element>

  @usableFromInline
  internal var _handle: _UnsafeHandle

  @inlinable
  internal init(_handle: consuming _UnsafeHandle) {
    self._handle = _handle
  }

  @inlinable
  public init(capacity: Int) {
    self.init(_handle: .allocate(capacity: capacity))
  }

  deinit {
    _handle.dispose()
  }
}

extension RigidDeque: @unchecked Sendable where Element: Sendable & ~Copyable {}

extension RigidDeque where Element: ~Copyable {
#if COLLECTIONS_INTERNAL_CHECKS
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _checkInvariants() {
    _handle._checkInvariants()
  }
#else
  @inlinable @inline(__always)
  internal func _checkInvariants() {}
#endif // COLLECTIONS_INTERNAL_CHECKS
}

extension RigidDeque where Element: ~Copyable {
  @usableFromInline
  internal var description: String {
    _handle.description
  }
}

public struct _DequeBorrowingIterator<Element: ~Copyable>: BorrowingIteratorProtocol, ~Escapable {
  @usableFromInline
  internal typealias _UnsafeHandle = _UnsafeDequeHandle<Element>

  @usableFromInline
  internal let _segments: _UnsafeDequeSegments<Element>

  @usableFromInline
  internal var _offset: Int

  @inlinable
  internal init<T: ~Copyable>(
    _unsafeSegments segments: _UnsafeDequeSegments<Element>,
    startOffset: Int,
    owner: borrowing T
  ) {
    self._segments = segments
    self._offset = startOffset
  }

  @inlinable
  internal init(_for handle: borrowing _UnsafeHandle, startOffset: Int) {
    self.init(_unsafeSegments: handle.segments(), startOffset: startOffset, owner: handle)
  }

  @inlinable
  public mutating func nextChunk(
    maximumCount: Int
  ) -> dependsOn(scoped self) Span<Element> {
    precondition(maximumCount > 0)
    if _offset < _segments.first.count {
      let d = Swift.min(maximumCount, _segments.first.count - _offset)
      let slice = _segments.first.extracting(_offset ..< _offset + d)
      _offset += d
      return Span(_unsafeElements: slice)
    }
    guard let second = _segments.second else {
      return Span(_unsafeElements: UnsafeBufferPointer._empty)
    }
    let o = _offset - _segments.first.count
    let d = Swift.min(maximumCount, second.count - o)
    let slice = second.extracting(o ..< o + d)
    _offset += d
    return Span(_unsafeElements: slice)
  }
}

extension RigidDeque: RandomAccessContainer where Element: ~Copyable {
  public typealias BorrowingIterator = _DequeBorrowingIterator<Element>

  public func startBorrowingIteration() -> BorrowingIterator {
    _handle.startBorrowingIteration()
  }

  public func startBorrowingIteration(from start: Int) -> BorrowingIterator {
    _handle.startBorrowingIteration(from: start)
  }

  public typealias Index = Int

  @inlinable
  public var isEmpty: Bool { _handle.count == 0 }

  @inlinable
  public var count: Int { _handle.count }

  @inlinable
  public var startIndex: Int { 0 }

  @inlinable
  public var endIndex: Int { _handle.count }

  @inlinable
  public subscript(position: Int) -> Element {
    @inline(__always)
    _read {
      yield _handle[offset: position]
    }
    @inline(__always)
    _modify {
      yield &_handle[offset: position]
    }
  }

  public func index(at position: borrowing BorrowingIterator) -> Int {
    precondition(_handle.segments().isIdentical(to: position._segments))
    return position._offset
  }
}

extension RigidDeque where Element: ~Copyable {
  @inlinable
  public var capacity: Int { _handle.capacity }

  @inlinable
  public var freeCapacity: Int { capacity - count }

  @inlinable
  public var isFull: Bool { count == capacity }

  @inlinable
  public mutating func resize(to newCapacity: Int) {
    _handle.reallocate(capacity: newCapacity)
  }
}

extension RigidDeque where Element: ~Copyable {
  @inlinable
  public mutating func append(_ newElement: consuming Element) {
    precondition(!isFull, "RigidDeque is full")
    _handle.uncheckedAppend(newElement)
  }

  @inlinable
  public mutating func prepend(_ newElement: consuming Element) {
    precondition(!isFull, "RigidDeque is full")
    _handle.uncheckedPrepend(newElement)
  }

  @inlinable
  public mutating func insert(_ newElement: consuming Element, at index: Int) {
    precondition(!isFull, "RigidDeque is full")
    precondition(index >= 0 && index <= count,
                 "Can't insert element at invalid index")
    _handle.uncheckedInsert(newElement, at: index)
  }
}

extension RigidDeque where Element: ~Copyable {
  @inlinable
  @discardableResult
  public mutating func remove(at index: Int) -> Element {
    precondition(index >= 0 && index < count,
                 "Can't remove element at invalid index")
    return _handle.uncheckedRemove(at: index)
  }

  @inlinable
  public mutating func removeSubrange(_ bounds: Range<Int>) {
    precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count,
                 "Index range out of bounds")
    _handle.uncheckedRemove(offsets: bounds)
  }

  @inlinable
  @discardableResult
  public mutating func removeFirst() -> Element {
    precondition(!isEmpty, "Cannot remove first element of an empty RigidDeque")
    return _handle.uncheckedRemoveFirst()
  }

  @inlinable
  @discardableResult
  public mutating func removeLast() -> Element {
    precondition(!isEmpty, "Cannot remove last element of an empty RigidDeque")
    return _handle.uncheckedRemoveLast()
  }

  @inlinable
  public mutating func removeFirst(_ n: Int) {
    precondition(n >= 0, "Can't remove a negative number of elements")
    precondition(n <= count, "Can't remove more elements than there are in a RigidDeque")
    _handle.uncheckedRemoveFirst(n)
  }

  @inlinable
  public mutating func removeLast(_ n: Int) {
    precondition(n >= 0, "Can't remove a negative number of elements")
    precondition(n <= count, "Can't remove more elements than there are in a RigidDeque")
    _handle.uncheckedRemoveLast(n)
  }

  @inlinable
  public mutating func removeAll() {
    _handle.uncheckedRemoveAll()
  }

  @inlinable
  public mutating func popFirst() -> Element? {
    guard !isEmpty else { return nil }
    return _handle.uncheckedRemoveFirst()
  }

  @inlinable
  public mutating func popLast() -> Element? {
    guard !isEmpty else { return nil }
    return _handle.uncheckedRemoveLast()
  }
}

extension RigidDeque {
  @inlinable
  internal func _copy() -> Self {
    RigidDeque(_handle: _handle.allocateCopy())
  }

  @inlinable
  internal func _copy(capacity: Int) -> Self {
    RigidDeque(_handle: _handle.allocateCopy(capacity: capacity))
  }
}
