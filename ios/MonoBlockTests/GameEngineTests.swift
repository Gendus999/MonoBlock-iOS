import XCTest
@testable import MonoBlock

@MainActor final class GameEngineTests: XCTestCase {
    private func makeEngine() -> GameEngine {
        let name = "MonoBlockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return GameEngine(defaults: defaults)
    }

    func testInitialStateIsCleanAndHasThreePieces() {
        let engine = makeEngine()
        XCTAssertEqual(engine.state.score, 0)
        XCTAssertEqual(engine.state.combo, 0)
        XCTAssertFalse(engine.state.gameOver)
        XCTAssertEqual(engine.state.pieces.count, 3)
        XCTAssertTrue(engine.state.grid.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    func testPlacementValidationChecksBoundsAndCollision() {
        let grid = Array(repeating: Array(repeating: 0, count: 8), count: 8)
        let dot = BlockPiece(matrix: [[true]], colorVariant: 0)
        XCTAssertTrue(canPlace(dot, row: 0, col: 0, grid: grid))
        XCTAssertTrue(canPlace(dot, row: 7, col: 7, grid: grid))
        XCTAssertFalse(canPlace(dot, row: -1, col: 0, grid: grid))
        XCTAssertFalse(canPlace(dot, row: 8, col: 0, grid: grid))
        XCTAssertFalse(canPlace(dot, row: 0, col: 8, grid: grid))
        let square = BlockPiece(matrix: [[true,true],[true,true]], colorVariant: 0)
        XCTAssertFalse(canPlace(square, row: 7, col: 7, grid: grid))
        XCTAssertTrue(canPlace(square, row: 6, col: 6, grid: grid))
        var occupied = grid; occupied[2][2] = 1
        XCTAssertFalse(canPlace(dot, row: 2, col: 2, grid: occupied))
    }

    func testPlacingPieceAddsTenPointsPerBlock() {
        let engine = makeEngine()
        guard let piece = engine.state.pieces[0] else { return XCTFail("Expected a piece") }
        engine.place(0, row: 0, col: 0)
        XCTAssertEqual(engine.state.score, piece.blockCount * 10)
        XCTAssertEqual(engine.state.highScore, piece.blockCount * 10)
        XCTAssertEqual(engine.state.pieces[0], nil)
    }

    func testAssistantModesAndHighScoresAreTrackedIndependently() {
        let engine = makeEngine()
        XCTAssertEqual(engine.state.mode, .off)
        for mode in AssistantMode.allCases {
            engine.setMode(mode)
            XCTAssertEqual(engine.state.mode, mode)
            XCTAssertNotNil(engine.state.highScores[mode])
        }
        XCTAssertEqual(engine.state.highScores.count, 4)
    }

    func testAssistedGenerationReturnsThreePiecesThatFitOnEmptyBoard() {
        let grid = Array(repeating: Array(repeating: 0, count: 8), count: 8)
        for mode in AssistantMode.allCases {
            let pieces = BlockPiece.generate(allowExtraordinary: false, grid: grid, mode: mode)
            XCTAssertEqual(pieces.count, 3)
            XCTAssertEqual(pieces.compactMap{$0}.count, 3)
            XCTAssertTrue(pieces.compactMap{$0}.allSatisfy { canFit($0, grid:grid) })
        }
    }

    func testLineClearingScoreTableAndComboBonus() {
        XCTAssertEqual(lineClearPoints(for: 1), 100)
        XCTAssertEqual(lineClearPoints(for: 2), 300)
        XCTAssertEqual(lineClearPoints(for: 3), 600)
        XCTAssertEqual(lineClearPoints(for: 4), 1000)
        XCTAssertEqual(lineClearPoints(for: 5), 1250)
        XCTAssertEqual(comboBonus(streak: 1), 0)
        XCTAssertEqual(comboBonus(streak: 2), 240)
    }
}
