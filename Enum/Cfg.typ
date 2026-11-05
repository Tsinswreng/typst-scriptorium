// HTML 靶的樣式不在本文件：
// 源檔是 _Mvn/Article.css（Mvn.csx 讀入後寫成發布目錄的 _mvn.css），
// 網站那份是 tsinswreng.github.io/public/assets/site.css（源，tracked；dist/ 是其構建產物）。
// 本文件改任何視覺值（顏色、字號、間距）時，那兩份 CSS 都要跟着改，反之亦然。
// CSS 裏的 --tswg-scrptm-em 等於本文件 PDF 靶的 1em（1.5em × 11pt = 16.5pt）。
#let TextSize = 1.5em
#let RawTextSize = 1em
#let RawInset = 0.4em
#let ColorStrong = rgb("00ffff")//rgb("f75c2f")
#let CjkStroke_Regular = 0.030em
#let CjkStroke_Bold = 0.015em
#let CjkChars = "[\p{script=Han}！-･〇-〰—]+"
#let ColorFore = white //rgb("#f0f0f0")
#let ColorBack = black
#let ColorCodeBack = rgb("#002020")
#let ColorInlineCodeBack = rgb("#004040")
// 代碼塊／引用塊的邊框：顏色比底色亮一階，粗細單獨控制；HTML 與 PDF 共用此二值。
#let ColorCodeBorder = rgb("#006060")
#let StrokeCodeBorder = 1pt
// 引用塊的前後間距（僅 PDF 靶）：Typst 塊默認 1.2em；要鬆緊改這一處即可。
#let SpacingQuote = 1em
// 正文行距：Typst 默認 0.65em；要鬆緊改這一處即可。
#let SpacingLeading = 1em
#let ParSpacing = 2.5em
// 段距：P() 段前的垂直距離；要鬆緊改這一處即可。
#let CustomPSpacing = 0em
// 標題前後間距：要鬆緊改這一處即可。
#let SpacingHeadingAbove = 1.5em
#let SpacingHeadingBelow = 1.5em
// 題名（#title）前後間距：要鬆緊改這一處即可。
#let SpacingTitleAbove = 1em
#let SpacingTitleBelow = 1em
#let ColorQuoteBack = ColorCodeBack
#let ColorQuoteBorder = ColorCodeBorder
#let ColorQuoteLeftBorder = rgb("#008888")
#let ColorRefText = rgb("#00dddd")
#let ColorRefUnderline = ColorRefText
#let ColorLinkText = ColorRefText
// 多行代碼塊右上角的語言標籤：文本取自圍欄 info string（寫 `typst` 的塊顯示 typst）。
// 無 lang 的塊不顯示標籤。僅 PDF 靶；HTML 靶暫未適配，見下方 show raw。
#let ColorCodeLangLabel = ColorRefText
#let CodeLangLabelTextSize = 0.8em
// 標題編号後豎線之色
#let ColorVertBar = rgb("00aaaa")
#let ColorTitleUnderbar = ColorVertBar
#let ColorVertBarSize = 1pt

#let ColorHeadingNum = luma(230)
#let ColorListNum = ColorHeadingNum //rgb("00dddd")
#let FigureCaptionTextSize = 0.9em
#let FigureCaptionTextColor = luma(215)
#let CustomPIndent = 2em
#let ListIndent = CustomPIndent
#let EnumIndent = CustomPIndent
