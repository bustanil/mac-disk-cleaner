import Foundation

@main
enum DiskCleanerTestRunner {
    static func main() {
        let tests: [() throws -> Void] = [
            decimalUnits,
            percentOfScannedTotal,
            nestedSizesRollUpAndSortLargestFirst,
            hardLinksCountBytesOnce,
            symlinkIsNotFollowed,
            cancelKeepsPartialSnapshot,
            unreadableDirectoryIsSkipped,
            scanDoesNotChangeFileContents,
            missingRootFailsWithoutATree,
            otherVolumeAndVisitedDirectoryAreNotEntered,
            volumeSummaryKeepsPurgeableOutOfUsed,
            volumeSummaryWithoutPurgeable,
            startupScanSkipsTheDataVolumeMirror,
            excludedDirectoryIsLeftOutOfTheTree,
            fullDiskAccessSettingsURLOpensThePrivacyPane,
            sizeClassBoundaries,
            smallFilesStayATotalAndMediumFilesAreListed,
            appIndexMeasuresBundlesOnly,
            minimumFilterHidesFilesBelowTheThreshold,
            largestFoldersStopAtFiftyAndSkipTheRoot,
            protectedSystemPathIsRefusedAndHomeFileIsAllowed,
            symlinkIntoAProtectedDirectoryIsRefused,
            trashMovesATempFileAndTheSnapshotTotalDrops,
            protectedPathIsNotTrashed,
            downloadAgeKeepsAFileFrom29DaysAgo,
            junkCatalogAppliesTheCategoryRules,
            emptyTrashRemovesOnlyTheListedItem,
            emptyTrashRefusesAPathOutsideTheTrash,
            emptyTrashRefusesASymlinkThatLeavesTheTrash,
        ]
        for test in tests {
            do {
                try test()
            } catch {
                Expect.shared.failures += 1
                print("FAIL threw \(error)")
            }
        }
        if Expect.shared.failures > 0 {
            print("\(Expect.shared.failures) failed")
            exit(1)
        }
        print("\(tests.count) tests passed")
    }
}
