#import "Enum/Cfg.typ" as Cfg
#import "Enum/Html.typ" as Html
#import "tsinswreng-auto-heading.typ": *
#import "Enum/Targets.typ" as Targets
#import "Target.typ": *
#import "concept-chain.typ": *
#import "Img.typ" as Img
#import "AiSesn.typ" as AiSesn
#import "@preview/cuti:0.4.0": regex-fakebold, show-cn-fakebold, show-cn-fakeitalic
#import "@preview/numbly:0.1.0": numbly
#import "@preview/cmarker:0.1.10"
#let Md = cmarker.render
#let MkImg = Img.MkImg
#let MkImgGen = Img.MkImgGen

// 舊寫法段落：只負責切段（v），不再加 h(Cfg.CustomPIndent)。
// 2026-11-05 起首行縮進由 _Show 的 set par(first-line-indent) 全局承擔；
// 若保留 h()，它會與全局縮進相加成 4em（實測：P 行 82.5pt、普通段 49.5pt、頁邊 16.5pt）。
// 保留本函數只是為了讓舊文檔不必改寫。
#let P(C) = {
	v(Cfg.CustomPSpacing)
	C
}

// 不縮進的段落。用法與「改造前直接寫」相同：首行頂格。
// PDF 靶：顯式造一個 first-line-indent: 0pt 的段落，只作用這一段。
// HTML 靶：導出 <p class="tswg-scrptm-no-indent">，由 Article.css 的 text-indent: 0 壓回。
// 只支援單一段落；內容裏再有塊級元素（列表等）請另行包裝。
#let NoIndent(C) = if Target == Targets.Html {
	html.elem("p", attrs: (class: Html.NoIndentClass))[#C]
} else {
	par(first-line-indent: 0pt, C)
}
#let U(C) = {
	underline(C)
}

#let Lang = sys.inputs.at("Lang", default: "zh-Hant")
#let LangParts = Lang.split("-")
#let TypstLang = LangParts.first()
#let LangFamily = if LangParts.len() >= 2 {
	LangParts.at(0) + "-" + LangParts.at(1)
} else {
	Lang
}

#let FigureSupplement = if LangFamily == "zh-Hant" {
	[圖]
} else if LangFamily == "zh-Hans" or TypstLang == "zh" {
	[图]
} else if TypstLang == "en" {
	[Figure]
} else {
	auto
}
#let TableSupplement = if LangFamily == "zh-Hant" or LangFamily == "zh-Hans" or TypstLang == "zh" {
	[表]
} else if TypstLang == "en" {
	[Table]
} else {
	auto
}
#let FigureKindSupplement(Kind) = {
	if Kind == table {
		TableSupplement
	} else {
		FigureSupplement
	}
}
#let FigureKindText(Kind) = {
	if Kind == table {
		if LangFamily == "zh-Hant" or LangFamily == "zh-Hans" or TypstLang == "zh" {
			"表"
		} else if TypstLang == "en" {
			"Table"
		} else {
			"Table"
		}
	} else if LangFamily == "zh-Hant" {
		"圖"
	} else if LangFamily == "zh-Hans" or TypstLang == "zh" {
		"图"
	} else if TypstLang == "en" {
		"Figure"
	} else {
		"Figure"
	}
}




#let Todo(Title, Body) = {
	text(red)[#U(Title)]
	linebreak()
	box(fill: rgb("#550000"))[#Body]
}

#let Wip(Title, Body) = {
	text(yellow)[#U(Title)]
	linebreak()
	box(fill: rgb("#555500"))[#Body]
}



#let _Document(
	path,
	format: auto,
	title: none,
	author: (), //str[]
	description: none,
	keywords: (), //str[]
	date: auto,
	body,
) = {
	if Targets.IsBundle {
		document(
			path,
			format: format,
			title: title,
			author: author,
			description: description,
			keywords: keywords,
			date: date,
		)[#body]
	} else {
		body
	}
}


//#let BaseStroke = 0.05em
#let HtmlDocument(body) = [
	#html.elem("article", attrs: (class: Html.ArticleClass))[#body]
]

#let _Outline()={
	
}

#let _Show(d) = {
	import "Internal.typ": *
	let PageHeight = if Target == Targets.Html {
		auto
	} else { //TODO 多傳入一個 「是否分頁」參數。
		//841.89pt
		21cm // A5 長邊, 若A4則 29.7 cm
		//auto //不分頁則tinymist預覽時會卡
	}

	// 底邊距要爲頁碼留出空間。
	// 頁碼被放在正文本區下沿、再按 footer-descent 下沉，
	// 底邊距太薄（如原來的 1em）會讓頁碼貼住紙邊。
	set page(
		margin: (rest: 1em, bottom: 2.4em),
		fill: Cfg.ColorBack,
		height: PageHeight,
		//width: 14.8cm, // A5短邊 改寬度會出問題, 在typstᶤ繪ʹ圖表中 如鍵位圖等。解決此問題前 勿改頁寬。
		// 頁碼。默認 number-align 是 center + bottom，即底部居中。
		numbering: "1",
		// 默認 30% 會把頁碼放在正文末行正下方、其下留大片空白；
		// 實測 60% 落在紙底上方約 2–5mm；
		// 80% 起又貼紙邊，100% 會被推出頁面。
		footer-descent: 60%,
	)
	

	// HTML 靶：CSS 的 strong 規則同色（見頂部「HTML 靶樣式」註釋）。
	show strong: set text(Cfg.ColorStrong)
	//show heading: set text(rgb("00ffff"))
	// 一級標題居中；二級起保持左對齊。
	// HTML 靶：CSS 的 h2 規則同樣居中（本站 h1 留給題名、頁面標題在 hero 裏）。
	show heading.where(level: 1): set align(center)
	// 標題前後間距：PDF 靶二級起與 HTML 靶各級走這條 show-set；
	// 一級 PDF 靶走下方自訂 block（引用同一對變量）。
	// typst 0.13 起 heading 的 above/below 參數已移除，
	// 須 show-set 到 block 上（官方遷移寫法）。
	show heading: set block(above: Cfg.SpacingHeadingAbove, below: Cfg.SpacingHeadingBelow)
	// 正文行距。行距是段落級屬性，只能走全局 set par（無法進 P()）；
	// 「不引入全局 set par」的舊決策只針對首行縮排與段距，不涵蓋 leading。
	// 首行縮進：常規段落全局縮進，寫文章時不必再套 P()（2026-11-05 起）。
	// all: true 是關鍵——簡寫 first-line-indent: 2em 等於 all: false，
	// 「區塊第一段」會被跳過，也就是標題後第一段不縮（舊印象的來源）。
	// 實測不受影響：標題、列表、代碼塊、表格單元格、圖表 caption、Todo/Wip 框；
	// 塊引用在 quote 的 show 規則裏另行歸零，保持一貫頂格。
	set par(
		leading: Cfg.SpacingLeading,
		spacing: Cfg.ParSpacing,
		first-line-indent: (amount: Cfg.CustomPIndent, all: true),
)
	// 一級標題：下方粗短線，後距加大。
	// 實作用 box 底邊框：編號+題文放進 shrink-wrap 的 box，
	// bottom stroke 即下劃線，線長天然等於文字寬、不會衝過。
	// （曾試 measure 量寬再畫 line，實測量出的寬度不對、線遠超文字，已棄。）
	// 線寬 2.5pt（細線在黑底不可見的教訓）。
	// HTML 靶：底線寬度爲 0，無對應裝飾；前後距由 CSS 的 h2 margin 對齊。
	show heading.where(level: 1): it => context {
		if Target == Targets.Html {
			it
		} else {
			let nums = counter(heading).at(it.location())
			block(sticky: true, width: 100%, above: Cfg.SpacingHeadingAbove, below: Cfg.SpacingHeadingBelow)[
				#align(center)[
					#box(
						// 0.35em：避開 1.2em 大號「|」分隔符的下探部分，
						// 太淺會與其重疊成亮斑。
						inset: (bottom: 0.35em),
						stroke: (bottom: 0pt /* 2.5pt */ + Cfg.ColorCodeBorder),
					)[
						// outline() 的合成目錄標題 level 亦爲 1、numbering 顯式爲 none，
						// 不守衛直接調 it.numbering 會報 expected function, found none。
						#if it.numbering != none [#(it.numbering)(..nums)] #it.body
					]
				]
			]
		}
	}
	show heading.where(level: 1): set text(size: 1em)
	show heading.where(level: 2): set text(size: 1em)
	show heading.where(level: 3): set text(size: 1em)
	show heading.where(level: 4): set text(size: 1em)

	show title: it => {
		// 題名是 flow 首元素，block 的 above 屬 weak 間距、在 flow 開頭被丟棄，
		// 故上方距用 weak: false 的 v 硬推（title 恆居文檔開頭，無中段疊加之虞）。
		v(Cfg.SpacingTitleAbove, weak: false)
		block(below: Cfg.SpacingTitleBelow)[
			#box(
				// 0.35em：避開 1.2em 大號「|」分隔符的下探部分，
				// 太淺會與其重疊成亮斑。
				inset: (bottom: 0.35em),
				stroke: (bottom: Cfg.ColorVertBarSize + Cfg.ColorTitleUnderbar),
			)[#it]
		]
	}

	let Styled = {
		set text(lang: TypstLang)
		show figure: set figure(
			supplement: FigureKindSupplement,
			//placement:
		)
		// 表格 figure：caption 顯示在表上方、整體允許跨頁（用戶 2026-10-29 要求）。
		// 僅 kind 爲 table 的 figure 受影響；圖片 figure 的 caption 仍在下方、不可跨頁。
		// 跨頁寫法按官方文檔：figure 本身無 breakable 參數，
		// 靠 show-set 到內層 block 上（內容可斷時 figure 即可斷）。
		show figure.where(kind: table): set figure.caption(position: top)
		show figure.where(kind: table): set block(breakable: true)
		// figure 保留各自的 kind，
		// 但圖注與引用都使用同一個全局 figure 計數器。
		show figure.caption: it => context {
			let Number = counter(figure).at(it.location()).first()
			let Caption = [
				#(FigureKindText(it.kind) + str(Number) + it.separator)
				#it.body
			]

			// HTML 靶：CSS 的 figcaption 規則同字號同色。
			set text(
				size: Cfg.FigureCaptionTextSize,
				Cfg.FigureCaptionTextColor,
			)
			if Target == Targets.Html {
				// 表格的 figcaption 掛 class：
				// position: top 使 HTML 導出的 DOM 順序天然是 figcaption 在 table 前，
				// 無需 CSS 重排；class 只供 Article.css 把間距挪到 caption 與表之間。
				if it.kind == table {
					html.elem("figcaption", attrs: (class: Html.TableCaptionClass))[#Caption]
				} else {
					html.elem("figcaption")[#Caption]
				}
			} else {
				Caption
			}
		}
		show ref: it => context {
			// 注意變量名：被引用的那個元素**不能**叫 Target——
			// 那是全局的靶別常量，一遮蔽，下面 `Target == Targets.Html` 就恆假，
			// HTML 靶會誤走 PDF 那一支（曾經踩過：HTML 裏少了 class、
			// 還多出一層下劃線）。
			let Refd = it.element
			if Refd != none and Refd.func() == figure {
				let Number = counter(figure).at(Refd.location()).first()
				let Label = FigureKindText(Refd.kind) + str(Number)
				box[
					#link(Refd.location())[
						#set text(Cfg.ColorRefText)
						#underline(stroke: Cfg.ColorRefUnderline + 0.1em)[
							#Label
						]
					]
				]
			} else if it.target != none and str(it.target) in ConceptNames.final() {
				// 概念鏈的引用：顯示概念名（標籤名即概念名，由 RenderTerms 登記）。
				// 這一支必須排在最後那個 else 之前：詞條標籤附着在普通內容
				// （block／div）上，一旦落到 else 就會去渲染 `it`，
				// 直接報 `cannot reference block`。
				// HTML 靶這一支只造一條可點的鏈接，**不要掛 id**：
				// 錨點在詞條那一頭，引用這一頭再掛同名 id 就是全篇重複 id，
				// 瀏覽器認文檔順序裏第一個，點 @概念 就跳到正文裏第一處引用去了。
				if Target == Targets.Html {
					// link 先生成再插值：內層調用緊貼內容變量時，
					// HTML 導出會把內層調用整段當字面文字輸出。
					let Inner = link(it.target)[#str(it.target)]
					html.elem("span", attrs: (class: Html.TermRefClass))[#Inner]
				} else {
					// 下劃線已按用戶要求移除：顏色由下方 show link 統一上，
					// 概念標籤那一支不包 U（與 HTML 靶一致）。
					link(it.target)[#str(it.target)]
				}
			} else {
				box[
					#underline(stroke: Cfg.ColorRefUnderline)[#it]
				]
			}
		}
		// 概念引用不加下劃線（用戶 2026-10-01 要求，兩靶一致）：
		// 鏈接目標是已登記的概念標籤時原樣返回（保色、不包 U），
		// 其餘鏈接（外部 URL、圖N、目錄）照舊下劃線。
		// 注意：show 規則原樣返回元素會落回更外層的同類規則，
		// 故在文檔級另寫 show link 壓不掉這條——改樣式只能改這裏（實測）。
		show link: it => context {
			set text(Cfg.ColorLinkText)
			if type(it.dest) == label and str(it.dest) in ConceptNames.final() {
				it
			} else {
				U[#it]
			}
		}
		show title: set align(center)
		let ShowCjkTypography(body) = {
			show regex(Cfg.CjkChars): set text(font: "Noto Serif SC") // Times New Roman
			show: show-cn-fakebold
			show: show-cn-fakeitalic
			show text.where(weight: "regular"): it => regex-fakebold(
				//reg-exp: Cfg.CjkChars,
				stroke: Cfg.CjkStroke_Regular,
				weight: "regular",
				it,
			)

			show text.where(weight: "bold"): it => regex-fakebold(
				reg-exp: Cfg.CjkChars,
				stroke: Cfg.CjkStroke_Bold,
				weight: "bold",
				it,
			)
			body
		}

		show: ShowCjkTypography

		set text(
			size: Cfg.TextSize,
			//stroke: 0.02em + Cfg.ColorFore,
			Cfg.ColorFore,
			//font: "Consolas",
			//stroke: BaseStroke
		)

		// token 配色: VSCode Dark Modern 主題，移植自
		// dark_vs + dark_plus + 用戶 tokenColorCustomizations，
		// 詳見 DarkModern.tmTheme。
		// 主題默認色等於環境色的 token 不帶 span，
		// 普通文本因此落到各條兜底規則：
		// 塊級代碼（含無 lang 者）跟正文同白，
		// 行內代碼白字加框（chip）。
		set raw(theme: "DarkModern.tmTheme")

		show raw: set text(
			font: ("Consolas", "Noto Serif SC"),
			// 代碼字號：實測仍是正文的 0.8em（13.2pt），不是正文大小。
			// 原因：Typst 內建 raw show-set 是 0.8em，此處的 1em 錨定在收縮後的
			// 尺寸上，是空操作。量法：同一串 14 個 M，正文（Consolas 16.5pt）
			// 寬 127pt，代碼塊內寬 101.5pt，比值 0.8。
			// 要真的除回去得寫 1.25em（1 / 0.8）；但在改 PDF 靶之前先維持現狀，
			// 因為 HTML 靶的 Article.css 是按實測值 0.8em（--tswg-scrptm-code-em）對齊的，
			// 兩邊要同時改。語言標籤的 0.8em 也錨在這個尺寸上（實測 10.56pt）。
			size: Cfg.RawTextSize,
			//fill: rgb("00ffff")
		)
		show raw.where(block: true): it => {
			if Target == Targets.Html {
				// HTML 導出不翻譯 block 的 fill/stroke，故輸出帶 class 的 div 包住 pre。
				// 底色、邊框、內距、無圓角全由 CSS 提供（見頂部「HTML 靶樣式」註釋）；
				// 不寫行內 style，避免同一件事有兩份值。
				html.elem("div", attrs: (class: Html.CodeBlockClass))[
					#box(width: 100%)[#it]
				]
			} else {
				block(
					width: 100%,
					fill: Cfg.ColorCodeBack,
					stroke: Cfg.StrokeCodeBorder + Cfg.ColorCodeBorder,
					inset: 0.75em,
					//radius: 2pt,
				)[
					// 語言標籤：代碼塊內右上角、代碼之上單獨一行。
					// lang 取自圍欄 info string；無 lang 的塊整行不出現。
					// HTML 靶：由 CSS 讀 code 的 data-lang 屬性生成同一行標籤。
					#if it.lang != none [
						#block(width: 100%, below: 0.4em)[
							#align(right)[
								#text(
									size: Cfg.CodeLangLabelTextSize,
									fill: Cfg.ColorCodeLangLabel,
								)[#it.lang]
							]
						]
					]
					#it
				]
			}
		}
		// 行內代碼：白字 + 與塊級代碼同底色同邊框的 chip。
		// 橫向 inset 提供內距；縱向用 outset 擴框、不佔行高。
		// box 不可跨行，過長內容會整塊跳行。
		// HTML 靶不翻譯 box 的 fill/stroke，
		// 樣式由 CSS 的 code 規則提供（源檔見頂部「HTML 靶樣式」註釋）。
		show raw.where(block: false): it => {
			if Target == Targets.Html {
				it
			} else {
				box(
					fill: Cfg.ColorInlineCodeBack,
					//stroke: Cfg.StrokeCodeBorder + Cfg.ColorCodeBorder,
					inset: (x: Cfg.RawInset),
					outset: (y: Cfg.RawInset),
				)[#set text(fill: Cfg.ColorFore); #it]
			}
		}
		// 引用塊：與多行代碼塊同底色，左側粗線、其餘三邊細框。
		// HTML 導出不翻譯 block 的 fill/stroke，分靶處理。
		show quote.where(block: true): it => {
			if Target == Targets.Html {
				// 用 blockquote 保住語義（Typst 內建 HTML 規則本來也導 blockquote，
				// 本規則接管只是為了加 class，故沿用同一標籤）。
				// 樣式在 CSS 裏（Article.css 與 site.css 的 .tswg-scrptm-quote），與 PDF 靶用同一組值。
				html.elem("blockquote", attrs: (class: Html.QuoteClass))[#it.body]
			} else {
				// 引用塊不參與全局首行縮進，保持改造前一貫頂格。
				// 不歸零的話，多段引用會縮、單段引用不縮（block 內單段的 all 怪癖），行爲還不一致。
				set par(first-line-indent: 0pt)
				block(
					width: 100%,
					fill: Cfg.ColorQuoteBack,
					stroke: (
						left: 3pt + Cfg.ColorQuoteLeftBorder,
						//rest: Cfg.StrokeCodeBorder + Cfg.ColorQuoteBorder,
					),
					inset: (left: 1em, rest: 0.75em),
					above: Cfg.SpacingQuote,
					below: Cfg.SpacingQuote,
					//radius: 2pt,
					breakable: true,
					it.body,
				)
			}
		}

		// 表格天生可跨頁（無 breakable 參數）；
		// 被 figure 包住時不跨頁的瓶頸在 figure（不可斷塊），
		// 已由上方 show figure.where(kind: table): set block(breakable: true) 解決。
		set table(
			stroke: Cfg.ColorFore,
			// 每個單元格的文字上下居中（用戶 2026-10-29 要求）。
			// horizon 只指定垂直分量，水平對齊沿用默認；
			// 個別表若在調用處傳 align: 會整體覆蓋此值（本倉庫現無此用法）。
			align: horizon,
		)
		// 標題編號：數字染 ColorNum，「|」分隔符樣式見下。標題文字保持正文白。
		// numbly 只出數字，分隔符由包裝函數追加着色；
		// 走 numbering 函數而非 show 規則，
		// 默認布局、間距、hanging-indent、refs、outline 均不受影響。
		// HTML 靶丟棄 text(fill:)，故改掛 class 交給 CSS 上色，兩靶視覺一致。
		let NumOnly = numbly(
			"{1:1}",
			"{1}.{2}", // use {level:format} to specify the format
			"{1}.{2}.{3}",
			"{1}.{2}.{3}.{4}",
			"{1}.{2}.{3}.{4}.{5}",
			// numbly 的 pattern 用完後深層編號格式會突變，
			// 故補到第 8 層。
			"{1}.{2}.{3}.{4}.{5}.{6}",
			"{1}.{2}.{3}.{4}.{5}.{6}.{7}",
			"{1}.{2}.{3}.{4}.{5}.{6}.{7}.{8}",
		)

		let HeadingNumbering(..nums) = {
			if Target == Targets.Html {
				let Num = html.elem("span", attrs: (class: Html.HeadingNumClass))[#NumOnly(..nums)]
				// 開頭那個空格必須寫成 ~（不換行空格）：
				// 內容塊首尾的**普通空格**會被 HTML 導出削掉，
				// 於是「編號 | 標題」在 HTML 靶只剩 | 後面那個空格，
				// 編號與 | 緊貼在一起。~ 是真字符，不會被削。
				// PDF 靶那一支不動，仍用普通空格。
				let Bar = html.elem("span", attrs: (class: Html.HeadingBarClass))[~|]
				Num + Bar
			} else {
				(
					text(fill: Cfg.ColorHeadingNum)[#NumOnly(..nums)]
						+ text(
							fill: Cfg.ColorVertBar,
							size: 1.2em,
							stroke: 0.02em + Cfg.ColorVertBar,
						)[ |]
				)
			}
		}
		set heading(numbering: HeadingNumbering)
		// 有序列表編號同染 Cfg.ColorListNum。走 numbering 函數保持默認布局；
		// 深層編號統一爲阿拉伯數字（覆蓋默認的第二層 a. 樣式）。
		// HTML 靶由 CSS 的 li::marker 上色。
		set enum(numbering: (..nums) => text(fill: Cfg.ColorListNum)[#numbering("1.", ..nums)])
		
				//trial
		show list: set block(above: 1em, below: 1em)
		show enum: set block(above: 1em, below: 1em)
		// 列表項：首行縮進、續行頂格（用戶 2026-10-29 修訂，第三版：手動重造）。
		// Typst 列表項內建是懸掛縮進：續行鎖在正文列，
		// 實測 indent／show 規則塞 h／負 par hanging-indent 三路都出不去，
		// 「首行縮進、換行頂格」只能重造。
		// PDF 靶由上方 ListRender/EnumRender 遞歸接管（層級縮進 D×Cfg.ListIndent、
		// 標記 •‣– 按深度循環、enum 編號路徑顯式攜帶）；
		// HTML 靶保持原生 li（層級、標記、編號全原生），
		// 首行縮進由 Article.css 的 li text-indent 補。
		show list: it => if Target == Targets.Html { it } else { ListRender(it, 1) }
		show enum: it => if Target == Targets.Html { it } else { EnumRender(it, 1) }
		if false{//debug only
			show par: it => block(
			stroke: (left: 2pt + red),
			inset: (left: 4pt),
			width: 100%,
			it.body,
		)
		}

		d//end
		
		
	}

	if Target == Targets.Html {
		HtmlDocument(Styled)
	} else {
		Styled
	}
}
