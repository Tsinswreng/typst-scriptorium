#import "Enum/Cfg.typ" as Cfg
#import "Internal.typ": ListMarkers

// ══ 列表門面（容器式）══
// 用法：
//   #Ol[
//     #L[項一]
//     #L[小題][項二的正文]
//   ]
//   #Ul[ ... ]
// 每個容器是一個實例：進場把有序計數歸零、出場還原，
// 所以兩個 Ol 各自從 1 重數，容器嵌在項裏時也自成另一個實例。
// 有序編號用每層一支原生 counter（最多 8 層），深度用 state 相對加減。
// 無序的標記沿用 Internal.typ 的 ListMarkers。
//
// 三個實測坑（改動前先看）：
// + state.update 的閉包裏不得讀另一個 state（如 `Base.update(_ => Depth.get())`），
//   否則整份文檔不收斂、早期輪次報錯。要先 let 出來再傳進去。
// + counter.get() 讀不到同一個 context 裏剛做的 step()，拿到的是步進前的值；
//   當前那一層要用「舊值加一」，其餘層正常 get()。
// + 早期佈局輪次裏容器狀態還沒寫進來，Kind 可能是 none，不可 panic；
//   退化成紅色問號即可，最後一輪自然正確，真寫在容器外時那顆問號會留下。
//
// HTML 靶暫與 PDF 靶同一套內容（block 加 inline 縮進），樣式待補。

#let _MaxDepth = 8
#let _ItemSpacing = 1em
#let _Indent = Cfg.ListIndent
#let _NumberingPattern = "1."
#let _Depth = state("tswg-scrptm-list-depth", 0)
#let _Base = state("tswg-scrptm-list-base", 0)
#let _Kind = state("tswg-scrptm-list-kind", none)
#let _CN(d) = counter("tswg-scrptm-list-ol-" + str(d))

// 判斷正文是否以塊級元素開頭（例如正文只有子項、或直接放了 block）。
// 這種情況不能給正文加首行縮進的 h()，否則會多出一個空行。
// 嵌套的 L 產物是 context 元素，用 (context [ ]) 取它的 func 作比對。
#let _ContextFunc = (context [ ]).func()
#let _IsBlocky(c) = {
	let kids = if c.has("children") { c.children } else { (c,) }
	let first = kids.find(x => {
		if x == [ ] { return false }
		let f = x.func()
		return not (f == parbreak or f == linebreak)
	})
	if first == none { return false }
	let f = first.func()
	f == _ContextFunc or f == block or f == list or f == enum or f == grid or f == table or f == figure or f == image
}

// 容器：進場存下各層計數、Base、Kind，有序的把計數歸零；出場按相反順序還原。
#let _MkList(kind, body) = context {
	let savedBase = _Base.get()
	let savedKind = _Kind.get()
	let base = _Depth.get()
	let savedC = range(_MaxDepth).map(i => _CN(i).get())
	if kind == "ol" {
		for i in range(_MaxDepth) { _CN(i).update(_ => 0) }
	}
	_Base.update(_ => base)
	_Kind.update(_ => kind)
	body
	_Kind.update(_ => savedKind)
	_Base.update(_ => savedBase)
	if kind == "ol" {
		for i in range(_MaxDepth) { _CN(i).update(_ => savedC.at(i)) }
	}
}

/// 有序列表的容器。內容裏用 `L` 寫項。
///
/// - body (content): 容器內容
/// -> content
#let Ol(body) = _MkList("ol", body)

/// 無序列表的容器。內容裏用 `L` 寫項。
///
/// - body (content): 容器內容
/// -> content
#let Ul(body) = _MkList("ul", body)

/// 列表項，形狀對齊 `auto-heading` 的 `#H[題][文]`。
///
/// - 一個參數（`L[正文]`）：正文就是這一項的內容；
/// - 兩個參數（`L[小題][正文]`）：小題獨佔首行，正文另起一行。
/// -> content
#let L(..args) = context {
	let kind = _Kind.get()
	if kind == none { kind = "none" }
	let d = _Depth.get()
	let base = _Base.get()
	_Depth.update(n => n + 1)
	let p = args.pos()
	let title = p.at(0)
	let body = if p.len() > 1 { p.at(1) } else { none }
	// 縮進照項目列表的慣例：頂層也要縮一個單位（Render 的 Depth 從 1 起算）。
	let indent = _Indent * (d + 1)
	let marker = if kind == "ol" {
		let prevCur = _CN(d).get().at(0)
		_CN(d).step()
		for i in range(d + 1, _MaxDepth) { _CN(i).update(_ => 0) }
		let nums = range(base, d + 1).map(i => if i == d { prevCur + 1 } else { _CN(i).get().at(0) })
		numbering(_NumberingPattern, ..nums)
	} else if kind == "ul" {
		ListMarkers.at(calc.rem(d - base, ListMarkers.len()))
	} else {
		//text(fill: red)[?]
	}
	block(above: _ItemSpacing, below: _ItemSpacing, breakable: true)[
		#set par(first-line-indent: 0pt)
		#h(indent)
		#text(fill: Cfg.ColorListNum)[#marker]
		#h(0.5em)
		#if body == none { title } else if _IsBlocky(body) {
			title + linebreak() + body
		} else {
			title + linebreak() + h(indent) + body
		}
	]
	_Depth.update(n => n - 1)
}
