// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationDocument.swift
import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class AnnotationDocument {
    public private(set) var imageSize: CGSize
    public private(set) var objects: [any AnnotationObject] = []
    public private(set) var selectedObjectID: ObjectID?
    public private(set) var cropRect: CGRect?
    /// Badge numbers already flattened into the source image.
    public var reservedCounterNumbers: Set<Int> = []
    /// Enabled only by screenshot version editing.
    public var enforcesUniqueCounterNumbers = false
    /// False when existing image coordinates must remain unchanged.
    public var allowsCanvasResize = true
    /// False for image-only annotation workflows without a pin service.
    public var allowsPin = true

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private struct Snapshot {
        let objects: [any AnnotationObject]
        let cropRect: CGRect?
        let imageSize: CGSize
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Whether the document has anything a user would be upset to lose.
    /// `canUndo` is included (not just `objects`/`cropRect`) so that
    /// destructive edits which don't leave visible objects behind — e.g. a
    /// rotate/flip via `replaceImage` — still count as unsaved work.
    public var hasUnsavedChanges: Bool {
        !objects.isEmpty || cropRect != nil || canUndo
    }

    public init(imageSize: CGSize) {
        self.imageSize = imageSize
    }

    public func addObject(_ object: any AnnotationObject) {
        if enforcesUniqueCounterNumbers, let counter = object as? CounterObject {
            let occupied = reservedCounterNumbers.union(objects.compactMap { ($0 as? CounterObject)?.number })
            if occupied.contains(counter.number) {
                counter.number = (occupied.max() ?? 0) + 1
            }
        }
        pushUndo()
        objects.append(object)
        selectedObjectID = object.id
    }

    public func removeObject(id: ObjectID) {
        pushUndo()
        objects.removeAll { $0.id == id }
        if selectedObjectID == id { selectedObjectID = nil }
    }

    public func removeSelected() {
        guard let id = selectedObjectID else { return }
        removeObject(id: id)
    }

    @discardableResult
    public func duplicateSelected(by offset: CGSize) -> Bool {
        guard let selectedObject else { return false }
        let duplicate = selectedObject.copy()
        duplicate.move(by: offset)
        addObject(duplicate)
        return true
    }

    public func selectObject(id: ObjectID?) {
        selectedObjectID = id
    }

    public func clearSelection() {
        selectedObjectID = nil
    }

    public var selectedObject: (any AnnotationObject)? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    public func objectAt(point: CGPoint, threshold: CGFloat = 8) -> (any AnnotationObject)? {
        for object in objects.reversed() {
            if object.hitTest(point: point, threshold: threshold) {
                return object
            }
        }
        return nil
    }

    public func moveObject(id: ObjectID, by delta: CGSize) {
        guard let obj = objects.first(where: { $0.id == id }) else { return }
        obj.move(by: delta)
    }

    public func beginDrag() {
        pushUndo()
    }

    public func setCropRect(_ rect: CGRect?) {
        guard allowsCanvasResize else { return }
        pushUndo()
        cropRect = rect
    }

    /// Called after the crop editor replaces the working image (e.g. after
    /// rotate + commit). Updates `imageSize`, clears any stored crop rect
    /// (coordinates are no longer meaningful), and pushes an undo snapshot.
    /// Callers are expected to avoid calling this when `objects` is non-empty
    /// — the annotations' coordinates would be invalidated.
    public func replaceImage(size: CGSize) {
        guard allowsCanvasResize else { return }
        pushUndo()
        imageSize = size
        cropRect = nil
    }

    /// Updates the backing image size while keeping annotation coordinates meaningful.
    /// Used when the visible canvas grows or shifts around already-created objects.
    public func updateImageSizePreservingObjects(size: CGSize, objectOffset: CGSize = .zero) {
        guard allowsCanvasResize else { return }
        imageSize = size
        cropRect = nil
        if objectOffset != .zero {
            for object in objects {
                object.move(by: objectOffset)
            }
        }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(objects: objects.map { $0.copy() }, cropRect: cropRect, imageSize: imageSize)
    }

    private func apply(_ snapshot: Snapshot) {
        objects = snapshot.objects
        cropRect = snapshot.cropRect
        imageSize = snapshot.imageSize
        selectedObjectID = nil
    }

    private func pushUndo() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot)
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot)
    }
}
