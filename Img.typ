#import "Target.typ": *

// BasePath 僅供 PDF image(...) 使用；HtmlBase 是項目根目錄下的資產路徑。
#let FnImgGen(BasePath, HtmlBase: "assets/") = {
	let affix = ".gen.png"
	return Name => {
		if Target == Targets.Html {
			html.elem("img", attrs: (
				class: HtmlAssetMarkerPrefix + HtmlBase + Name + affix,
				alt: Name,
			))
		} else {
			image(BasePath + Name + affix)
		}
	}
}

// 普通項目圖片。Base 是 PDF 模式相對於本公共文件的路徑，HTML 只保留 Path marker。
#let ImgPath(Path, Base: ".", alt: none) = {
	if Target == Targets.Html {
		html.elem("img", attrs: (
			class: HtmlAssetMarkerPrefix + Path,
			alt: if alt == none { Path } else { alt },
		))
	} else {
		image(Base + "/" + Path)
	}
}

// ── path 錨定版(本地包場景) ──
// 動機:本文件作為 @local 包被 import 時,包沙箱禁止包內 image()/read() 走出包根,
// 上面兩個舊函數在包內拼接路徑字串再調 image(),只能讀到包內資產。
// 解法:Typst 0.15 的 path 值在*構造點*(調用方文件)錨定成根絕對路徑,
// 傳進包內後 image() 直接按該值加載、與解析點無關(官方文檔 foundations/path 的設計場景)。
// 故圖片路徑必須由消費者在自己文件裡用 path(...) 構造後傳入;HTML marker 仍是
// 相對發布目錄的字串(與舊版格式一致,Scriptorium.csx 按 Output 解析並拒絕 / 開頭與 ..)。
/// 普通圖片的 path 錨定版。
///
/// - P (path): 圖片路徑值，
///   須在消費者自己的文件裡以 `path(...)` 構造
///   （按構造點錨定，可穿包沙箱）。
/// - Marker (str): HTML 靶的資產路徑字串，
///   相對發布目錄（格式與舊版 marker 一致）。
/// - alt (str or none): 替代文字，
///   `none` 時取 Marker。
/// -> content
#let ImgP(P, Marker, alt: none) = {
	if Target == Targets.Html {
		html.elem("img", attrs: (
			class: HtmlAssetMarkerPrefix + Marker,
			alt: if alt == none { Marker } else { alt },
		))
	} else {
		image(P)
	}
}

/// 圖片函數工廠（path 錨定版）。
///
/// 把路徑構造器包裝成可直接調用的圖片函數，
/// 相當於舊 `ImgPath` ＋ `.with(Base: ...)` 的組合。
///
/// - ToImg (function): `str -> path`，
///   相對路徑字串到 path 值的構造器；
///   必須寫在消費者自己的文件裡
///   （`path()` 按構造點錨定，寫在本包內會錨到包根）。
/// -> function: `(P: str, alt: str or none) -> content`
#let MkImg(ToImg) = (P, alt: none) => ImgP(ToImg(P), P, alt: alt)

/// 生成圖工廠（path 錨定版）。
///
/// - ToImg (function): `str -> path`，
///   與 `MkImgP` 同款構造器，兩廠可共用同一個；
///   收到的字串爲 `HtmlBase + 圖名 + ".gen.png"`。
/// - HtmlBase (str): 生成圖目錄，相對發布目錄。
/// -> function: `str -> content`，
///   圖名到圖片內容的渲染器。
#let MkImgGen(ToImg, HtmlBase: "assets/") = {
	let affix = ".gen.png"
	return Name => {
		if Target == Targets.Html {
			html.elem("img", attrs: (
				class: HtmlAssetMarkerPrefix + HtmlBase + Name + affix,
				alt: Name,
			))
		} else {
			image(ToImg(HtmlBase + Name + affix))
		}
	}
}
