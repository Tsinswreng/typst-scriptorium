#import "Cfg.typ" as Cfg
#import "tsinswreng-auto-heading.typ": *
#import "Target.typ" as Target
// ── 概念鏈的概念登記表 ──
// 概念鏈文章的詞條數據由收集側（MkTerm／MkTerms）產出，
// 渲染側 RenderTerms 渲染詞表時把全量概念名一次性登記進來。
// 下面的 show ref（見 _Common.typ）靠它認出
// 「這個引用是概念」——認出來才接管，其餘的引用（figure 的「圖N」、
// 標題的章節號）原樣不動。
// 為甚麼要登記、不能靠元素類型認：詞條標籤附着在普通內容（block／div）上，
// Typst 對這種標籤的默認引用渲染直接報 `cannot reference block`，
// 所以必須在 show ref 裏攔下來。
// 讀取一律用 final()：正文裡的引用通常出現在文末詞條之前，
// 按位置讀會讀到一張空表。
// 文章之間互不干擾——沒登記過概念的文檔，那張表是空的，
// show ref 的概念分支永不觸發；
// 登記表按文檔隔離，一篇一張，不是跨文的全局表。
#let ConceptNames = state("tsinswreng-concept-names", ())

// ══ 概念鏈（收集側與渲染側分離） ══
// 「頂部概念登記區 + 正文提及處引用」那套寫法的實現，共四件：
// 概念登記表 ConceptNames（本文件上方）、
// 詞條收集器 MkTerm、詞表收集器 MkTerms、渲染器 RenderTerms／TermEntry（下方）。
//
// 職責邊界（2026-11-04 重構，方向：收集與渲染分離）：
// + 收集側只產數據，不碰排版決策。
//   MkTerm 解析與校驗單條詞條，產出記錄；MkTerms 彙成數組並做表級校驗。
// + 渲染側 RenderTerms 負責登記與逐條分發，
//   每條長甚麼樣由 entry 回調決定（默認 TermEntry），
//   調用方因此能自己決定渲染方式。
//
// 命名約定（2026-11-04）：記錄字段用小寫（name／title／descr），
// 造物與渲染函數用大寫（MkTerm、MkTerms、RenderTerms、TermEntry）。
// Typst 字典沒有用戶自定義方法，可排版之物以字段承載：
// 記錄三字段——
// + name（str）：數據用概念名。登記、排序、分組用。
//   **不得**拿去當標題（見 MkTerm 處的紅線）。
// + title（content）：可直接排版的標題。
//   概念名＋隱形載體，標籤紅線已在收集期處理完。
// + descr（content）：釋義。
//
// 一條詞條有兩種寫法（T 是詞表回調裏收到的 MkTerm 簡名）：
// + A（概念名寫兩遍）：#T[概念名<概念名>][詳解]
// + B（概念名只寫一遍，官方推薦）：#T[-<概念名>][詳解]
// 兩種的登記名都必須與標籤名逐字一致（引用拿標籤名查登記表）。
// 舊寫法 #MkTerm[概念名][詳解]<概念名> 已廢止（2026-11-04）：
// 其標籤附着在函數返回值上，而收集器返回的是 metadata 記錄，
// 標籤沒有可附着的排版元素；誤用會在收集期直接 panic。
//
// 前向引用包裝：編輯標記（「此條在後文才登記」），輸出原樣。
// 概念鏈要求詞條只引用排在自己前面的條目；萬一繞不開要引用後文，
// 就用 #R[@名字] 代替 @名字，渲染結果一樣，只是提醒編輯者這是前向引用。
#let R(cont) = cont

// ┊詞條收集器：只收集，不渲染。┊
// 解析第一參數的形態、校驗，把記錄裝進隱形的 metadata 元素返回。
// 爲甚麼包 metadata：Typst 代碼塊 {…} 的語義是按序拼接各表達式的值，
// 收集器直接返回裸字典會被拼進內容（要麼報錯要麼渲染成垃圾）；
// metadata 是不參與排版的隱形元素，
// MkTerms 行走元素序列時再把記錄逐一撈出來。
#let MkTerm(head, body) = {
	// 第一參數的形態分流：
	// A＝帶標籤的概念名文字（text＝名）、
	// B＝帶標籤的連字號載體（text＝"-"，名字由標籤合成）。
	let Fields = head.fields()
	let Text = Fields.at("text", default: none)
	let Lbl = Fields.at("label", default: none)
	if Text == none {
		// 概念名必須是純文字：引用靠標籤名查表，登記的必須是同一個名字。
		// 帶裝飾的內容（比如 #underline[…]）取不出 text，
		// 那就直接報錯——要的是大聲失敗，不是靜默地不回跳。
		panic("MkTerm 的第一個參數必須是純文字的概念名（或 [-<概念名>] 載體寫法）：要據它登記概念、與調用處的 <標籤> 對應")
	}
	if Lbl == none {
		// 標籤寫在調用末尾的舊寫法已廢止：
		// 收集器返回 metadata 記錄，末尾標籤沒有可附着的排版元素，
		// 引用會失去跳轉目標。
		panic("MkTerm 的第一個參數缺 <標籤>：請改用 [-<概念名>] 或 [概念名<概念名>]（標籤寫在調用末尾的舊寫法已廢止）")
	}
	if Text != "-" and str(Lbl) != Text {
		// A 形兩處名字不一致時，@標籤 在登記表裏查不到，
		// 會落到 show ref 的兜底分支直接報 cannot reference block。
		// 與其留到渲染期炸，不如收集期就大聲失敗。
		panic("概念名與標籤名不一致：「" + Text + "」≠「" + str(Lbl) + "」，兩處必須逐字一致")
	}
	// B 形（載體寫法）：概念名由標籤合成。
	let IsCarrier = Text == "-"
	let Name = if IsCarrier { str(Lbl) } else { Text }
	//
	// 紅線：標籤的源碼位置必須留在調用處（F12 直達）。
	// 唯一可行做法：**調用處寫的標籤隨原文元素裸直入文檔**（A＝display 原樣進標題）。
	// 兩類已證死的寫法（F12 全跳函數體內，勿再犯）：
	// + 標籤值取出來插值附着（#Lbl、H(label:)）——跳到插值行；
	// + 載體包進任何元素體（text(size:0pt)、box(clip)、html.elem）——
	//   跳到包裹層所在的標題序列行（舊實現實測）。
	// B 形的載體因此必須**裸放**在標題序列裏、緊跟合成的概念名，
	// PDF/LSP 靶用作用域內 set 規則縮小（純樣式上下文、不建包裹元素，與 A 同構）；
	// HTML 靶導出丟棄 text 尺寸，set 縮小無效，只能 span 行內 font-size:0 包裹
	// （HTML 構建無 F12 需求，包裹無妨）。
	//
	// title 爲何在收集期整備：把「名」造成可直接排版的形態屬數據提取
	// （[-<名>] 載體本就不能直接顯示），不是渲染決策；
	// 真正的渲染選擇（要不要 H、幾級、甚麼殼）全在 entry 回調手裏。
	// ⚠ 拿 name 當標題是能編譯通過但引用全斷的寫法（載體沒進排版，
	// 標籤無處附着）——所以可排版之名只此一份 title，name 只做數據用途。
	let Title = if IsCarrier {
		if Target == TargetHtml {
			[#Name #html.elem("span", attrs: (style: "font-size:0"))[#head]]
		} else {
			[#Name #set text(size: 0pt); #head]
		}
	} else {
		head
	}
	metadata((
		name: Name,
		head: Title,
		body: body,
	))
}

// ┊詞表收集器：彙集記錄＋表級校驗，不渲染。┊
// 用法：#let Terms = MkTerms(T => { T[-<名>][詳解] … })。
// 回調參數 T 就是上面的 MkTerm（作用域限定在回調內，不外泄）；
// 回調體是代碼塊，各 T 調用產出的 metadata 元素按序拼接，
// 這裏把元素序列歸一後撈出記錄、彙成數組返回。
// 詞表因此是顯式契約：回調體裏只允許詞條調用，
// 混入其他內容或出現重名概念都在此大聲失敗。
#let MkTerms(F) = {
	if type(F) != function {
		// 防舊式遷移錯誤：把內容塊 […] 直接傳進來（舊 API 的形狀）。
		panic("MkTerms 的參數必須是回調：(T) => { … }，詞條在回調體裏用 T[-<名>][詳解] 聲明")
	}
	let Res = F(MkTerm)
	// 歸一化（2026-11-04 探針實測）：回調體的拼接結果有三種形態——
	// 單條＝裸 metadata 元素（無 children）、
	// 多條與 for 循環＝攤平的元素序列（有 children）、
	// 空表＝none。
	let Elems = if Res == none {
		()
	} else if type(Res) != content {
		panic("MkTerms 的回調返回了非內容值（" + str(type(Res)) + "）：回調體裏只允許 T[-<名>][詳解] 的詞條調用")
	} else if Res.has("children") {
		Res.children
	} else {
		(Res,)
	}
	let Records = ()
	for Child in Elems {
		// 只認 MkTerm 造的記錄：別處自寫的 metadata（值不是帶 name 的字典）
		// 與其他任何元素一樣按外來內容拒收。
		let V = if Child.func() == metadata { Child.value } else { none }
		if type(V) != dictionary or not ("name" in V) {
			panic("MkTerms 的詞表裏混入了非詞條內容：回調體裏只允許 T[-<名>][詳解] 的詞條調用")
		}
		Records.push(V)
	}
	// 重名檢查：同名概念會讓 @引用 的跳轉目標分不清（鏈接跳錯條），
	// 且概念鏈裏一個名字本就只該對應一條詞條。
	let Seen = (:)
	for Rec in Records {
		if Rec.name in Seen {
			panic("概念重名：" + Rec.name)
		}
		Seen.insert(Rec.name, true)
	}
	Records
}

// ┊默認單條渲染：H 標題＋左豎線塊（PDF）／tswg-scrptm-term div（HTML）。┊
// 兩靶同構：內容塊共用，只有外面的包裹分靶。
// PDF 靶是左豎線的 block；HTML 靶是帶 class 的 div，
// class 名對應 Article.css 裏的 .tswg-scrptm-term（下面的默認值就是它）。
// 注意 class 只管詞條那一頭：引用那一頭的 class 固定在 show ref 裏（.tswg-scrptm-term-ref），
// 換了 class 就得自己把兩邊的 CSS 都備齊。
#let RenderTerm(term) = {
	// 兩靶共用同一段內容，故先造好再各自包裹。
	let cont = H[#term.head][
		#term.body
	]
	if Target == TargetHtml {
		html.elem("div", attrs: (class: TermClass))[#cont]
	} else {
		block(
			width: 100%,
			inset: (left: 1em, rest: 0.2em),
			above: 1.1em,
			below: 1.1em,
			stroke: (left: 3pt + ColorQuoteLeftBorder),
		)[#cont]
	}
}

// ┊渲染器：登記＋逐條分發。┊
// entry 是單條渲染回調 (Rec) => content，默認 TermEntry。
// 自定義例（每條一個裸 H 標題、無塊殼）：
//   #RenderTerms(Terms, entry: Rec => H[#Rec.title][#Rec.descr])
// 契約（編譯查不出來、違者該術語的引用全斷，只能靠文檔約束）：
// + Rec.title 必須以某種形式進文檔（標籤附在它身上）；
// + Rec.name 不得拿去當標題（載體沒進排版，標籤無處附着）。
#let RenderTerms(terms, fnRender: RenderTerm) = {
	if type(terms) != array {
		panic("RenderTerms 的參數必須是 MkTerms 返回的記錄數組")
	}
	// 一次性登記全量概念名（舊實現逐條各更新一次 state，語義等價、寫入收斂）。
	// show ref 讀 final()（見文件頭），單次批量寫入不影響其讀法。
	ConceptNames.update(List => List + terms.map(Rec => Rec.name))
	let Entry = if fnRender == none { RenderTerm } else { fnRender }
	terms.map(Entry).join()
}
