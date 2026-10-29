import XCTest
@testable import NashiUpdates

final class UpdateRelaunchTests: XCTestCase {
    func testBusyConversionDefersRestartAndResumesOnlyOnceWhenIdle() async {
        await MainActor.run {
            let updater = AppUpdater()
            var restarts = 0
            updater.setBusy(true)
            XCTAssertTrue(updater.postponeRelaunchIfBusy { restarts += 1 })
            XCTAssertTrue(updater.waitingForCurrentTask)
            XCTAssertEqual(restarts, 0)
            updater.setBusy(true)
            XCTAssertEqual(restarts, 0)
            updater.setBusy(false)
            XCTAssertEqual(restarts, 1)
            XCTAssertFalse(updater.waitingForCurrentTask)
            updater.setBusy(false)
            XCTAssertEqual(restarts, 1)
        }
    }

    func testIdleAppLetsSparkleContinueWithoutCallingItsHandlerTwice() async {
        await MainActor.run {
            let updater = AppUpdater()
            var restarts = 0
            XCTAssertFalse(updater.postponeRelaunchIfBusy { restarts += 1 })
            XCTAssertFalse(updater.waitingForCurrentTask)
            updater.setBusy(false)
            XCTAssertEqual(restarts, 0)
        }
    }

    func testEndedUpdateSessionCannotRestartAfterAConversionFinishes() async {
        await MainActor.run {
            let updater = AppUpdater()
            var restarts = 0
            updater.setBusy(true)
            XCTAssertTrue(updater.postponeRelaunchIfBusy { restarts += 1 })
            updater.standardUserDriverWillFinishUpdateSession()
            updater.setBusy(false)
            XCTAssertEqual(restarts, 0)
            XCTAssertFalse(updater.waitingForCurrentTask)
        }
    }
}
