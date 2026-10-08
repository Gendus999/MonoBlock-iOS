import SwiftUI

@main struct MonoBlockApp: App {
    var body: some Scene { WindowGroup { GameScreen().preferredColorScheme(.dark) } }
}

private enum Ink {
    static let black=Color.black, panel=Color(red:12/255,green:12/255,blue:16/255)
    static let slot=Color(red:20/255,green:20/255,blue:30/255), muted=Color(red:142/255,green:142/255,blue:155/255)
}

struct GameScreen: View {
    @StateObject private var engine=GameEngine()
    @State private var settings=false
    @State private var boardFrame=CGRect.zero
    @State private var cellSize: CGFloat=0
    @State private var rootOrigin=CGPoint.zero

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header.padding(.top, 8)
                Spacer(minLength: 14)
                board.padding(.horizontal, 14).frame(maxWidth: 480)
                Spacer(minLength: 12)
                tray.frame(height: min(geo.size.width * 0.29, 110)).padding(.horizontal, 18).padding(.bottom, 12)
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color.black.ignoresSafeArea())
            .onAppear { rootOrigin=geo.frame(in:.global).origin }
            .onChange(of:geo.frame(in:.global)) { frame in rootOrigin=frame.origin }
            .overlay { if settings { settingsOverlay.transition(.opacity) } }
            .overlay { if engine.state.gameOver { gameOver.transition(.opacity.combined(with:.scale(scale:0.94))) } }
            .overlay { if let p=engine.drag.piece, engine.drag.index != nil { dragOverlay(p) }.allowsHitTesting(false) }
        }
        .statusBarHidden(false)
    }

    private var header: some View {
        HStack {
            Button { withAnimation(.easeOut(duration:0.2)){settings=true} } label: { Image(systemName:"gearshape.fill").font(.system(size:18)).foregroundStyle(.white).frame(width:42,height:42).background(Ink.panel,in:Circle()).overlay(Circle().stroke(Color.white.opacity(0.1))) }
            Spacer()
            VStack(spacing:3) {
                HStack(spacing:4) { Image(systemName:"trophy.fill").foregroundStyle(engine.state.mode == .off ? Ink.muted : Color.yellow).font(.system(size:11)); Text("BEST\(engine.state.mode == .off ? "" : " (\(engine.state.mode.title.uppercased()))")  \(engine.state.highScore.formatted())").font(.system(size:11,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(Ink.muted) }
                Text(engine.state.score.formatted()).font(.system(size:35,weight:.black,design:.rounded)).foregroundStyle(.white)
            }
            Spacer()
            Color.clear.frame(width:42,height:42)
        }.padding(.horizontal,16).animation(.spring(response:0.28,dampingFraction:0.78),value:engine.state.score)
    }

    private var board: some View {
        GeometryReader { proxy in
            let side=proxy.size.width
            let spacing:CGFloat=3.5, inset:CGFloat=8
            let cell=(side-2*inset-spacing*7)/8
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:20).fill(Ink.panel)
                TimelineView(.animation(minimumInterval:1.0/30.0,paused:engine.state.blasting.isEmpty && engine.state.grid.allSatisfy{$0.allSatisfy{$0 == 0}})) { timeline in
                Canvas { context, size in
                    for r in 0..<8 { for c in 0..<8 {
                        let rect=CGRect(x:CGFloat(c)*(cell+spacing),y:CGFloat(r)*(cell+spacing),width:cell,height:cell)
                        let path=Path(roundedRect:rect,cornerRadius:cell*0.22)
                        context.fill(path,with:.color(Ink.slot))
                        context.stroke(path,with:.color(engine.state.gridBorder ? Color.white.opacity(0.93) : Color(red:0.145,green:0.145,blue:0.21)),lineWidth:engine.state.gridBorder ? 1.15 : 1)
                        let isBlast=engine.state.blasting.contains(Cell(row:r,col:c))
                        if engine.state.grid[r][c] != 0 || isBlast {
                            let pulse=0.9 + 0.1*sin(timeline.date.timeIntervalSinceReferenceDate*3.9)
                            let progress=isBlast ? min(max(timeline.date.timeIntervalSince(engine.state.blastStartedAt ?? timeline.date)/0.22,0),1) : 0
                            let alpha=isBlast ? 0.55*(1-progress) : 0.24*pulse
                            context.drawLayer { layer in
                                layer.addFilter(.blur(radius:cell*0.17));layer.fill(path,with:.color(.white.opacity(alpha)))
                            }
                            var core=context;core.opacity=isBlast ? 1-progress : 1
                            core.fill(path,with:.linearGradient(Gradient(colors:[.white,Color(red:0.92,green:0.92,blue:0.95)]),startPoint:rect.minYPoint,endPoint:rect.maxYPoint))
                        }
                    } }
                    if engine.drag.valid,let p=engine.drag.piece,let target=engine.drag.target {
                        for r in 0..<p.height { for c in 0..<p.width where p.matrix[r][c] {
                            let rect=CGRect(x:CGFloat(target.col+c)*(cell+spacing),y:CGFloat(target.row+r)*(cell+spacing),width:cell,height:cell)
                            let path=Path(roundedRect:rect,cornerRadius:cell*0.22)
                            context.fill(path,with:.color(.white.opacity(0.24)));context.stroke(path,with:.color(.white.opacity(0.8)),lineWidth:2)
                        } }
                    }
                }
                .padding(inset)
                .contentShape(Rectangle())
                }
                GeometryReader { hit in Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onEnded { value in
                    guard engine.state.selectedIndex != nil else{return}
                    let x=value.location.x-inset,y=value.location.y-inset
                    let c=min(max(Int(x/(cell+spacing)),0),7),r=min(max(Int(y/(cell+spacing)),0),7)
                    engine.boardTap(row:r,col:c)
                }) }
            }
            .overlay(RoundedRectangle(cornerRadius:20).stroke(engine.state.whiteBoardBorder ? .white : Color(red:0.12,green:0.12,blue:0.16),lineWidth:engine.state.whiteBoardBorder ? 1.8 : 1.2))
            .onAppear { cellSize=cell;boardFrame=proxy.frame(in:.global).insetBy(dx:inset,dy:inset) }
            .onChange(of: proxy.size) { _ in cellSize=cell;boardFrame=proxy.frame(in:.global).insetBy(dx:inset,dy:inset) }
            .onChange(of: proxy.frame(in:.global)) { frame in boardFrame=frame.insetBy(dx:inset,dy:inset) }
        }
        .aspectRatio(1,contentMode:.fit)
    }

    private var tray: some View {
        HStack(spacing:14) {
            ForEach(0..<3,id:\.self) { index in
                let piece=engine.state.pieces[index]
                ZStack {
                    RoundedRectangle(cornerRadius:14).fill(Color(red:0.03,green:0.03,blue:0.045))
                    RoundedRectangle(cornerRadius:14).stroke(engine.state.selectedIndex == index || engine.state.puzzleBorder ? .white : Color(red:0.095,green:0.095,blue:0.13),lineWidth:engine.state.selectedIndex == index ? 2.2 : 1)
                    if let piece,engine.drag.index != index {
                        PieceShape(piece:piece,ratio:0.72).opacity(engine.canFit(piece) ? 1 : 0.35).padding(6)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius:14))
                .gesture(DragGesture(minimumDistance:0,coordinateSpace:.global).onChanged { v in
                    if engine.drag.index == nil {engine.startDrag(index:index,point:v.startLocation)}
                    engine.updateDrag(point:v.location,board:boardFrame,cell:cellSize)
                }.onEnded { v in
                    if v.translation.width.magnitude + v.translation.height.magnitude < 12 { engine.endDrag();engine.selectPiece(index) }
                    else { engine.endDrag() }
                })
            }
        }
    }

    @ViewBuilder private func dragOverlay(_ piece:BlockPiece)->some View {
        let spacing:CGFloat=3.5, cell=max(cellSize,38)
        let w=CGFloat(piece.width)*cell+CGFloat(piece.width-1)*spacing,h=CGFloat(piece.height)*cell+CGFloat(piece.height-1)*spacing
        PieceShape(piece:piece,ratio:1,spacing:spacing,cellOverride:cell)
            .frame(width:w,height:h).shadow(color:.white.opacity(0.35),radius:12).position(x:engine.drag.point.x-rootOrigin.x,y:engine.drag.point.y-rootOrigin.y-88)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea().onTapGesture { settings=false }
            ScrollView {
                VStack(alignment:.leading,spacing:15) {
                    HStack { Text("NASTAVENIA").font(.system(size:17,weight:.black)).tracking(1.5);Spacer();Button {settings=false} label:{Image(systemName:"xmark").font(.system(size:13,weight:.bold)).frame(width:36,height:36).background(Color.white.opacity(0.1),in:Circle())} }
                    section("REKORDY SKÓRE",icon:"trophy.fill",color:.yellow) {
                        ForEach(AssistantMode.allCases) { mode in HStack { Circle().fill(modeColor(mode)).frame(width:8,height:8);Text("\(mode.title)\(engine.state.mode == mode ? " (aktívny)" : "")");Spacer();Text((engine.state.highScores[mode] ?? 0).formatted()).fontWeight(.bold) }.font(.system(size:13)).padding(10).background(Color.white.opacity(engine.state.mode == mode ? 0.09 : 0.025),in:RoundedRectangle(cornerRadius:11)) }
                    }
                    section("POMOCNÍK",icon:"brain.head.profile",color:.blue) {
                        HStack(spacing:6) {ForEach([AssistantMode.off,.low,.medium,.lot]) { mode in Button {engine.setMode(mode)} label: {Text(mode.title).font(.system(size:12,weight:.black)).frame(maxWidth:.infinity).padding(.vertical,11).foregroundStyle(engine.state.mode == mode ? .black : .white).background(engine.state.mode == mode ? modeColor(mode) : Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:11))} } }
                        Text(engine.state.mode.description).font(.system(size:11)).foregroundStyle(Ink.muted)
                    }
                    Text("ZOBRAZENIE A OVLÁDANIE").font(.system(size:11,weight:.bold)).tracking(1).foregroundStyle(Ink.muted)
                    toggle("Vibrácie",subtitle:"Zapnuté / vypnuté",key:"haptics",icon:"iphone.radiowaves.left.and.right",value:engine.state.haptics)
                    toggle("Extraordinary Blocks",subtitle:"Špeciálne 3×3 tvary",key:"extraordinary",icon:"sparkles",value:engine.state.extraordinary)
                    toggle("Svetlý biely rámček",subtitle:"Okraj dosky",key:"white",icon:"square.dashed",value:engine.state.whiteBoardBorder)
                    toggle("Biele políčka plátna",subtitle:"Obrysy buniek",key:"grid",icon:"square.grid.3x3",value:engine.state.gridBorder)
                    toggle("Biely rámček Puzzle",subtitle:"Okraje dielikov",key:"puzzle",icon:"puzzlepiece",value:engine.state.puzzleBorder)
                    Button {engine.restart();settings=false} label:{Label("Reštartovať hru",systemImage:"arrow.clockwise").font(.system(size:14,weight:.bold)).frame(maxWidth:.infinity).padding(14).background(Color.white.opacity(0.08),in:RoundedRectangle(cornerRadius:14))}
                }.padding(20).background(Color(red:0.03,green:0.03,blue:0.04),in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(Color.white.opacity(0.12))).padding(20)
            }
        }
    }
    private func section<Content:View>(_ title:String,icon:String,color:Color,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:10) {Label(title,systemImage:icon).font(.system(size:13,weight:.black)).tracking(0.8).foregroundStyle(color);content()}.padding(14).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(Color.white.opacity(0.08)))
    }
    private func toggle(_ title:String,subtitle:String,key:String,icon:String,value:Bool)->some View {
        Toggle(isOn:Binding(get:{value},set:{_ in engine.toggle(key)})) {Label {VStack(alignment:.leading,spacing:3){Text(title).font(.system(size:14,weight:.bold));Text(subtitle).font(.system(size:11)).foregroundStyle(Ink.muted)} } icon:{Image(systemName:icon).frame(width:21)} }.tint(.white).padding(12).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
    }
    private var gameOver: some View {
        ZStack {Color.black.opacity(0.89).ignoresSafeArea();VStack(spacing:17) {
            Text("KONIEC HRY").font(.system(size:24,weight:.black)).tracking(2)
            if engine.state.score>0 && engine.state.score>=engine.state.highScore {Label("NOVÝ REKORD!",systemImage:"trophy.fill").font(.system(size:12,weight:.black)).padding(10).overlay(Capsule().stroke(.white))}
            VStack(spacing:6){Text("DOSIAHNUTÉ SKÓRE").font(.system(size:11,weight:.bold)).tracking(1).foregroundStyle(Ink.muted);Text(engine.state.score.formatted()).font(.system(size:38,weight:.black));Text("Najlepšie skóre: \(engine.state.highScore.formatted())").font(.system(size:13)).foregroundStyle(Ink.muted)}.frame(maxWidth:.infinity).padding(20).background(Color.white.opacity(0.06),in:RoundedRectangle(cornerRadius:18))
            Button {engine.restart()} label:{Label("HRAŤ ZNOVA",systemImage:"arrow.clockwise").font(.system(size:15,weight:.black)).tracking(1).foregroundStyle(.black).frame(maxWidth:.infinity).padding(17).background(.white,in:RoundedRectangle(cornerRadius:17))}
        }.padding(28).frame(maxWidth:380).background(Color(red:0.055,green:0.055,blue:0.08),in:RoundedRectangle(cornerRadius:27)).overlay(RoundedRectangle(cornerRadius:27).stroke(.white.opacity(0.15)))}}
    private func modeColor(_ mode:AssistantMode)->Color {switch mode{case .lot:Color(red:1,green:0.43,blue:0.61);case .medium:Color(red:1,green:0.7,blue:0.05);case .low:Color(red:0.3,green:0.69,blue:0.32);case .off:Color(red:0.62,green:0.62,blue:0.67)}}
}

private struct PieceShape: View {
    let piece:BlockPiece;var ratio:CGFloat=0.82;var spacing:CGFloat=2.5;var cellOverride:CGFloat?=nil
    var body:some View {GeometryReader { proxy in
        let cell=cellOverride ?? min((proxy.size.width-spacing*CGFloat(max(0,piece.width-1)))/CGFloat(max(1,piece.width)),(proxy.size.height-spacing*CGFloat(max(0,piece.height-1)))/CGFloat(max(1,piece.height)))*ratio
        let drawnW=CGFloat(piece.width)*cell+CGFloat(max(0,piece.width-1))*spacing,drawnH=CGFloat(piece.height)*cell+CGFloat(max(0,piece.height-1))*spacing
        ZStack(alignment:.topLeading) {ForEach(0..<piece.height,id:\.self){r in ForEach(0..<piece.width,id:\.self){c in if piece.matrix[r][c] {RoundedRectangle(cornerRadius:cell*0.22).fill(LinearGradient(colors:[.white,Color(red:0.92,green:0.92,blue:0.95)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay(RoundedRectangle(cornerRadius:cell*0.22).stroke(.white.opacity(0.6),lineWidth:1.3)).shadow(color:.white.opacity(0.18),radius:4).frame(width:cell,height:cell).position(x:CGFloat(c)*(cell+spacing)+cell/2,y:CGFloat(r)*(cell+spacing)+cell/2)}}}.frame(width:drawnW,height:drawnH).position(x:proxy.size.width/2,y:proxy.size.height/2)}
    }}
}
private extension CGRect { var minYPoint:CGPoint{CGPoint(x:minX,y:minY)};var maxYPoint:CGPoint{CGPoint(x:maxX,y:maxY)} }
