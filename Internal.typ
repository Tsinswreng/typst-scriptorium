#import "Enum/Cfg.typ" as Cfg
// 列表層級標記數組（原生默認 •‣– 循環），供 _Show 的列表手動重造用。
#let ListMarkers = ([•], [‣], [–])

// 列表手動重造（PDF 靶）：首行縮進（D×縮進量）、續行頂格。
// 不用計數器/introspection——list.item 不可定位、
// show 規則裏 emit 的 counter update 對嵌套 item 讀值不可靠（均實測踩過）。
// 深度與編號路徑由遞歸參數顯式攜帶；嵌套列表靠 item 塊內的作用域 show 規則
// 接管（show 規則能穿透 styled 等包裝，手動 walk children 穿不透，已踩）。
#let ListRender(It, Depth) = {
	It.children
		.filter(c => c.func() == list.item)
		.enumerate()
		.map(Pair => {
			let Item = Pair.at(1)
			block(above: 1em, below: 1em)[
				#h(Cfg.ListIndent * Depth)
				#text(fill: Cfg.ColorListNum)[#ListMarkers.at(calc.rem(Depth - 1, ListMarkers.len()))]
				#h(0.5em)
				#{
					show list: it => ListRender(it, Depth + 1)
					show enum: it => EnumRender(it, Depth + 1)
					Item.body
				}
			]
		})
		.join()
}
#let EnumRender(It, Depth, Path: ()) = {
	It.children
		.filter(c => c.func() == enum.item)
		.enumerate()
		.map(Pair => {
			let Item = Pair.at(1)
			let NumPath = Path + (Pair.at(0) + 1,)
			block(above: 1em, below: 1em)[
				#h(Cfg.EnumIndent * Depth)
				#text(fill: Cfg.ColorListNum)[#numbering("1.", ..NumPath)]
				#h(0.5em)
				#{
					show list: it => ListRender(it, Depth + 1)
					show enum: it => EnumRender(it, Depth + 1, Path: NumPath)
					Item.body
				}
			]
		})
		.join()
}
