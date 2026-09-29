(function () {
	var CFG = __MVN_CFG__;
	var article = document.querySelector(CFG.scope) || document.body;
	var terms = Array.prototype.slice.call(article.querySelectorAll(CFG.item));
	if (terms.length === 0) { return; }

	function here() {
		return {
			path: location.pathname,
			hash: decodeURIComponent(location.hash || ''),
			y: Math.round(window.scrollY || window.pageYOffset || 0)
		};
	}

	function readSnapshot() {
		try {
			var raw = sessionStorage.getItem(CFG.key);
			if (!raw) { return null; }
			var rec = JSON.parse(raw);
			// 換了文章就作廢：同一分頁的 sessionStorage 跨導航存活，
			// 不認 path 就會把上一篇的座標搬到這一篇上。
			if (!rec || rec.path !== location.pathname) { return null; }
			return rec;
		} catch (e) {
			// 瀏覽器禁用儲存時讀不到，就當作沒有記錄。
			return null;
		}
	}

	function writeSnapshot() {
		try {
			sessionStorage.setItem(CFG.key, JSON.stringify(here()));
		} catch (e) {
			// 瀏覽器拒絕寫入時記不住位置，那就不放回跳鏈接。
		}
	}

	// 搬視窗搬兩次：第一次立刻生效；
	// 第二次留給「改 location.hash」那條降級路徑——
	// 瀏覽器在 hash 變化後自己還要跳一次，會蓋掉第一次。
	function settle(y) {
		window.scrollTo(0, y);
		setTimeout(function () { window.scrollTo(0, y); }, 0);
	}

	// 捕獲階段監聽：比目標元素的默認跳轉更早拿到點擊。
	// 「讀者從哪來」只在跳轉發生前纔取得到，這是唯一的時機。
	// 只記站內鏈接；外鏈、mailto 等一概不管。
	document.addEventListener('click', function (ev) {
		if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) { return; }
		var a = ev.target && ev.target.closest ? ev.target.closest('a[href]') : null;
		if (!a) { return; }
		// 「回出處」自己那一下不記：它要用的正是已存在的那條記錄，
		// 記下去等於把來源覆寫成「此刻在詞條表裏」。
		if ((' ' + (a.className || '') + ' ').indexOf(' ' + CFG.back + ' ') >= 0) { return; }
		var href = a.getAttribute('href') || '';
		if (href === '' || href.charAt(0) !== '#') { return; }
		writeSnapshot();
		// 同頁 fragment 跳轉不會重新載入頁面，腳本也不會重跑，
		// 所以必須當場重繪一次詞條表裡的鏈接。
		render();
	}, true);

	// 回出處：自己把 URL 換回來源、自己把視窗搬到記下的座標。
	// 不用 history.back()，也不指望瀏覽器替我們還原滾動位置。
	function goBack(rec, ev) {
		ev.preventDefault();
		try {
			// 不帶 fragment 時要給完整路徑，
			// 否則 replaceState 會保留當前的 fragment。
			history.replaceState(null, '', rec.hash || (location.pathname + location.search));
		} catch (e) {
			// 不透明來源（file:// 在部分瀏覽器上就是）會拒絕 replaceState，退回改 hash。
			location.hash = rec.hash || '';
		}
		settle(rec.y);
		render();
	}

	function render() {
		Array.prototype.slice.call(article.querySelectorAll('.' + CFG.back)).forEach(function (old) {
			var parent = old.parentNode;
			// 連它前面那個空格結點一起收掉，否則反覆點擊會攢出一串空格。
			if (parent && parent.lastChild === old && old.previousSibling && old.previousSibling.nodeType === 3) {
				parent.removeChild(old.previousSibling);
			}
			if (parent) { parent.removeChild(old); }
		});
		var rec = readSnapshot();
		if (!rec) { return; }
		terms.forEach(function (term) {
			// 記錄指向本詞條自己時，這條鏈接是空動作，不放。
			if (rec.hash === '#' + term.id) { return; }
			var head = term.querySelector('h1, h2, h3, h4, h5, h6') || term;
			var link = document.createElement('a');
			link.className = CFG.back;
			// 先寫文字再加那個空格結點：
			// textContent 的賦值會清空既有子結點，順序反了就只剩一個空格。
			link.textContent = CFG.label;
			link.href = rec.hash || '#';
			link.addEventListener('click', function (ev) { goBack(rec, ev); });
			head.appendChild(document.createTextNode(' '));
			head.appendChild(link);
		});
	}

	// 只重繪，不搬視窗：
	// 前進跳轉（讀者點名詞）一律不許被這支腳本干擾；
	// 讀者若用瀏覽器自己的返回鍵，滾動還原也是瀏覽器的事。
	window.addEventListener('hashchange', render);

	render();
})();