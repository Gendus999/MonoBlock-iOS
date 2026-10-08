import Foundation

let gridSize = 8

enum AssistantMode: String, CaseIterable, Codable, Identifiable {
    case lot = "LOT", medium = "MEDIUM", low = "LOW", off = "OFF"
    var id: String { rawValue }
    var title: String { switch self { case .lot: "Lot"; case .medium: "Medium"; case .low: "Low"; case .off: "Off" } }
    var description: String {
        switch self {
        case .lot: "Veľká pomoc – aktívne vyberá dieliky na dokončenie línií a kombá."
        case .medium: "Stredná pomoc – častejšie ponúkne vhodný kúsok na vyčistenie dosky."
        case .low: "Mierna pomoc – občas jemne pomôže potrebnými tvarmi."
        case .off: "Vypnutý – čisté náhodné generovanie dielikov bez asistencie."
        }
    }
}

struct BlockPiece: Identifiable, Equatable {
    let id = UUID()
    let matrix: [[Bool]]
    let colorVariant: Int
    var height: Int { matrix.count }
    var width: Int { matrix.first?.count ?? 0 }
    var blockCount: Int { matrix.flatMap { $0 }.filter { $0 }.count }
    static func shape(_ rows: [String]) -> [[Bool]] { rows.map { $0.map { $0 == "1" } } }

    static let basic: [[[Bool]]] = [
        shape(["1"]), shape(["11"]), shape(["1","1"]), shape(["111"]), shape(["1","1","1"]),
        shape(["1111"]), shape(["1","1","1","1"]), shape(["11111"]), shape(["1","1","1","1","1"]),
        shape(["11","11"]), shape(["111","111","111"]),
        shape(["10","11"]), shape(["01","11"]), shape(["11","10"]), shape(["11","01"]),
        shape(["100","100","111"]), shape(["001","001","111"]), shape(["111","100","100"]), shape(["111","001","001"]),
        shape(["10","10","11"]), shape(["01","01","11"]), shape(["111","100"]), shape(["111","001"]),
        shape(["11","10","10"]), shape(["11","01","01"]), shape(["100","111"]), shape(["001","111"]),
        shape(["111","010"]), shape(["010","111"]), shape(["10","11","10"]), shape(["01","11","01"]),
        shape(["110","011"]), shape(["011","110"]), shape(["10","11","01"]), shape(["01","11","10"]),
        shape(["111","111"]), shape(["11","11","11"])
    ]
    static let extraordinary: [[[Bool]]] = [
        shape(["111","100","111"]), shape(["111","001","111"]), shape(["101","101","111"]),
        shape(["111","101","101"]), shape(["010","111","010"]), shape(["111","101","111"]),
        shape(["100","010","001"]), shape(["001","010","100"]), shape(["111","010","010"]),
        shape(["010","010","111"])
    ]
    static func generate(allowExtraordinary: Bool, grid: [[Int]], mode: AssistantMode) -> [BlockPiece?] {
        let pool = allowExtraordinary ? basic + extraordinary : basic
        func fit(_ shape: [[Bool]]) -> Bool { canShapeFit(shape, grid: grid) }
        func clears(_ shape: [[Bool]]) -> Bool { doesShapeClearLine(shape, grid: grid) }
        if mode == .off {
            let small = pool.filter { $0.flatMap { $0 }.filter { $0 }.count <= 4 }
            let first = allowExtraordinary && Double.random(in: 0..<1) < 0.45 ? extraordinary.randomElement()! : pool.randomElement()!
            return [first, small.randomElement()!, pool.randomElement()!].shuffled().map { BlockPiece(matrix: $0, colorVariant: Int.random(in: 0..<3)) }
        }
        let fits = pool.filter(fit), clears = fits.filter(clears)
        let small = (fits.isEmpty ? pool : fits).filter { $0.flatMap { $0 }.filter { $0 }.count <= 4 }
        func pick(_ items: [[[Bool]]], fallback: [[[Bool]]]) -> [[Bool]] { (items.isEmpty ? fallback : items).randomElement()! }
        var chosen: [[[Bool]]] = []
        switch mode {
        case .lot:
            chosen.append(pick(clears, fallback: small.isEmpty ? (fits.isEmpty ? pool : fits) : small))
            if clears.count > 1 && Double.random(in: 0..<1) < 0.65 { chosen.append(clears.randomElement()!) }
            else { chosen.append(pick(small, fallback: fits.isEmpty ? pool : fits)) }
            chosen.append(pick(fits, fallback: pool))
        case .medium:
            chosen.append(!clears.isEmpty && Double.random(in: 0..<1) < 0.70 ? clears.randomElement()! : pick(small, fallback: fits.isEmpty ? pool : fits))
            chosen.append(pick(small, fallback: fits.isEmpty ? pool : fits)); chosen.append(pool.randomElement()!)
        case .low:
            if !clears.isEmpty && Double.random(in: 0..<1) < 0.35 { chosen.append(clears.randomElement()!) }
            else if !small.isEmpty && Double.random(in: 0..<1) < 0.50 { chosen.append(small.randomElement()!) }
            else { chosen.append(pool.randomElement()!) }
            chosen.append(pick(small, fallback: pool)); chosen.append(pool.randomElement()!)
        case .off: break
        }
        return chosen.shuffled().map { BlockPiece(matrix: $0, colorVariant: Int.random(in: 0..<3)) }
    }
}

struct GameSnapshot {
    var grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
    var pieces: [BlockPiece?] = []
    var score = 0
    var highScore = 0
    var highScores: [AssistantMode: Int] = Dictionary(uniqueKeysWithValues: AssistantMode.allCases.map { ($0, 0) })
    var mode: AssistantMode = .off
    var combo = 0
    var gameOver = false
    var blasting = Set<Cell>()
    var blastStartedAt: Date?
    var alert: String?
    var selectedIndex: Int?
    var extraordinary = false
    var whiteBoardBorder = true
    var gridBorder = true
    var puzzleBorder = false
    var haptics = true
}
struct Cell: Hashable { let row: Int; let col: Int }
func lineClearPoints(for total: Int) -> Int { switch total { case 1: 100; case 2: 300; case 3: 600; case 4: 1000; default: total * 250 } }
func comboBonus(streak: Int) -> Int { streak > 1 ? streak * 120 : 0 }

func canPlace(_ piece: BlockPiece, row: Int, col: Int, grid: [[Int]]) -> Bool {
    for r in 0..<piece.height { for c in 0..<piece.width where piece.matrix[r][c] {
        let rr = row + r, cc = col + c
        if rr < 0 || rr >= gridSize || cc < 0 || cc >= gridSize || grid[rr][cc] != 0 { return false }
    } }
    return true
}
func canFit(_ piece: BlockPiece, grid: [[Int]]) -> Bool {
    guard piece.height <= gridSize, piece.width <= gridSize else { return false }
    for r in 0...(gridSize-piece.height) { for c in 0...(gridSize-piece.width) where canPlace(piece, row: r, col: c, grid: grid) { return true } }
    return false
}
func canShapeFit(_ shape: [[Bool]], grid: [[Int]]) -> Bool {
    let p = BlockPiece(matrix: shape, colorVariant: 0); return canFit(p, grid: grid)
}
func doesShapeClearLine(_ shape: [[Bool]], grid: [[Int]]) -> Bool {
    let p = BlockPiece(matrix: shape, colorVariant: 0)
    guard p.height <= gridSize, p.width <= gridSize else { return false }
    for r in 0...(gridSize-p.height) { for c in 0...(gridSize-p.width) where canPlace(p, row: r, col: c, grid: grid) {
        for dr in 0..<p.height where (0..<gridSize).allSatisfy({ grid[r+dr][$0] != 0 || ($0 >= c && $0 < c+p.width && shape[dr][$0-c]) }) { return true }
        for dc in 0..<p.width where (0..<gridSize).allSatisfy({ grid[$0][c+dc] != 0 || ($0 >= r && $0 < r+p.height && shape[$0-r][dc]) }) { return true }
    } }
    return false
}
