import SwiftUI

struct ANSIRenderer {
    private enum State {
        case plain
        case esc
        case csi
        case osc
        case oscEsc
        case stString
        case stStringEsc
    }

    private struct RGBColor: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    private struct TextStyle: Equatable {
        var isBold = false
        var foregroundColor: RGBColor?
    }

    private struct Cell {
        var scalar: UnicodeScalar
        var style: TextStyle
        var isWide = false
        var isContinuation = false
    }

    private var state: State = .plain
    private var csiParameters = ""
    private var csiIntermediates = ""
    private var style = TextStyle()
    private var lines: [[Cell]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursorRow = 0
    private var savedCursorColumn = 0
    private let defaultForeground = RGBColor(red: 0.82, green: 0.95, blue: 0.88)

    mutating func process(_ input: String) -> AttributedString {
        for scalar in input.unicodeScalars {
            let value = scalar.value

            switch self.state {
            case .plain:
                if value == 0x1B {
                    self.state = .esc
                    continue
                }
                if value == 0x9B {
                    self.beginCSI()
                    continue
                }
                if value == 0x9D {
                    self.state = .osc
                    continue
                }
                if value == 0x90 {
                    self.state = .stString
                    continue
                }
                if value == 0x0A {
                    self.lineFeed()
                    continue
                }
                if value == 0x0D {
                    self.carriageReturn()
                    continue
                }
                if value == 0x08 {
                    self.backspace()
                    continue
                }
                if value == 0x09 {
                    self.horizontalTab()
                    continue
                }
                if scalar == "\u{21A9}" || scalar == "\u{23CE}" {
                    continue
                }
                if value < 0x20 {
                    continue
                }
                if (0x80...0x9F).contains(value) {
                    continue
                }
                self.writeScalar(scalar)

            case .esc:
                switch scalar {
                case "[":
                    self.beginCSI()
                case "]":
                    self.state = .osc
                case "P", "_", "^", "X":
                    self.state = .stString
                default:
                    self.state = .plain
                }

            case .csi:
                if (0x30...0x3F).contains(value) {
                    self.csiParameters.unicodeScalars.append(scalar)
                } else if (0x20...0x2F).contains(value) {
                    self.csiIntermediates.unicodeScalars.append(scalar)
                } else if (0x40...0x7E).contains(value) {
                    self.handleCSI(final: scalar)
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .esc
                }

            case .osc:
                if value == 0x07 {
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .oscEsc
                }

            case .oscEsc:
                self.state = scalar == "\\" ? .plain : .osc

            case .stString:
                if value == 0x1B {
                    self.state = .stStringEsc
                }

            case .stStringEsc:
                self.state = scalar == "\\" ? .plain : .stString
            }
        }

        return self.renderSnapshot()
    }

    private mutating func beginCSI() {
        self.csiParameters = ""
        self.csiIntermediates = ""
        self.state = .csi
    }

    private mutating func handleCSI(final: UnicodeScalar) {
        let params = self.parseCSIParameters(self.csiParameters)
        switch final {
        case "m":
            self.applySGR(parameters: params)
        case "K":
            self.eraseInLine(mode: params.first ?? 0)
        case "J":
            self.eraseInDisplay(mode: params.first ?? 0)
        case "C":
            self.cursorColumn += self.countParameter(params)
        case "D":
            self.cursorColumn = max(0, self.cursorColumn - self.countParameter(params))
        case "G":
            self.cursorColumn = max(0, self.positionParameter(params, index: 0) - 1)
        case "A":
            self.cursorRow = max(0, self.cursorRow - self.countParameter(params))
        case "B":
            self.cursorRow += self.countParameter(params)
            self.ensureCursorRowExists()
        case "E":
            self.cursorRow += self.countParameter(params)
            self.ensureCursorRowExists()
            self.cursorColumn = 0
        case "F":
            self.cursorRow = max(0, self.cursorRow - self.countParameter(params))
            self.cursorColumn = 0
        case "H", "f":
            let row = self.positionParameter(params, index: 0) - 1
            let column = self.positionParameter(params, index: 1) - 1
            self.cursorRow = max(0, row)
            self.ensureCursorRowExists()
            self.cursorColumn = max(0, column)
        case "s":
            self.savedCursorRow = self.cursorRow
            self.savedCursorColumn = self.cursorColumn
        case "u":
            self.cursorRow = max(0, self.savedCursorRow)
            self.ensureCursorRowExists()
            self.cursorColumn = max(0, self.savedCursorColumn)
        default:
            break
        }
    }

    private func parseCSIParameters(_ raw: String) -> [Int] {
        guard !raw.isEmpty else { return [] }
        let params = raw.split(separator: ";", omittingEmptySubsequences: false).map { part -> Int in
            Int(part) ?? 0
        }
        return params
    }

    private func countParameter(_ params: [Int], index: Int = 0) -> Int {
        guard index < params.count else { return 1 }
        let value = params[index]
        return value == 0 ? 1 : max(1, value)
    }

    private func positionParameter(_ params: [Int], index: Int) -> Int {
        guard index < params.count else { return 1 }
        let value = params[index]
        return value <= 0 ? 1 : value
    }

    private mutating func applySGR(parameters: [Int]) {
        let codes = parameters.isEmpty ? [0] : parameters
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                self.style = TextStyle()
            case 1:
                self.style.isBold = true
            case 22:
                self.style.isBold = false
            case 30...37:
                self.style.foregroundColor = self.baseColor(for: code - 30, bright: false)
            case 39:
                self.style.foregroundColor = nil
            case 90...97:
                self.style.foregroundColor = self.baseColor(for: code - 90, bright: true)
            case 38:
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    self.style.foregroundColor = self.extended256Color(codes[index + 2])
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    let r = codes[index + 2]
                    let g = codes[index + 3]
                    let b = codes[index + 4]
                    self.style.foregroundColor = RGBColor(
                        red: Double(max(0, min(255, r))) / 255.0,
                        green: Double(max(0, min(255, g))) / 255.0,
                        blue: Double(max(0, min(255, b))) / 255.0
                    )
                    index += 4
                }
            default:
                break
            }
            index += 1
        }
    }

    private mutating func ensureCursorRowExists() {
        if self.lines.isEmpty {
            self.lines = [[]]
        }
        if self.cursorRow < 0 {
            self.cursorRow = 0
        }
        while self.cursorRow >= self.lines.count {
            self.lines.append([])
        }
        if self.cursorColumn < 0 {
            self.cursorColumn = 0
        }
    }

    private mutating func lineFeed() {
        self.cursorRow += 1
        if self.cursorRow >= self.lines.count {
            self.lines.append([])
        }
        self.cursorColumn = 0
    }

    private mutating func carriageReturn() {
        self.cursorColumn = 0
    }

    private mutating func backspace() {
        self.cursorColumn = max(0, self.cursorColumn - 1)
    }

    private mutating func horizontalTab() {
        let spaces = 8 - (self.cursorColumn % 8)
        for _ in 0..<spaces {
            self.writeScalar(" ")
        }
    }

    private mutating func writeScalar(_ scalar: UnicodeScalar) {
        self.ensureCursorRowExists()

        let width = self.displayWidth(of: scalar)
        guard width > 0 else { return }

        self.clearWideFragment(at: self.cursorColumn)
        if width == 2 {
            self.clearWideFragment(at: self.cursorColumn + 1)
        }

        self.ensureColumnExists(self.cursorColumn + width)
        self.lines[self.cursorRow][self.cursorColumn] = Cell(
            scalar: scalar,
            style: self.style,
            isWide: width == 2,
            isContinuation: false
        )

        if width == 2 {
            self.lines[self.cursorRow][self.cursorColumn + 1] = Cell(
                scalar: " ",
                style: self.style,
                isWide: false,
                isContinuation: true
            )
        }

        self.cursorColumn += width
    }

    private mutating func eraseInLine(mode: Int) {
        self.ensureCursorRowExists()

        switch mode {
        case 1:
            let upperBound = min(self.cursorColumn + 1, self.lines[self.cursorRow].count)
            guard upperBound > 0 else { return }
            let blank = self.blankCell()
            for index in 0..<upperBound {
                self.lines[self.cursorRow][index] = blank
            }
        case 2:
            self.lines[self.cursorRow].removeAll(keepingCapacity: true)
            self.cursorColumn = 0
        default:
            guard self.cursorColumn < self.lines[self.cursorRow].count else { return }
            self.lines[self.cursorRow].removeSubrange(self.cursorColumn..<self.lines[self.cursorRow].count)
        }
    }

    private mutating func eraseInDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in 0..<min(self.cursorRow, self.lines.count) {
                self.lines[row].removeAll(keepingCapacity: true)
            }
            self.eraseInLine(mode: 1)
        case 2, 3:
            self.lines = [[]]
            self.cursorRow = 0
            self.cursorColumn = 0
            self.savedCursorRow = 0
            self.savedCursorColumn = 0
        default:
            self.eraseInLine(mode: 0)
            if self.cursorRow + 1 < self.lines.count {
                self.lines.removeSubrange((self.cursorRow + 1)..<self.lines.count)
            }
        }
    }

    private func renderSnapshot() -> AttributedString {
        guard !self.lines.isEmpty else { return AttributedString() }

        var result = AttributedString()
        for row in self.lines.indices {
            result += self.renderLine(self.lines[row])
            if row < self.lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private func renderLine(_ line: [Cell]) -> AttributedString {
        guard !line.isEmpty else { return AttributedString() }

        var rendered = AttributedString()
        var runStyle = line[0].style
        var runText = ""

        func flushRun() {
            guard !runText.isEmpty else { return }
            var attributed = AttributedString(runText)
            attributed.font = runStyle.isBold
                ? .system(.body, design: .monospaced).weight(.semibold)
                : .system(.body, design: .monospaced)
            let color = runStyle.foregroundColor ?? self.defaultForeground
            attributed.foregroundColor = Color(red: color.red, green: color.green, blue: color.blue)
            rendered += attributed
            runText.removeAll(keepingCapacity: true)
        }

        for cell in line {
            if cell.isContinuation {
                continue
            }
            if cell.style != runStyle {
                flushRun()
                runStyle = cell.style
            }
            runText.unicodeScalars.append(cell.scalar)
        }

        flushRun()
        return rendered
    }

    private func baseColor(for index: Int, bright: Bool) -> RGBColor {
        let palette: [(Double, Double, Double)] = bright
            ? [
                (0.50, 0.50, 0.50),
                (1.00, 0.35, 0.35),
                (0.45, 0.90, 0.45),
                (1.00, 0.95, 0.45),
                (0.50, 0.68, 1.00),
                (1.00, 0.55, 1.00),
                (0.55, 0.95, 0.95),
                (1.00, 1.00, 1.00),
            ]
            : [
                (0.00, 0.00, 0.00),
                (0.75, 0.20, 0.20),
                (0.20, 0.70, 0.20),
                (0.78, 0.65, 0.20),
                (0.25, 0.45, 0.78),
                (0.70, 0.30, 0.70),
                (0.25, 0.70, 0.70),
                (0.80, 0.80, 0.80),
            ]
        let safeIndex = max(0, min(7, index))
        let color = palette[safeIndex]
        return RGBColor(red: color.0, green: color.1, blue: color.2)
    }

    private func extended256Color(_ code: Int) -> RGBColor {
        let clamped = max(0, min(255, code))

        if clamped < 16 {
            if clamped < 8 {
                return self.baseColor(for: clamped, bright: false)
            }
            return self.baseColor(for: clamped - 8, bright: true)
        }

        if clamped < 232 {
            let offset = clamped - 16
            let r = offset / 36
            let g = (offset % 36) / 6
            let b = offset % 6
            let component: (Int) -> Double = { value in
                value == 0 ? 0.0 : (Double(value) * 40.0 + 55.0) / 255.0
            }
            return RGBColor(red: component(r), green: component(g), blue: component(b))
        }

        let gray = Double((clamped - 232) * 10 + 8) / 255.0
        return RGBColor(red: gray, green: gray, blue: gray)
    }

    private func blankCell() -> Cell {
        Cell(scalar: " ", style: self.style, isWide: false, isContinuation: false)
    }

    private mutating func ensureColumnExists(_ targetExclusive: Int) {
        guard targetExclusive > self.lines[self.cursorRow].count else { return }
        let padCount = targetExclusive - self.lines[self.cursorRow].count
        guard padCount > 0 else { return }
        self.lines[self.cursorRow].append(contentsOf: Array(repeating: self.blankCell(), count: padCount))
    }

    private mutating func clearWideFragment(at column: Int) {
        guard column >= 0, column < self.lines[self.cursorRow].count else { return }

        if self.lines[self.cursorRow][column].isContinuation {
            self.lines[self.cursorRow][column] = self.blankCell()
            if column > 0, self.lines[self.cursorRow][column - 1].isWide {
                self.lines[self.cursorRow][column - 1] = self.blankCell()
            }
            return
        }

        if self.lines[self.cursorRow][column].isWide {
            self.lines[self.cursorRow][column] = self.blankCell()
            if column + 1 < self.lines[self.cursorRow].count,
               self.lines[self.cursorRow][column + 1].isContinuation {
                self.lines[self.cursorRow][column + 1] = self.blankCell()
            }
        }
    }

    private func displayWidth(of scalar: UnicodeScalar) -> Int {
        if scalar.properties.generalCategory == .nonspacingMark
            || scalar.properties.generalCategory == .enclosingMark
            || scalar.properties.generalCategory == .format {
            return 0
        }

        let value = scalar.value
        if (0x1100...0x115F).contains(value)
            || (0x2329...0x232A).contains(value)
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value)
            || (0xFE30...0xFE6F).contains(value)
            || (0xFF01...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F300...0x1FAFF).contains(value)
            || (0x20000...0x3FFFD).contains(value) {
            return 2
        }

        return 1
    }
}
