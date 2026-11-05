// HTML 類名前綴（2026-11-05 起，舊前綴 mvn- 棄用）。
// 所有類名常量走 HtmlName()；_.typ 與 concept-chain.typ 的 html.elem 發射點只引用常量、不寫字面量。
// 前綴本身另需手改的字面量落在（改前綴須全改）：
// 本目錄 Article.css 的選擇器與 --tswg-scrptm-* 變量、
// Scriptorium.csx 的 ImageMarkerPrefix（圖片標記，與 _.typ 的 HtmlAssetMarkerPrefix 必須同值）、
// 網站倉 tsinswreng.github.io/public/assets/site.css（手工同步份，選擇器多 .article-body 前綴）。
// data-mvn-style / _mvn.css / MVN_TYPST_PATH 是管線自身命名，不隨前綴改。
#let HtmlNamingPrefix = "tswg-scrptm-"
#let HtmlName(name)={
	return HtmlNamingPrefix+name
}

#let ArticleClass = HtmlName("article")
#let NoIndentClass = HtmlName("no-indent")
#let TableCaptionClass = HtmlName("table-caption")
#let TermRefClass = HtmlName("term-ref")
#let CodeBlockClass = HtmlName("code-block")
#let QuoteClass = HtmlName("quote")
#let HeadingNumClass = HtmlName("heading-num")
#let HeadingBarClass = HtmlName("heading-bar")
#let TermClass = HtmlName("term")
