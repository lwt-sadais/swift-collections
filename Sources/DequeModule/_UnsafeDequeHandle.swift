//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2021 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if !COLLECTIONS_SINGLE_MODULE
import InternalCollectionsUtilities
#endif

@frozen
@usableFromInline
internal struct _UnsafeDequeHandle<Element: ~Copyable>: ~Copyable {
  @usableFromInline
  internal let _buffer: UnsafeMutableBufferPointer<Element>

  @usableFromInline
  internal var count: Int

  @usableFromInline
  internal var startSlot: _DequeSlot

  @inlinable
  internal static func allocate(
    capacity: Int
  ) -> Self {
    Self(
      _storage: capacity > 0 ? .allocate(capacity: capacity) : ._empty,
      count: 0,
      startSlot: .zero)
  }

  @inlinable
  internal init(
    _storage: UnsafeMutableBufferPointer<Element>,
    count: Int,
    startSlot: _DequeSlot
  ) {
    self._buffer = _storage
    self.count = count
    self.startSlot = startSlot
  }

  @inlinable
  internal consuming func dispose() {
    _checkInvariants()
    self.mutableSegments().deinitialize()
    _buffer.deallocate()
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable @inline(__always)
  internal var _baseAddress: UnsafeMutablePointer<Element> {
    _buffer.baseAddress.unsafelyUnwrapped
  }

  @inlinable
  internal var capacity: Int {
    _buffer.count
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @usableFromInline
  internal var description: String {
    "(capacity: \(capacity), count: \(count), startSlot: \(startSlot))"
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
#if COLLECTIONS_INTERNAL_CHECKS
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _checkInvariants() {
    precondition(capacity >= 0)
    precondition(count >= 0 && count <= capacity)
    precondition(startSlot.position >= 0 && startSlot.position <= capacity)
  }
#else
  @inlinable @inline(__always)
  internal func _checkInvariants() {}
#endif // COLLECTIONS_INTERNAL_CHECKS
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @usableFromInline
  internal typealias Slot = _DequeSlot

  @inlinable @inline(__always)
  internal func ptr(at slot: Slot) -> UnsafePointer<Element> {
    assert(slot.position >= 0 && slot.position <= capacity)
    return UnsafePointer(_baseAddress + slot.position)
  }

  @inlinable @inline(__always)
  internal mutating func mutablePtr(
    at slot: Slot
  ) -> UnsafeMutablePointer<Element> {
    assert(slot.position >= 0 && slot.position <= capacity)
    return _baseAddress + slot.position
  }

  @inlinable @inline(__always)
  internal var mutableBuffer: UnsafeMutableBufferPointer<Element> {
    mutating get {
      _buffer
    }
  }

  @inlinable
  internal func buffer(for range: Range<Slot>) -> UnsafeBufferPointer<Element> {
    assert(range.upperBound.position <= capacity)
    return .init(_buffer._extracting(unchecked: range._offsets))
  }

  @inlinable @inline(__always)
  internal mutating func mutableBuffer(for range: Range<Slot>) -> UnsafeMutableBufferPointer<Element> {
    assert(range.upperBound.position <= capacity)
    return _buffer._extracting(unchecked: range._offsets)
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  /// The slot immediately following the last valid one. (`endSlot` refers to
  /// the valid slot corresponding to `endIndex`, which is a different thing
  /// entirely.)
  @inlinable
  @inline(__always)
  internal var limSlot: Slot {
    Slot(at: capacity)
  }

  @inlinable
  internal func slot(after slot: Slot) -> Slot {
    assert(slot.position < capacity)
    let position = slot.position + 1
    if position >= capacity {
      return Slot(at: 0)
    }
    return Slot(at: position)
  }

  @inlinable
  internal func slot(before slot: Slot) -> Slot {
    assert(slot.position < capacity)
    if slot.position == 0 { return Slot(at: capacity - 1) }
    return Slot(at: slot.position - 1)
  }

  @inlinable
  internal func slot(_ slot: Slot, offsetBy delta: Int) -> Slot {
    assert(slot.position <= capacity)
    let position = slot.position + delta
    if delta >= 0 {
      if position >= capacity { return Slot(at: position - capacity) }
    } else {
      if position < 0 { return Slot(at: position + capacity) }
    }
    return Slot(at: position)
  }

  @inlinable
  @inline(__always)
  internal var endSlot: Slot {
    slot(startSlot, offsetBy: count)
  }

  /// Return the storage slot corresponding to the specified offset, which may
  /// or may not address an existing element.
  @inlinable
  internal func slot(forOffset offset: Int) -> Slot {
    assert(offset >= 0)
    assert(offset <= capacity) // Not `count`!

    // Note: The use of wrapping addition/subscription is justified here by the
    // fact that `offset` is guaranteed to fall in the range `0 ..< capacity`.
    // Eliminating the overflow checks leads to a measurable speedup for
    // random-access subscript operations. (Up to 2x on some microbenchmarks.)
    let position = startSlot.position &+ offset
    guard position < capacity else { return Slot(at: position &- capacity) }
    return Slot(at: position)
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal func segments() -> _UnsafeWrappedBuffer<Element> {
    guard _buffer.baseAddress != nil else {
      return .init(._empty)
    }
    let wrap = capacity - startSlot.position
    if count <= wrap {
      return .init(start: ptr(at: startSlot), count: count)
    }
    return .init(first: ptr(at: startSlot), count: wrap,
                 second: ptr(at: .zero), count: count - wrap)
  }

  @inlinable
  internal func segments(
    forOffsets offsets: Range<Int>
  ) -> _UnsafeWrappedBuffer<Element> {
    assert(offsets.lowerBound >= 0 && offsets.upperBound <= count)
    guard _buffer.baseAddress != nil else {
      return .init(._empty)
    }
    let lower = slot(forOffset: offsets.lowerBound)
    let upper = slot(forOffset: offsets.upperBound)
    if offsets.count == 0 || lower < upper {
      return .init(start: ptr(at: lower), count: offsets.count)
    }
    return .init(first: ptr(at: lower), count: capacity - lower.position,
                 second: ptr(at: .zero), count: upper.position)
  }

  @inlinable
  @inline(__always)
  internal mutating func mutableSegments() -> _UnsafeMutableWrappedBuffer<Element> {
    .init(mutating: segments())
  }

  @inlinable
  @inline(__always)
  internal mutating func mutableSegments(
    forOffsets range: Range<Int>
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    .init(mutating: segments(forOffsets: range))
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func availableSegments() -> _UnsafeMutableWrappedBuffer<Element> {
    guard _buffer.baseAddress != nil else {
      return .init(._empty)
    }
    let endSlot = self.endSlot
    guard count < capacity else { return .init(start: mutablePtr(at: endSlot), count: 0) }
    if endSlot < startSlot { return .init(mutableBuffer(for: endSlot ..< startSlot)) }
    return .init(mutableBuffer(for: endSlot ..< limSlot),
                 mutableBuffer(for: .zero ..< startSlot))
  }
}

extension _UnsafeDequeHandle {
  @inlinable
  @discardableResult
  internal mutating func initialize(
    at start: Slot,
    from source: UnsafeBufferPointer<Element>
  ) -> Slot {
    assert(start.position + source.count <= capacity)
    guard source.count > 0 else { return start }
    mutablePtr(at: start).initialize(from: source.baseAddress!, count: source.count)
    return Slot(at: start.position + source.count)
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func moveInitialize(
    at start: Slot,
    from source: UnsafeMutableBufferPointer<Element>
  ) -> Slot {
    assert(start.position + source.count <= capacity)
    guard source.count > 0 else { return start }
    mutablePtr(at: start)
      .moveInitialize(from: source.baseAddress!, count: source.count)
    return Slot(at: start.position + source.count)
  }

  @inlinable
  @inline(__always)
  @discardableResult
  internal mutating func move(
    from source: Slot,
    to target: Slot,
    count: Int
  ) -> (source: Slot, target: Slot) {
    assert(count >= 0)
    assert(source.position + count <= self.capacity)
    assert(target.position + count <= self.capacity)
    guard count > 0 else { return (source, target) }
    mutablePtr(at: target)
      .moveInitialize(from: mutablePtr(at: source), count: count)
    return (slot(source, offsetBy: count), slot(target, offsetBy: count))
  }
}



extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal func withUnsafeSegment<R>(
    startingAt start: Int,
    maximumCount: Int?,
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> (end: Int, result: R) {
    assert(start <= count)
    guard start < count else {
      return try (count, body(UnsafeBufferPointer(start: nil, count: 0)))
    }
    let endSlot = self.endSlot

    let segmentStart = self.slot(forOffset: start)
    let segmentEnd = segmentStart < endSlot ? endSlot : limSlot
    let count = Swift.min(maximumCount ?? Int.max, segmentEnd.position - segmentStart.position)
    let result = try body(UnsafeBufferPointer(start: ptr(at: segmentStart), count: count))
    return (start + count, result)
  }
}

// MARK: Replacement

extension _UnsafeDequeHandle where Element: ~Copyable {
  /// Replace the elements in `range` with `newElements`. The deque's count must
  /// not change as a result of calling this function.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func uncheckedReplaceInPlace<C: Collection>(
    inOffsets range: Range<Int>,
    with newElements: C
  ) where C.Element == Element {
    assert(range.upperBound <= count)
    assert(newElements.count == range.count)
    guard !range.isEmpty else { return }
    let target = mutableSegments(forOffsets: range)
    target.assign(from: newElements)
  }
}

// MARK: Appending

extension _UnsafeDequeHandle where Element: ~Copyable {
  /// Append `element` to this buffer. The buffer must have enough free capacity
  /// to insert one new element.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func uncheckedAppend(_ element: consuming Element) {
    assert(count < capacity)
    mutablePtr(at: endSlot).initialize(to: element)
    count += 1
  }
}

extension _UnsafeDequeHandle {
  /// Append the contents of `source` to this buffer. The buffer must have
  /// enough free capacity to insert the new elements.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func uncheckedAppend(contentsOf source: UnsafeBufferPointer<Element>) {
    assert(count + source.count <= capacity)
    guard source.count > 0 else { return }
    let c = self.count
    count += source.count
    let gap = mutableSegments(forOffsets: c ..< count)
    gap.initialize(from: source)
  }
}

// MARK: Prepending

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func uncheckedPrepend(_ element: consuming Element) {
    assert(count < capacity)
    let slot = self.slot(before: startSlot)
    mutablePtr(at: slot).initialize(to: element)
    startSlot = slot
    count += 1
  }
}

extension _UnsafeDequeHandle {
  /// Prepend the contents of `source` to this buffer. The buffer must have
  /// enough free capacity to insert the new elements.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func uncheckedPrepend(contentsOf source: UnsafeBufferPointer<Element>) {
    assert(count + source.count <= capacity)
    guard source.count > 0 else { return }
    let oldStart = startSlot
    let newStart = self.slot(startSlot, offsetBy: -source.count)
    startSlot = newStart
    count += source.count

    let gap = mutableWrappedBuffer(between: newStart, and: oldStart)
    gap.initialize(from: source)
  }
}

// MARK: Insertion

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func uncheckedInsert(
    _ newElement: consuming Element, at offset: Int
  ) {
    assert(count < capacity)
    if offset == 0 {
      uncheckedPrepend(newElement)
      return
    }
    if offset == count {
      uncheckedAppend(newElement)
      return
    }
    let gap = openGap(ofSize: 1, atOffset: offset)
    assert(gap.first.count == 1)
    gap.first.baseAddress!.initialize(to: newElement)
  }
}

extension _UnsafeDequeHandle {
  /// Insert all elements from `newElements` into this deque, starting at
  /// `offset`.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  ///
  /// - Parameter newElements: The elements to insert.
  /// - Parameter newCount: Must be equal to `newElements.count`. Used to
  ///    prevent calling `count` more than once.
  /// - Parameter offset: The desired offset from the start at which to place
  ///    the first element.
  @inlinable
  internal mutating func uncheckedInsert<C: Collection>(
    contentsOf newElements: __owned C,
    count newCount: Int,
    atOffset offset: Int
  ) where C.Element == Element {
    assert(offset <= count)
    assert(newElements.count == newCount)
    guard newCount > 0 else { return }
    let gap = openGap(ofSize: newCount, atOffset: offset)
    gap.initialize(from: newElements)
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func mutableWrappedBuffer(
    between start: Slot,
    and end: Slot
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    assert(start.position <= capacity)
    assert(end.position <= capacity)
    if start < end {
      return .init(
        start: mutablePtr(at: start),
        count: end.position - start.position)
    }
    return .init(
      first: mutablePtr(at: start), count: capacity - start.position,
      second: mutablePtr(at: .zero), count: end.position)
  }

  /// Slide elements around so that there is a gap of uninitialized slots of
  /// size `gapSize` starting at `offset`, and return a (potentially wrapped)
  /// buffer holding the newly inserted slots.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  ///
  /// - Parameter gapSize: The number of uninitialized slots to create.
  /// - Parameter offset: The offset from the start at which the uninitialized
  ///    slots should start.
  @inlinable
  internal mutating func openGap(
    ofSize gapSize: Int,
    atOffset offset: Int
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    assert(offset >= 0 && offset <= self.count)
    assert(self.count + gapSize <= capacity)
    assert(gapSize > 0)

    let headCount = offset
    let tailCount = count - offset
    if tailCount <= headCount {
      // Open the gap by sliding elements to the right.

      let originalEnd = self.slot(startSlot, offsetBy: count)
      let newEnd = self.slot(startSlot, offsetBy: count + gapSize)
      let gapStart = self.slot(forOffset: offset)
      let gapEnd = self.slot(gapStart, offsetBy: gapSize)

      let sourceIsContiguous = gapStart <= originalEnd.orIfZero(capacity)
      let targetIsContiguous = gapEnd <= newEnd.orIfZero(capacity)

      if sourceIsContiguous && targetIsContiguous {
        // No need to deal with wrapping; we just need to slide
        // elements after the gap.

        // Illustrated steps: (underscores mark eventual gap position)
        //
        //   0) ....ABCDE̲F̲G̲H.....      EFG̲H̲.̲........ABCD      .̲.......ABCDEFGH̲.̲
        //   1) ....ABCD.̲.̲.̲EFGH..      EF.̲.̲.̲GH......ABCD      .̲H......ABCDEFG.̲.̲
        move(from: gapStart, to: gapEnd, count: tailCount)
      } else if targetIsContiguous {
        // The gap itself will be wrapped.

        // Illustrated steps: (underscores mark eventual gap position)
        //
        //   0) E̲FGH.........ABC̲D̲
        //   1) .̲..EFGH......ABC̲D̲
        //   2) .̲CDEFGH......AB.̲.̲
        assert(startSlot > originalEnd.orIfZero(capacity))
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: originalEnd.position)
        move(from: gapStart, to: gapEnd, count: capacity - gapStart.position)
      } else if sourceIsContiguous {
        // Opening the gap pushes subsequent elements across the wrap.

        // Illustrated steps: (underscores mark eventual gap position)
        //
        //   0) ........ABC̲D̲E̲FGH.
        //   1) GH......ABC̲D̲E̲F...
        //   2) GH......AB.̲.̲.̲CDEF
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: newEnd.position)
        move(from: gapStart, to: gapEnd, count: tailCount - newEnd.position)
      } else {
        // The rest of the items are wrapped, and will remain so.

        // Illustrated steps: (underscores mark eventual gap position)
        //
        //   0) GH.........AB̲C̲D̲EF
        //   1) ...GH......AB̲C̲D̲EF
        //   2) DEFGH......AB̲C̲.̲..
        //   3) DEFGH......A.̲.̲.̲BC
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: originalEnd.position)
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapSize)
        move(from: gapStart, to: gapEnd, count: tailCount - gapSize - originalEnd.position)
      }
      count += gapSize
      return mutableWrappedBuffer(between: gapStart, and: gapEnd.orIfZero(capacity))
    }

    // Open the gap by sliding elements to the left.

    let originalStart = self.startSlot
    let newStart = self.slot(originalStart, offsetBy: -gapSize)
    let gapEnd = self.slot(forOffset: offset)
    let gapStart = self.slot(gapEnd, offsetBy: -gapSize)

    let sourceIsContiguous = originalStart <= gapEnd.orIfZero(capacity)
    let targetIsContiguous = newStart <= gapStart.orIfZero(capacity)

    if sourceIsContiguous && targetIsContiguous {
      // No need to deal with any wrapping.

      // Illustrated steps: (underscores mark eventual gap position)
      //
      //   0) ....A̲B̲C̲DEFGH...      GH.........̲A̲B̲CDEF      .̲A̲B̲CDEFGH.......̲.̲
      //   1) .ABC.̲.̲.̲DEFGH...      GH......AB.̲.̲.̲CDEF      .̲.̲.̲CDEFGH....AB.̲.̲
      move(from: originalStart, to: newStart, count: headCount)
    } else if targetIsContiguous {
      // The gap itself will be wrapped.

      // Illustrated steps: (underscores mark eventual gap position)
      //
      //   0) C̲D̲EFGH.........A̲B̲
      //   1) C̲D̲EFGH.....AB...̲.̲
      //   2) .̲.̲EFGH.....ABCD.̲.̲
      assert(originalStart >= newStart)
      move(from: originalStart, to: newStart, count: capacity - originalStart.position)
      move(from: .zero, to: limSlot.advanced(by: -gapSize), count: gapEnd.position)
    } else if sourceIsContiguous {
      // Opening the gap pushes preceding elements across the wrap.

      // Illustrated steps: (underscores mark eventual gap position)
      //
      //   0) .AB̲C̲D̲EFGH.........
      //   1) ...̲C̲D̲EFGH.......AB
      //   2) CD.̲.̲.̲EFGH.......AB
      move(from: originalStart, to: newStart, count: capacity - newStart.position)
      move(from: Slot.zero.advanced(by: gapSize), to: .zero, count: gapStart.position)
    } else {
      // The preceding of the items are wrapped, and will remain so.

      // Illustrated steps: (underscores mark eventual gap position)
      //   0) CD̲E̲F̲GHIJKL.........AB
      //   1) CD̲E̲F̲GHIJKL......AB...
      //   2) ..̲.̲F̲GHIJKL......ABCDE
      //   3) F.̲.̲.̲GHIJKL......ABCDE
      move(from: originalStart, to: newStart, count: capacity - originalStart.position)
      move(from: .zero, to: limSlot.advanced(by: -gapSize), count: gapSize)
      move(from: Slot.zero.advanced(by: gapSize), to: .zero, count: gapStart.position)
    }
    startSlot = newStart
    count += gapSize
    return mutableWrappedBuffer(between: gapStart, and: gapEnd.orIfZero(capacity))
  }
}

// MARK: Removal

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func uncheckedRemove(at offset: Int) -> Element {
    let slot = self.slot(forOffset: offset)
    let result = mutablePtr(at: slot).move()
    closeGap(offsets: Range(uncheckedBounds: (offset, offset + 1)))
    return result
  }

  @inlinable
  internal mutating func uncheckedRemoveFirst() -> Element {
    assert(count > 0)
    let result = mutablePtr(at: startSlot).move()
    startSlot = slot(after: startSlot)
    count -= 1
    return result
  }

  @inlinable
  internal mutating func uncheckedRemoveLast() -> Element {
    assert(count > 0)
    let slot = self.slot(forOffset: count - 1)
    let result = mutablePtr(at: slot).move()
    count -= 1
    return result
  }

  @inlinable
  internal mutating func uncheckedRemoveFirst(_ n: Int) {
    assert(count >= n)
    guard n > 0 else { return }
    let target = mutableSegments(forOffsets: 0 ..< n)
    target.deinitialize()
    startSlot = slot(startSlot, offsetBy: n)
    count -= n
  }

  @inlinable
  internal mutating func uncheckedRemoveLast(_ n: Int) {
    assert(count >= n)
    guard n > 0 else { return }
    let target = mutableSegments(forOffsets: count - n ..< count)
    target.deinitialize()
    count -= n
  }

  /// Remove all elements stored in this instance, deinitializing their storage.
  ///
  /// This method does not ensure that the storage buffer is uniquely
  /// referenced.
  @inlinable
  internal mutating func uncheckedRemoveAll() {
    guard count > 0 else { return }
    let target = mutableSegments()
    target.deinitialize()
    count = 0
    startSlot = .zero
  }

  /// Remove all elements in `bounds`, deinitializing their storage and sliding
  /// remaining elements to close the resulting gap.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func uncheckedRemove(offsets bounds: Range<Int>) {
    assert(bounds.lowerBound >= 0 && bounds.upperBound <= self.count)

    // Deinitialize elements in `bounds`.
    mutableSegments(forOffsets: bounds).deinitialize()
    closeGap(offsets: bounds)
  }

  /// Close the gap of already uninitialized elements in `bounds`, sliding
  /// elements outside of the gap to eliminate it, and updating `count` to
  /// reflect the removal.
  ///
  /// This function does not validate its input arguments in release builds. Nor
  /// does it ensure that the storage buffer is uniquely referenced.
  @inlinable
  internal mutating func closeGap(offsets bounds: Range<Int>) {
    assert(bounds.lowerBound >= 0 && bounds.upperBound <= self.count)
    let gapSize = bounds.count
    guard gapSize > 0 else { return }

    let gapStart = self.slot(forOffset: bounds.lowerBound)
    let gapEnd = self.slot(forOffset: bounds.upperBound)

    let headCount = bounds.lowerBound
    let tailCount = count - bounds.upperBound

    if headCount >= tailCount {
      // Close the gap by sliding elements to the left.
      let originalEnd = endSlot
      let newEnd = self.slot(forOffset: count - gapSize)

      let sourceIsContiguous = gapEnd < originalEnd.orIfZero(capacity)
      let targetIsContiguous = gapStart <= newEnd.orIfZero(capacity)
      if tailCount == 0 {
        // No need to move any elements.
      } else if sourceIsContiguous && targetIsContiguous {
        // No need to deal with wrapping.

        //   0) ....ABCD.̲.̲.̲EFGH..   EF.̲.̲.̲GH........ABCD   .̲.̲.̲E..........ABCD.̲.̲   .̲.̲.̲EF........ABCD .̲.̲.̲DE.......ABC
        //   1) ....ABCDE̲F̲G̲H.....   EFG̲H̲.̲..........ABCD   .̲.̲.̲...........ABCDE̲.̲   E̲F̲.̲..........ABCD D̲E̲.̲.........ABC
        move(from: gapEnd, to: gapStart, count: tailCount)
      } else if sourceIsContiguous {
        // The gap lies across the wrap from the subsequent elements.

        //   0) .̲.̲.̲EFGH.......ABCD.̲.̲      EFGH.......ABCD.̲.̲.̲
        //   1) .̲.̲.̲..GH.......ABCDE̲F̲      ..GH.......ABCDE̲F̲G̲
        //   2) G̲H̲.̲...........ABCDE̲F̲      GH.........ABCDE̲F̲G̲
        let c = capacity - gapStart.position
        assert(tailCount > c)
        let next = move(from: gapEnd, to: gapStart, count: c)
        move(from: next.source, to: .zero, count: tailCount - c)
      } else if targetIsContiguous {
        // We need to move elements across a wrap, but the wrap will
        // disappear when we're done.

        //   0) HI....ABCDE.̲.̲.̲FG
        //   1) HI....ABCDEF̲G̲.̲..
        //   2) ......ABCDEF̲G̲H̲I.
        let next = move(from: gapEnd, to: gapStart, count: capacity - gapEnd.position)
        move(from: .zero, to: next.target, count: originalEnd.position)
      } else {
        // We need to move elements across a wrap that won't go away.

        //   0) HIJKL....ABCDE.̲.̲.̲FG
        //   1) HIJKL....ABCDEF̲G̲.̲..
        //   2) ...KL....ABCDEF̲G̲H̲IJ
        //   3) KL.......ABCDEF̲G̲H̲IJ
        var next = move(from: gapEnd, to: gapStart, count: capacity - gapEnd.position)
        next = move(from: .zero, to: next.target, count: gapSize)
        move(from: next.source, to: .zero, count: newEnd.position)
      }
      count -= gapSize
    } else {
      // Close the gap by sliding elements to the right.
      let originalStart = startSlot
      let newStart = slot(startSlot, offsetBy: gapSize)

      let sourceIsContiguous = originalStart < gapStart.orIfZero(capacity)
      let targetIsContiguous = newStart <= gapEnd.orIfZero(capacity)

      if headCount == 0 {
        // No need to move any elements.
      } else if sourceIsContiguous && targetIsContiguous {
        // No need to deal with wrapping.

        //   0) ....ABCD.̲.̲.̲EFGH.....   EFGH........AB.̲.̲.̲CD   .̲.̲.̲CDEFGH.......AB.̲.̲   DEFGH.......ABC.̲.̲
        //   1) .......AB̲C̲D̲EFGH.....   EFGH...........̲A̲B̲CD   .̲A̲B̲CDEFGH..........̲.̲   DEFGH.........AB̲C̲     ABCDEFGH........̲.̲.̲
        move(from: originalStart, to: newStart, count: headCount)
      } else if sourceIsContiguous {
        // The gap lies across the wrap from the preceding elements.

        //   0) .̲.̲DEFGH.......ABC.̲.̲     .̲.̲.̲EFGH.......ABCD
        //   1) B̲C̲DEFGH.......A...̲.̲     B̲C̲D̲DEFGH......A...
        //   2) B̲C̲DEFGH...........̲A̲     B̲C̲D̲DEFGH.........A
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapEnd.position)
        move(from: startSlot, to: newStart, count: headCount - gapEnd.position)
      } else if targetIsContiguous {
        // We need to move elements across a wrap, but the wrap will
        // disappear when we're done.

        //   0) CD.̲.̲.̲EFGHI.....AB
        //   1) ...̲C̲D̲EFGHI.....AB
        //   1) .AB̲C̲D̲EFGHI.......
        move(from: .zero, to: gapEnd.advanced(by: -gapStart.position), count: gapStart.position)
        move(from: startSlot, to: newStart, count: headCount - gapStart.position)
      } else {
        // We need to move elements across a wrap that won't go away.
        //   0) FG.̲.̲.̲HIJKLMNO....ABCDE
        //   1) ...̲F̲G̲HIJKLMNO....ABCDE
        //   2) CDE̲F̲G̲HIJKLMNO....AB...
        //   3) CDE̲F̲G̲HIJKLMNO.......AB
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: gapStart.position)
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapSize)
        move(from: startSlot, to: newStart, count: headCount - gapEnd.position)
      }
      startSlot = newStart
      count -= gapSize
    }
  }
}

extension _UnsafeDequeHandle {
  /// Copy elements into a newly allocated handle without changing capacity or
  /// layout.
  @inlinable
  internal func allocateCopy() -> Self {
    var handle: Self = .allocate(capacity: self.capacity)
    handle.count = self.count
    handle.startSlot = self.startSlot
    let src = self.segments()
    handle.initialize(at: self.startSlot, from: src.first)
    if let second = src.second {
      handle.initialize(at: .zero, from: second)
    }
    return handle
  }

  /// Copy elements into a new storage instance with the specified minimum
  /// capacity. This operation does not preserve layout.
  @inlinable
  internal func allocateCopy(capacity: Int) -> Self {
    assert(capacity >= count)
    var handle: Self = .allocate(capacity: capacity)
    handle.count = self.count
    let src = self.segments()
    let next = handle.initialize(at: .zero, from: src.first)
    if let second = src.second {
      handle.initialize(at: next, from: second)
    }
    return handle
  }
}

extension _UnsafeDequeHandle where Element: ~Copyable {
  @inlinable
  internal mutating func reallocate(capacity newCapacity: Int) {
    precondition(newCapacity >= count)
    guard newCapacity != capacity else { return }
    var newHandle = Self.allocate(capacity: newCapacity)
    newHandle.startSlot = .zero
    newHandle.count = self.count
    let source = self.mutableSegments()
    let next = newHandle.moveInitialize(at: .zero, from: source.first)
    if let second = source.second {
      newHandle.moveInitialize(at: next, from: second)
    }
    self._buffer.deallocate()
    self = newHandle
  }
}
