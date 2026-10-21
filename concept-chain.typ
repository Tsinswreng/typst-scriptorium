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
// 一條詞條寫成
//   #MkTerm[概念名<概念名>][詳解]
// 標籤寫在第一個參數裏、緊跟概念名（中間不留空格）：
// 源碼直讀時 @概念名 F12 跳到詞條開頭。
// 標籤按 Typst 規則附着在概念名文字上、隨詞條標題渲染，
// 錨點因此落在詞條標題處；引用照舊按標籤名查登記表。
// 標籤名要與概念名逐字一致：引用時拿標籤名查登記表。
// 舊寫法 #MkTerm[概念名][詳解]<概念名>（標籤在條目末尾、附着在整個詞條塊上）
// 仍然可用，兩種寫法可在同一檔混用、逐條遷移；新條目一律用開頭寫法。
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
	// 概念名必須是純文字：引用靠標籤名查表，登記的必須是同一個名字。
	// 帶裝飾的內容（比如 #underline[…]）取不出 text，
	// 那就直接報錯——要的是大聲失敗，不是靜默地不回跳。
	let Name = display.fields().at("text", default: none)
	if Name == none {
		panic("MkTerm 的第一個參數必須是純文字的概念名：要據它登記概念、與調用處的 <標籤> 對應")
	}
	RegisterConcept(Name)
	// 兩靶共用同一段內容，故先造好再各自包裹。
	let Body = H[#display][
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

