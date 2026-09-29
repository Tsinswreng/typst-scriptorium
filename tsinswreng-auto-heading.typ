#let tsinswreng-heading-level = state("tsinswreng-heading-level", 0)

// 自動層級標題。帶命名參數時要用圓括號，如 #H(level: 3)[題][文]。
// - level：本標題的絕對層級，默認在當前層級上加一；
//   子孫在此之上繼續嵌套，本子樹結束後恢復原層級。
// - start：本標題的序號（末位數字），默認接着計數；
//   如 start: 2 則本標題顯示 2.、子標題顯示 2.1。
//   只可傳 ≥1 的整數：Typst 計數器值禁負數、內建 numbering()
//   也拒絕負數，單個標題永遠無法顯示 0 或負數（底層硬限制）；
//   「歸零重編」用下面的 HReset()。
// - label：附着到本標題的 label 值（如 <sec>），之後用 @sec 引用。
//
// 收斂陷阱（踩過的坑，勿再犯）：
// state 更新必須保持相對運算（n => n + 1 / n => n - 1）。
// 若把 get() 的結果捕獲後絕對寫回（update(_ => lvl) 之類），
// 嵌套超過 5 層時 Typst 五輪迭代內不收斂，
// 層級與序號會整體錯亂（層級塌陷、編號亂跳）。
// level: 錨定分支只有進出各一次絕對寫回，鏈條被相對步驟切斷，實測收斂。
#let auto-heading(title, content, level: none, start: none, label: none) = context {
	let outer = tsinswreng-heading-level.get()
	if level == none {
		tsinswreng-heading-level.update(n => n + 1)
	} else {
		tsinswreng-heading-level.update(n => level)
	}
	let lvl = if level == none { outer + 1 } else { level }
	if start != none {
		// 先把編號計數器撥到 start 的前一個數，
		// 下面 heading 出現時自增一位，從而顯示 start。
		// 父鏈照舊；比當前深度更深時中間層補 0（與手寫跳層行爲一致）。
		let nums = counter(heading).get()
		let padded = range(lvl - 1).map(i => if i < nums.len() { nums.at(i) } else { 0 })
		counter(heading).update(padded + (start - 1,))
	}
	[#heading(level: lvl)[#title] #label]

	content

	if level == none {
		tsinswreng-heading-level.update(n => n - 1)
	} else {
		// 錨定子樹結束，跳回進入前的層級
		tsinswreng-heading-level.update(n => outer)
	}
}

// 編號歸零：下一個標題從 1 重新編號，層級棧不受影響。
// 用於 include 進來的文檔要獨立從 1 編號、又不改其源碼的場合：
// 寫在 include 之前即可。
#let HReset() = counter(heading).update((0,))

#let H = auto-heading