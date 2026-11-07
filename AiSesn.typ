#import "tsinswreng-auto-heading.typ": *
// AI 會話記錄 DSL（ai-sesn）。
// 職責：把「一輪用戶提問＋AI回答」的 .typ 存檔排版成可讀文檔。
// 約定：回答塊（#T 第三參數）若只含一個 md 代碼塊、別無他物，
// 自動以 Markdown 渲染（cmarker）；否則按原樣 typst 內容渲染。
// 依賴紅線：本文件不得 import 入口 _.typ（cyclic import 直接報錯），
// 所需符號一律從兄弟文件取；Md 在本文件自行接 cmarker，不借入口的別名。
// 消費者接線（入口已把本模塊 as AiSesn 導出）：
// #import "@local/tsinswreng-scriptorium:0.1.0": *
// #show: _Show
// #import "@local/tsinswreng-scriptorium:0.1.0": AiSesn
// #import AiSesn: T, Sesn
// 末行建議用具名導入而非 ``: *``：
// 本文件頂層的 Cfg/Html/Targets/Target/Md 等內部綁定會隨星號導出，
// 與入口星號導入的 Target 等同名，具名導入只帶走 T/Sesn、零污染。
#import "Enum/Cfg.typ" as Cfg
#import "Enum/Html.typ" as Html
#import "Enum/Targets.typ" as Targets
#import "Target.typ": *
#import "@preview/cmarker:0.1.10"
#let Md = cmarker.render

// ── 視覺旋鈕（僅本文件用，用戶檢驗後再調）──
// 輪次前後與會話分隔的前後間距。
#let TurnAbove = 1.4em
#let TurnBelow = 1.4em
// 時間戳：小號、暗灰。
#let TimeSize = 0.75em
#let TimeColor = luma(140)
// 提問塊與回答之間的間距。
#let QGap = 0.7em
// 人類提問塊：左側豎線（比引用塊/詞條的 #008888 亮一階，以示區分）。
#let QBarStroke = 2.5pt + Cfg.ColorRefText
#let QInset = (left: 0.75em, rest: 0.2em)

// ── md-only 判定的內部函數（不對外承諾）──
// 空白判定：space、parbreak、linebreak、純空白文字、全空白子序列。
// 字段一律走 fields().at() 取：對未證明元素類型的 content 做 .lang/.text 訪問，
// 靜態檢查報「field ... is not known at this point」（and 短路守衛它不認），實測 2026-11-06。
#let IsWs(c) = {
	if c.func() == raw { return false }
	if c == [ ] or c.func() == parbreak or c.func() == linebreak { return true }
	if c.has("text") { return c.fields().at("text", default: "").trim() == "" }
	if c.has("children") { return c.children.all(IsWs) }
	false
}

// 判定：內容是否「只含一個 lang 爲 md 的塊級 raw、別無他物」。
// 實測（2026-11-06）：貼入回答的內容塊子元素形態爲 [space, raw(block, lang:"md"), space]。
#let IsOnlyMd(body) = {
	let real = if body.has("children") {
		body.children.filter(c => not IsWs(c))
	} else {
		(body,)
	}
	if real.len() != 1 { return false }
	let Only = real.first()
	if Only.func() != raw { return false }
	Only.fields().at("lang", default: none) == "md"
}

// 取出那個 md raw 元素（只在 IsOnlyMd 爲真時調用）。
#let ExtractMd(body) = {
	if body.has("children") {
		body.children.filter(c => c.func() == raw).first()
	} else {
		body
	}
}

/// 渲染 AI 回答內容：md-only 走 cmarker，其餘原樣。
///
/// - A (content): 回答塊
/// -> content
#let Answer(A) = {
	if IsOnlyMd(A) [#Md(ExtractMd(A))] else [#A]
}

/// 會話分隔。多會話同檔時每個會話包一個；單會話可省。
///
/// - Body (content): 會話內容（通常爲若干個 #T）
/// -> content
#let Sesn(Body) = {
	HReset()
	v(TurnAbove, weak: true)
	if Target == Targets.Html {
		html.elem("hr")
	} else {
		line(length: 100%, stroke: 1pt + Cfg.ColorCodeBorder)
	}
	v(QGap)
	Body
	v(TurnBelow, weak: true)
}

/// 一輪問答。人類提問做視覺區分（左側豎線），AI 回答按原樣式。
///
/// - Time (content): 時間戳，約定格式 2026_1106_181148
/// - Q (content): 用戶提問
/// - A (content): AI 回答；僅含一個 md 代碼塊時自動以 Markdown 渲染
/// -> content
#let Round(time, question, answer) = {
	
	H[#time][
#{
if Target == Targets.Html {
		html.elem("div", attrs: (class: Html.AiQClass))[#question]
	} else {
		box(
		)[
			#block(
				stroke: Cfg.StrokeCodeBorder + Cfg.ColorCodeBorder,
				fill: rgb("#0000ff44"),
				width: 100%,
				inset: 1em,
			)[#question]
		]
		
	}
	//v(1em)
	//box(width: 100%, height: 1pt, fill: Cfg.ColorStrong)
	Answer(answer)
}
	]
	
	
	
}
