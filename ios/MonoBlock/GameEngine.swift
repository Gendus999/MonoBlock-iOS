import Foundation
import SwiftUI
import UIKit

@MainActor final class GameEngine: ObservableObject {
    @Published private(set) var state: GameSnapshot
    @Published private(set) var drag = DragSnapshot()
    private let defaults: UserDefaults
    private var clearTask: Task<Void, Never>?

    struct DragSnapshot { var index: Int?; var piece: BlockPiece?; var point: CGPoint = .zero; var target: Cell?; var valid = false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var s = GameSnapshot()
        let legacy = defaults.integer(forKey: "HIGH_SCORE")
        s.highScores[.lot] = defaults.integer(forKey: "HIGH_SCORE_LOT")
        s.highScores[.medium] = defaults.integer(forKey: "HIGH_SCORE_MEDIUM")
        s.highScores[.low] = defaults.integer(forKey: "HIGH_SCORE_LOW")
        s.highScores[.off] = defaults.object(forKey: "HIGH_SCORE_OFF") == nil ? legacy : defaults.integer(forKey: "HIGH_SCORE_OFF")
        s.mode = AssistantMode(rawValue: defaults.string(forKey: "ASSISTANT_MODE") ?? "OFF") ?? .off
        s.highScore = s.highScores[s.mode] ?? 0
        s.extraordinary = defaults.object(forKey: "EXTRAORDINARY_BLOCKS") as? Bool ?? false
        s.whiteBoardBorder = defaults.object(forKey: "WHITE_BORDER") as? Bool ?? true
        s.puzzleBorder = defaults.object(forKey: "PUZZLE_BORDER") as? Bool ?? false
        s.gridBorder = defaults.object(forKey: "GRID_BORDER") as? Bool ?? true
        s.haptics = defaults.object(forKey: "HAPTICS_ENABLED") as? Bool ?? true
        s.pieces = BlockPiece.generate(allowExtraordinary: s.extraordinary, grid: s.grid, mode: s.mode)
        state = s
    }

    func canPlace(_ piece: BlockPiece, row: Int, col: Int) -> Bool {
    MonoBlock.canPlace(piece, row: row, col: col, grid: state.grid)
}
    func canFit(_ piece: BlockPiece) -> Bool { MonoBlock.canFit(piece, grid: state.grid) }
    func startDrag(index: Int, point: CGPoint) {
        guard !state.gameOver, state.blasting.isEmpty, let p = state.pieces[safe: index] ?? nil else { return }
        drag = DragSnapshot(index: index, piece: p, point: point); state.selectedIndex = nil; impact(.light)
    }
    func updateDrag(point: CGPoint, board: CGRect, cell: CGFloat, spacing: CGFloat = 3.5, lift: CGFloat = 88) {
        guard let p = drag.piece else { return }
        let step = cell + spacing
        let left = point.x - (CGFloat(p.width)*cell + CGFloat(p.width-1)*spacing)/2
        let top = point.y - lift - (CGFloat(p.height)*cell + CGFloat(p.height-1)*spacing)/2
        let exactC = (left-board.minX)/step, exactR = (top-board.minY)/step
        let maxC = max(0, gridSize-p.width), maxR = max(0, gridSize-p.height)
        var target: Cell?
        if exactC >= -1.8 && exactC <= CGFloat(maxC)+1.8 && exactR >= -1.8 && exactR <= CGFloat(maxR)+1.8 {
            let clampedC = min(max(exactC, 0), CGFloat(maxC)), clampedR = min(max(exactR, 0), CGFloat(maxR))
            let idealC = Int(clampedC.rounded()), idealR = Int(clampedR.rounded())
            if canPlace(p, row: idealR, col: idealC), pow(clampedR-CGFloat(idealR),2)+pow(clampedC-CGFloat(idealC),2) <= 0.70 { target = Cell(row: idealR,col: idealC) }
            if target == nil {
                var best = CGFloat.greatestFiniteMagnitude
                for dr in -2...2 { for dc in -2...2 {
                    let r=idealR+dr,c=idealC+dc
                    guard (0...maxR).contains(r),(0...maxC).contains(c),canPlace(p,row:r,col:c) else { continue }
                    var d=pow(clampedR-CGFloat(r),2)+pow(clampedC-CGFloat(c),2)
                    if drag.target == Cell(row:r,col:c) { d *= 0.78 }
                    if d < best && d <= 1.69 { best=d; target=Cell(row:r,col:c) }
                } }
            }
        }
        drag.point=point; drag.target=target; drag.valid=target != nil
    }
    func endDrag() { if let index=drag.index, let t=drag.target, drag.valid { place(index,row:t.row,col:t.col) }; drag=DragSnapshot() }
    func selectPiece(_ index: Int) {
        guard !state.gameOver,state.blasting.isEmpty,let _=state.pieces[safe:index] ?? nil else{return}
        impact(.light); state.selectedIndex = state.selectedIndex == index ? nil : index
    }
    func boardTap(row: Int, col: Int) {
        guard let i=state.selectedIndex, let p=state.pieces[safe:i] ?? nil else{return}
        let ar=min(max(row-p.height/2,0),gridSize-p.height), ac=min(max(col-p.width/2,0),gridSize-p.width)
        if canPlace(p,row:ar,col:ac) { place(i,row:ar,col:ac);state.selectedIndex=nil;return }
        var best: Cell?, distance=Int.max
        for dr in -2...2 { for dc in -2...2 {let r=ar+dr,c=ac+dc,d=dr*dr+dc*dc
            if (0...(gridSize-p.height)).contains(r),(0...(gridSize-p.width)).contains(c),canPlace(p,row:r,col:c),d<distance {best=Cell(row:r,col:c);distance=d}
        } }
        if let best { place(i,row:best.row,col:best.col);state.selectedIndex=nil }
    }
    func place(_ index:Int,row:Int,col:Int) {
        guard state.blasting.isEmpty else{return}
        guard let p=state.pieces[safe:index] ?? nil, canPlace(p,row:row,col:col) else{return}
        impact(.medium); var g=state.grid
        for r in 0..<p.height { for c in 0..<p.width where p.matrix[r][c] {g[row+r][col+c]=1} }
        let rows=(0..<gridSize).filter { g[$0].allSatisfy{$0>0} }
        let cols=(0..<gridSize).filter { c in (0..<gridSize).allSatisfy{g[$0][c]>0} }
        let total=rows.count+cols.count
        var pieces=state.pieces;pieces[index]=nil
        var effective=g
        for r in rows {for c in 0..<gridSize {effective[r][c]=0}}
        for c in cols {for r in 0..<gridSize {effective[r][c]=0}}
        if pieces.allSatisfy({$0 == nil}) {pieces=BlockPiece.generate(allowExtraordinary:state.extraordinary,grid:effective,mode:state.mode)}
        var score=state.score+p.blockCount*10
        let mode=state.mode, oldHigh=state.highScores[mode] ?? 0
        if total>0 {
            state.combo += 1
            score += lineClearPoints(for:total)+comboBonus(streak:state.combo)
            var cells=Set<Cell>(); for r in rows {for c in 0..<gridSize {cells.insert(Cell(row:r,col:c))}};for c in cols {for r in 0..<gridSize {cells.insert(Cell(row:r,col:c))}}
            state.grid=g;state.pieces=pieces;state.score=score;state.blasting=cells;state.blastStartedAt=Date();state.selectedIndex=nil;state.alert=total>=4 ? "SUPER BLAST!" : total>=3 ? "TRIPLE BLAST!" : total==2 ? "DOUBLE BLAST!" : state.combo>1 ? "COMBO x\(state.combo)!" : "BLAST!"
            updateHigh(score)
            impact(.rigid)
            clearTask?.cancel(); clearTask=Task { try? await Task.sleep(for:.milliseconds(220)); guard !Task.isCancelled else{return}
                for cell in cells { self.state.grid[cell.row][cell.col]=0 }
                self.state.blasting=[];self.state.blastStartedAt=nil;self.state.gameOver=self.noMoves();if self.state.gameOver {self.notification(.error)};try? await Task.sleep(for:.milliseconds(900));self.state.alert=nil
            }
        } else {
            state.grid=g;state.pieces=pieces;state.score=score;state.combo=0;state.selectedIndex=nil;state.gameOver=noMoves();updateHigh(score)
            if state.gameOver {notification(.error)}
        }
    }
    private func noMoves() -> Bool { let active=state.pieces.compactMap{$0};return !active.isEmpty && !active.contains{MonoBlock.canFit($0,grid:state.grid)} }
    private func updateHigh(_ score:Int) {let old=state.highScores[state.mode] ?? 0;if score>old {state.highScores[state.mode]=score;state.highScore=score;defaults.set(score,forKey:"HIGH_SCORE_\(state.mode.rawValue)")} }
    func restart() {clearTask?.cancel();let old=state;var s=GameSnapshot();s.highScores=old.highScores;s.mode=old.mode;s.highScore=old.highScore;s.extraordinary=old.extraordinary;s.whiteBoardBorder=old.whiteBoardBorder;s.gridBorder=old.gridBorder;s.puzzleBorder=old.puzzleBorder;s.haptics=old.haptics;s.pieces=BlockPiece.generate(allowExtraordinary:s.extraordinary,grid:s.grid,mode:s.mode);state=s;drag=DragSnapshot()}
    func setMode(_ mode:AssistantMode){state.mode=mode;state.highScore=state.highScores[mode] ?? 0;defaults.set(mode.rawValue,forKey:"ASSISTANT_MODE")}
    func toggle(_ key:String){switch key{case "extraordinary":state.extraordinary.toggle();defaults.set(state.extraordinary,forKey:"EXTRAORDINARY_BLOCKS");case "white":state.whiteBoardBorder.toggle();defaults.set(state.whiteBoardBorder,forKey:"WHITE_BORDER");case "grid":state.gridBorder.toggle();defaults.set(state.gridBorder,forKey:"GRID_BORDER");case "puzzle":state.puzzleBorder.toggle();defaults.set(state.puzzleBorder,forKey:"PUZZLE_BORDER");case "haptics":state.haptics.toggle();defaults.set(state.haptics,forKey:"HAPTICS_ENABLED");default:break}}
    private func impact(_ style:UIImpactFeedbackGenerator.FeedbackStyle){guard state.haptics else{return};UIImpactFeedbackGenerator(style:style).impactOccurred()}
    private func notification(_ type:UINotificationFeedbackGenerator.FeedbackType){guard state.haptics else{return};UINotificationFeedbackGenerator().notificationOccurred(type)}
}
private extension Array { subscript(safe index:Int)->Element? {indices.contains(index) ? self[index] : nil} }
