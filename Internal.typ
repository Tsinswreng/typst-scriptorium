#import "Enum/Cfg.typ" as Cfg
// 列表層級標記數組（原生默認 •‣– 循環），供 _Show 的列表手動重造用。
#let ListMarkers = ([•], [‣], [–])

// 列表手動重造（PDF 靶）：首行縮進（D×縮進量）、續行頂格。
// 不用計數器/introspection——list.item 不可定位、
// show 規則裏 emit 的 counter update 對嵌套 item 讀值不可靠（均實測踩過）。
// 深度與編號路徑由遞歸參數顯式攜帶；嵌套列表靠 item 塊內的作用域 show 規則
// 接管（show 規則能穿透 styled 等包裝，手動 walk children 穿不透，已踩）。
// 2026-11-16 起合併爲單一 Render：Typst 頂層 #let 閉包互相引用非法
// （兄弟函數不論定義先後，引用對方都報 unknown variable，雙向實測），
// 舊 ListRender/EnumRender 兩函數互調，在「list 項內嵌 enum」時必炸
// （CertWeekReport/W47-1.typ 首例觸發）。
// list 與 enum 的差異（過濾目標、縮進量、標記）按 It.func() 分派；
// 編號路徑只在 enum 鏈上攜帶，list 項內的嵌套 enum 從 1 重新編號（與舊行爲一致）。
#let Render(It, Depth, Path: ()) = {
	let IsEnum = It.func() == enum
	let ItemKind = if IsEnum { enum.item } else { list.item }
	let Indent = if IsEnum { Cfg.EnumIndent } else { Cfg.ListIndent }
	It.children
		.filter(c => c.func() == ItemKind)
		.enumerate()
		.map(Pair => {
			let Item = Pair.at(1)
			let NumPath = Path + (Pair.at(0) + 1,)
			// 傳給嵌套 enum 的編號路徑：enum 項延續自身路徑，list 項歸零。
			let ChildEnumPath = if IsEnum { NumPath } else { () }
			block(above: 1em, below: 1em)[
				// 首行縮進歸零：本函數已用 h(縮進量×Depth) 承擔列表縮進，
				// 項內不能再吃一次 _Show 的全局 first-line-indent，
				// 否則項內含塊級元素（如代碼塊）時，標記行會被多縮進一次，
				// 與同層級其他項的標記對不齊。
				#set par(first-line-indent: 0pt)
				#h(Indent * Depth)
				#text(fill: Cfg.ColorListNum)[#(if IsEnum { numbering("1.", ..NumPath) } else { ListMarkers.at(calc.rem(Depth - 1, ListMarkers.len())) })]
				#h(0.5em)
				#{
					show list: it => Render(it, Depth + 1)
					show enum: it => Render(it, Depth + 1, Path: ChildEnumPath)
					Item.body
				}
			]
		})
		.join()
}
