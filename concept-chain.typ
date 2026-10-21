#import "Cfg.typ": *
#import "tsinswreng-auto-heading.typ": *
#import "Target.typ": *
// ── 概念鏈的概念登記表 ──
// 概念鏈文章的詞條由各篇自己的詞條工廠（MkTerm 之類）造，每造一條就
// 用 RegisterConcept 把概念名登記進來。下面的 show ref 靠它認出
// 「這個引用是概念」——認出來才接管，其餘的引用（figure 的「圖N」、
// 標題的章節號）原樣不動。
// 為甚麼要登記、不能靠元素類型認：詞條標籤附着在普通內容（block／div）上，
// Typst 對這種標籤的默認引用渲染直接報 `cannot reference block`，
// 所以必須在 show ref 裏攔下來。
// 讀取一律用 final()：正文裡的引用通常出現在文末詞條之前，
// 按位置讀會讀到一張空表。
#let ConceptNames = state("tsinswreng-concept-names", ())
#let RegisterConcept(name) = ConceptNames.update(list => list + (name,))

// ══ 概念鏈（渲染側） ══
// 「頂部概念登記區 + 正文提及處引用」那套寫法的實現，共三件：
// 概念登記表 ConceptNames／RegisterConcept（本文件上方）、
// 詞條工廠 MkTerm（這裏）、引用渲染（下面的 show ref）。
//
// 為甚麼要登記表、不能靠元素類型認概念：
// 詞條標籤附着在普通內容（PDF 靶的 block、HTML 靶的 div）上，
// Typst 對這種標籤的默認引用渲染直接報 `cannot reference block`。
//
// 一條詞條有三種寫法，共用本工廠，兩靶都可渲染、可在同一檔混用：
// + A（概念名寫兩遍）：#MkTerm[概念名<概念名>][詳解]
// + B（概念名只寫一遍，官方推薦）：#MkTerm[-<概念名>][詳解]
// + 舊寫法（兼容存量）：#MkTerm[概念名][詳解]<概念名>
// 三種的登記名都必須與標籤名逐字一致（引用拿標籤名查登記表）。
//
// 紅線：標籤的源碼位置必須留在調用處（F12 直達）。
// 唯一可行做法：**調用處寫的標籤隨原文元素裸直入文檔**（A/舊＝display 原樣進標題）。
// 兩類已證死的寫法（F12 全跳函數體內，勿再犯）：
// + 標籤值取出來插值附着（#Lbl、H(label:)）——跳到插值行；
// + 載體包進任何元素體（text(size:0pt)、box(clip)、html.elem）——
//   跳到包裹層所在的標題序列行（L83 實測）。
// B 的載體因此必須**裸放**在標題序列裏、緊跟合成的概念名，
// PDF/LSP 靶用作用域內 set 規則縮小（純樣式上下文、不建包裹元素，與 A 同構）；
// HTML 靶導出丟棄 text 尺寸，set 縮小無效，只能 span 行內 font-size:0 包裹
// （HTML 構建無 F12 需求，包裹無妨）。
// 文章之間互不干擾——沒登記過概念的文檔，那張表是空的，
// show ref 的概念分支永不觸發，figure 的「圖N」與標題的章節號一概照舊。
// 登記表讀的是 final()（全篇最末的值），因為正文的引用都在文末詞條之前。
// 但**不要**為此把登記表當成跨文的全局表：它按文檔隔離，一篇一張。
//
// 兩靶同構：內容塊共用，只有外面的包裹分靶。
// PDF 靶是左豎線的 block；HTML 靶是帶 class 的 div，
// class 名對應 Article.css 裏的 .mvn-term（下面的默認值就是它）。
// 注意 class 只管詞條那一頭：引用那一頭的 class 固定在 show ref 裏（.mvn-term-ref），
// 換了 class 就得自己把兩邊的 CSS 都備齊。
#let MkTerm(
	display,
	descr,
	class: "mvn-term",
	bar-color: ColorQuoteLeftBorder,
) = {
	// 三種寫法在第一個參數的形態上分流：
	// A＝帶標籤的概念名文字（text＝名）、
	// B＝帶標籤的連字號載體（text＝"-"，名字由標籤合成）、
	// 舊＝純文字無標籤（標籤在調用末尾、附着在詞條塊上）。
	let Fields = display.fields()
	let Text = Fields.at("text", default: none)
	let Lbl = Fields.at("label", default: none)
	let IsCarrier = Text == "-" and Lbl != none
	if not IsCarrier and Text == none {
		// 概念名必須是純文字：引用靠標籤名查表，登記的必須是同一個名字。
		// 帶裝飾的內容（比如 #underline[…]）取不出 text，
		// 那就直接報錯——要的是大聲失敗，不是靜默地不回跳。
		panic("MkTerm 的第一個參數必須是純文字的概念名（或 [-<概念名>] 載體寫法）：要據它登記概念、與調用處的 <標籤> 對應")
	}
	RegisterConcept(if IsCarrier { str(Lbl) } else { Text })
	// 詞條標題。A/舊：display 原樣進標題（標籤隨原文、F12 跳調用處）。
	// B：合成名字＋裸載體直入標題序列——不得包進任何元素體（見文件頭紅線）。
	// PDF/LSP：載體後置，用作用域內 set 規則縮成零號字（樣式上下文、不包裹）；
	// HTML：span 行內 font-size:0（導出丟棄 text 尺寸；此靶無 F12 需求）。
	let Title = if IsCarrier {
		if Target == TargetHtml {
			[#str(Lbl) #html.elem("span", attrs: (style: "font-size:0"))[#display]]
		} else {
			[#str(Lbl) #set text(size: 0pt); #display]
		}
	} else {
		display
	}
	// 兩靶共用同一段內容，故先造好再各自包裹。
	let Body = H[#Title][
		#descr
	]
	if Target == TargetHtml {
		html.elem("div", attrs: (class: class))[#Body]
	} else {
		block(
			width: 100%,
			inset: (left: 1em, rest: 0.2em),
			above: 1.1em,
			below: 1.1em,
			stroke: (left: 3pt + bar-color),
		)[#Body]
	}
}

