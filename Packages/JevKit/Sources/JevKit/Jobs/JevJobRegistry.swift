// Packages/JevKit/Sources/JevKit/Jobs/JevJobRegistry.swift
import Foundation

/// Every Jev job, in the order the refined files list them.
///
/// The Jev base wrote one line per planned feature, each naming a stub in its
/// own file. A feature session fills in its own job file and never edits this
/// list, so parallel sessions never change the same file. A later feature
/// adds one line.
public enum JevJobRegistry {
    public static let all: [any JevJob] = [
        NoteCoachJob(), // #37
        CropsAnchorsJob(), // #38
        DupesConflictsJob(), // #39
        OneBreathJob(), // #40
        PromptLanesJob(), // #69
        DataGuardJob(), // #70
    ]
}
