// Scriptorium：以 Typst 文檔入口 manifest 構建可搬運的發布副本。
//
// 本腳本的核心順序是：讀 manifest -> 複製項目 -> 生成文檔 -> 編譯 HTML
// -> 從 HTML 發現圖片 -> 生成圖片資產 -> 編譯 PDF -> 修正 HTML 圖片路徑
// -> 生成 Markdown -> 寫入共用 CSS 並連結 HTML。順序改動可能會讓資產或輸出失效。
//
// dotnet script Scriptorium.csx check AltNav/_Manifest.typ
// dotnet script Scriptorium.csx build AltNav/_Manifest.typ
// dotnet script Scriptorium.csx list
// dotnet script Scriptorium.csx build-all
// dotnet script Scriptorium.csx zhihu _Publish/AltNav/Main.html -o _Publish/AltNav/Main.zhihu.html --images zhihu-images.txt
//
// _Manifest.typ 有兩個 schema：V1 逐個文件列入口；V2 以目錄為單位，
// SrcDirs 是源碼樹，GeneratedDirs 是整棵由生成器產生的樹。資產和輸出規則由本腳本固定處理。
// 構建不修改源項目，所有輸出先寫入 _Publish/<Project>/ 的可運行副本。

// CsSh 負責命令列、檔案複製、目錄操作和 glob；AngleSharp 只負責解析已生成的 HTML。
// 這個邊界很重要：C# 不解析 Typst 正文，也不使用正則表達式掃描 ImgGen(...)。
#r "nuget: Tsinswreng.CsSh, 0.3.0-alpha"
#r "nuget: AngleSharp, 1.7.0"
#r "nuget: ReverseMarkdown, 5.0.0"
#r "nuget: OpenCC, 0.1.0"

#nullable enable

using AngleSharp;
using OpenCC;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using Tsinswreng.CsSh;
using static Tsinswreng.CsSh.ShGlobal;
using CT = System.Threading.CancellationToken;

// MvnConfig 是腳本級配置，不是項目 manifest；所有可調整值只在這個類中定義一次。
var Config = new MvnConfig();
// ManifestV1 是 _Manifest.typ 中 metadata 的 label；不要把正文文件當 manifest 讀取。
// label 和文件名也只在 MvnConfig 內定義一次。

// Root 固定為本腳本所在目錄；Publish 是所有項目的共同發布目錄。
// CsxDir() 來自 CsSh，確保從任意目前工作目錄啟動時仍以腳本位置為基準。
var Ct = CT.None;
var Root = CsxDir();
var Publish = Root/Config.PublishDirectoryName;
// MVN_TYPST_PATH 可指向未加入 PATH 的便攜版 Typst；未設置時交給 PATH 查找 typst。
var Typst = GetEnv(Config.TypstEnvironmentVariableName) ?? Config.DefaultTypstExecutable;
// 讀取 Typst query 輸出的 JSON；欄位名稱保持與 metadata 一致。
// WriteIndented 只影響發布的 manifest.json，不影響輸入 manifest 的解析。
var Json = Config.JsonSerializerOptions;

// 無參數時只顯示用法，不建立或刪除任何文件。
if (Args.Count == 0) {
	// 沒有命令時不猜測用戶意圖，也不執行默認 build，避免意外修改 _Publish。
	Echo(Config.UsageText);
	return 2;
}

try {
	// 命令分派保持薄；manifest 驗證和構建流程由下方函數完成。
	if (Args[0] == Config.CheckCommand) {
		// check 只執行 Typst query 和欄位驗證，不觸碰 _Publish。
		// 這使 check 可以用於 CI 或編輯 manifest 時的快速反饋。
		var CheckPath = RequireManifestPath(Args);
		var CheckManifest = await ReadManifest(CheckPath, Ct);
		// check 只讀源項目：入口文件是否存在、目錄結構是否自洽都在這裡驗證，不碰 _Publish。
		ResolveUnits(Path.GetDirectoryName(CheckPath)!, CheckManifest);
		await Echo($"valid: {CheckPath}", Ct);
	} else if (Args[0] == Config.BuildCommand) {
		// build 只構建命令列指定的單一項目。
		// Build 內部會先驗證配置，再覆寫該項目的同名構建產物。
		await Build(RequireManifestPath(Args), Ct);
	} else if (Args[0] == Config.BuildAllCommand) {
		// _Publish 也可能包含複製的 _Manifest.typ，必須排除它們。
		// Glob 遍歷整個腳本根目錄，因此每個項目都會被獨立構建。
		foreach (var Entry in Glob(Root/$"**/{Config.ManifestFileName}")) {
			if (!IsUnder(Entry, Publish)) {
				await Build(Entry, Ct);
			}
		}
	} else if (Args[0] == Config.ListCommand) {
		// list 和 build-all 使用同一個 manifest 掃描範圍，但不產生輸出。
		// list 仍然讀取並驗證 manifest，這樣列出的項目不會包含格式錯誤的配置。
		foreach (var Entry in Glob(Root/$"**/{Config.ManifestFileName}")) {
			if (IsUnder(Entry, Publish)) {
				continue;
			}
			var Manifest = await ReadManifest(Entry, Ct);
			await Echo($"{Manifest.Id}\t{Path.GetRelativePath(Root, Entry)}", Ct);
		}
	} else if (Args[0] == Config.ZhihuCommand) {
		var Options = ParseZhihuOptions(Args);
		await RewriteHtmlForZhihu(Options.HtmlPath, Options.OutputPath, Options.ImagesPath, Ct);
	} else {
		throw new Exception($"unknown command: {Args[0]}");
	}
}
catch (Exception Error) {
	// 統一以非零狀態返回，方便命令列或上層腳本判斷構建失敗。
	await Write(Stderr, $"Mvn: {Error.Message}{Environment.NewLine}", Ct);
	return 1;
}

ZhihuOptions ParseZhihuOptions(IList<string> Arguments) {
	// zhihu 僅接受一個來源 HTML，所有選項都必須顯式給值，避免把 URL 清單或輸出檔誤當來源。
	if (Arguments.Count != 6 || Arguments[2] != "-o" || Arguments[4] != "--images") {
		throw new Exception("usage: dotnet script Mvn.csx zhihu <Main.html> -o <Main.zhihu.html> --images <ImgPath>");
	}
	var HtmlPath = Path.GetFullPath(Arguments[1]);
	var OutputPath = Path.GetFullPath(Arguments[3]);
	var ImagesPath = Path.GetFullPath(Arguments[5]);
	if (HtmlPath == OutputPath) {
		throw new Exception("zhihu output path must differ from source HTML path.");
	}
	return new ZhihuOptions(HtmlPath, OutputPath, ImagesPath);
}

async Task RewriteHtmlForZhihu(string HtmlPath, string OutputPath, string ImagesPath, CT Ct) {
	if (!File.Exists(HtmlPath)) {
		throw new Exception($"zhihu source HTML does not exist: {HtmlPath}");
	}
	if (!File.Exists(ImagesPath)) {
		throw new Exception($"zhihu image URL list does not exist: {ImagesPath}");
	}
	var ImageUrls = (await File.ReadAllLinesAsync(ImagesPath, Ct))
		.Select(Line => Line.Trim())
		.Where(Line => Line.Length > 0)
		.ToList();
	if (ImageUrls.Count == 0) {
		throw new Exception($"zhihu image URL list is empty: {ImagesPath}");
	}
	for (var Index = 0; Index < ImageUrls.Count; Index++) {
		if (!Uri.TryCreate(ImageUrls[Index], UriKind.Absolute, out var Url)
			|| Url.Scheme != Uri.UriSchemeHttps
			|| !Url.Host.EndsWith(Config.ZhihuImageHostSuffix, StringComparison.OrdinalIgnoreCase)) {
			throw new Exception($"invalid Zhihu image URL at line {Index + 1}: {ImageUrls[Index]}");
		}
	}
	var Html = await File.ReadAllTextAsync(HtmlPath, Ct);
	var Context = BrowsingContext.New(Configuration.Default);
	var Document = await Context.OpenAsync(Requester => Requester.Content(Html), Ct);
	var Article = Document.QuerySelector(Config.HtmlArticleSelector)
		?? throw new Exception($"zhihu source HTML has no {Config.HtmlArticleSelector} element: {HtmlPath}");
	var LiftedCodeBlocks = LiftCodeBlocksOutOfLists(Article);
	var Images = Article.QuerySelectorAll("img[src]");
	if (Images.Length != ImageUrls.Count) {
		throw new Exception($"zhihu image count mismatch: HTML has {Images.Length}, URL list has {ImageUrls.Count}.");
	}
	for (var Index = 0; Index < Images.Length; Index++) {
		Images[Index].SetAttribute("src", ImageUrls[Index]);
	}
	Directory.CreateDirectory(Path.GetDirectoryName(OutputPath)!);
	await File.WriteAllTextAsync(OutputPath, Document.ToHtml(), Ct);
	await Echo($"zhihu: rewrote {Images.Length} images and lifted {LiftedCodeBlocks} code blocks -> {OutputPath}", Ct);
}

int LiftCodeBlocksOutOfLists(AngleSharp.Dom.IElement Article) {
	// 知乎不會把 li 或其他列表容器中的 pre 轉成原生代碼塊。
	// 僅處理直接位於 article 的、且後代含 pre 的列表；普通列表保持原 HTML，
	// 以保留巢狀工具清單與「簡言之」等不含代碼塊的語義和版式。
	var Lists = Article.Children
		.Where(Element => Element.LocalName is "ol" or "ul")
		.Where(Element => Element.QuerySelector("pre") is not null)
		.ToList();
	var LiftedCodeBlocks = 0;
	foreach (var List in Lists) {
		var IsOrdered = List.LocalName == "ol";
		var Start = IsOrdered && int.TryParse(List.GetAttribute("start"), out var ParsedStart) ? ParsedStart : 1;
		var Items = List.Children.Where(Element => Element.LocalName == "li").ToList();
		if (Items.Count == 0 || Items.Count != List.Children.Length) {
			throw new Exception("zhihu cannot flatten a list containing non-li children.");
		}
		for (var ItemIndex = 0; ItemIndex < Items.Count; ItemIndex++) {
			var Item = Items[ItemIndex];
			var ItemChildren = Item.ChildNodes.ToList();
			var FirstParagraph = ItemChildren.OfType<AngleSharp.Dom.IElement>()
				.FirstOrDefault(Element => Element.LocalName == "p");
			var Marker = IsOrdered ? $"{Start + ItemIndex}. " : "• ";
			if (FirstParagraph is not null) {
				FirstParagraph.InnerHtml = System.Net.WebUtility.HtmlEncode(Marker) + FirstParagraph.InnerHtml;
			} else {
				var MarkerParagraph = Article.Owner!.CreateElement("p");
				MarkerParagraph.TextContent = Marker.TrimEnd();
				Article.InsertBefore(MarkerParagraph, List);
			}
			LiftedCodeBlocks += Item.QuerySelectorAll("pre").Length;
			foreach (var Child in ItemChildren) {
				Article.InsertBefore(Child, List);
			}
		}
		List.Remove();
	}
	return LiftedCodeBlocks;
}

string RequireManifestPath(IList<string> Arguments) {
	// 命令列路徑轉成絕對路徑；項目內相對路徑之後都以它的目錄為基準。
	// 目前只有 check 和 build 接受 manifest 參數，build-all/list 使用自動掃描。
	if (Arguments.Count < 2) {
		throw new Exception("manifest path is required for check and build.");
	}

	return Path.GetFullPath(Arguments[1]);
}

void AddTypstInputs(
	List<string> Arguments,
	string Target,
	string? Lang = null,
	IReadOnlyDictionary<string, string>? Inputs = null) {
	// 所有 Typst 編譯都從同一個地方追加 Mvn 約定的輸入，避免 HTML、PDF 和圖片資產使用不同配置。
	// Target 和 Lang 都由 _Common.typ 消費；自訂 Inputs 只在文件編譯時傳入，圖片資產保持固定配置。
	Arguments.Add("--input");
	Arguments.Add($"Target={Target}");
	if (!string.IsNullOrWhiteSpace(Lang)) {
		Arguments.Add("--input");
		Arguments.Add($"Lang={Lang}");
	}
	if (Inputs is not null) {
		foreach (var Input in Inputs) {
			Arguments.Add("--input");
			Arguments.Add($"{Input.Key}={Input.Value}");
		}
	}
}

async Task Build(string ManifestPath, CT Ct) {
	// 先讀取並驗證 manifest，再覆寫構建產物，避免無效配置破壞既有發布結果。
	var Manifest = await ReadManifest(ManifestPath, Ct);
	var Project = Path.GetDirectoryName(ManifestPath)!;
	var ProjectId = Path.GetFileName(Project);
	var Output = Publish/ProjectId;

	// ProjectId 同時是發布目錄名和 manifest.json 的 Id；兩者不一致時停止，
	// 避免同一項目被錯誤地寫入另一個發布目錄。

	if (!string.Equals(Manifest.Id, ProjectId, StringComparison.Ordinal)) {
		throw new Exception($"manifest id '{Manifest.Id}' must match project directory '{ProjectId}'.");
	}

	// V2 的入口是「目錄 + 檔名」，V1 是「相對項目根的檔名」；兩者都解析成同一份編譯清單。
	var Docs = ResolveUnits(Project, Manifest);

	// 發布目錄採增量覆寫，保留使用者放入的圖片 URL 清單等非構建文件。
	// 因此來源已刪除或改名的文件不會自動從發布目錄移除，需由使用者另行明確清理。
	await Mkdir(Output, Ct);
	// 發布副本必須包含源文件和普通資產，因為 Typst 編譯時仍會按相對路徑讀取它們。
	await Cp(Project/"*", Output, new(Overwrite: true), Ct);
	// Main.typ 通常會 import ../_Common.typ；把共用文件放在 _Publish 根部才能保持相對導入。
	await Cp(Root/Config.CommonTypstFileName, Publish/Config.CommonTypstFileName, new(Overwrite: true), Ct);
	// _Common.typ 現在是聚合器，本體在同名目錄 _Common/ 下（_Common.typ 自己 import 它們）。
	// 目錄要整個搬到發布根，否則發布副本編譯時 _Common/Cfg.typ 之類會 file not found。
	// 用 glob 進既有目錄，與上面複製項目用的是同一種寫法（不依賴目錄對目錄的複製語義）。
	await Mkdir(Publish/Config.CommonDirectoryName, Ct);
	await Cp(Root/Config.CommonDirectoryName/"*", Publish/Config.CommonDirectoryName, new(Overwrite: true), Ct);
	// _Common.typ 的 set raw(theme: ...) 按 _Common.typ 所在目錄解析主題路徑；缺此文件時 HTML/PDF 編譯都會報 file not found。
	await Cp(Root/Config.CommonTypstThemeFileName, Publish/Config.CommonTypstThemeFileName, new(Overwrite: true), Ct);

	// 生成只寫入發布副本。源倉庫中的同名舊文件不會被當作自動生成結果使用。
	if (Manifest.V2 is not null) {
		// V2 以目錄為單位：整棵來源樹複製到目標樹，再按 Include/Exclude 轉換其中文件。
		await GenerateV2Dirs(Output, Manifest.V2, Ct);
	} else {
		await GenerateDocs(Output, Manifest.V1!, Ct);
	}

	// 先編譯 HTML：HTML 中的 marker 是資產發現的唯一來源。
	// HTML 編譯先於 PDF，是因為只有 HTML export 會留下可供 AngleSharp 讀取的圖片 marker。
	var HtmlPaths = new List<string>();
	foreach (var Doc in Docs) {
		// Doc.Source 是發布副本內的相對 .typ 路徑；輸出文件則按入口名固定命名。
		var OutputPath = Output/$"{Doc.Name}{Config.HtmlExtension}";
		var CompileArgs = new List<string> {
			"compile", "--root", Publish, "--format", Config.HtmlFormat,
			"--features", Config.HtmlFeature,
		};
		AddTypstInputs(CompileArgs, Config.HtmlTarget, Doc.Lang, Doc.Inputs);
		CompileArgs.Add(Output/Doc.Source);
		CompileArgs.Add(OutputPath);
		// CsSh 的 Exe 統一處理進程啟動、stdout/stderr 和取消令牌。
		await Exe(Typst, CompileArgs, Ct);
		HtmlPaths.Add(OutputPath);
	}

	// 只解析已生成的 HTML，不讀取或正則掃描任何 Typst 正文。
	foreach (var Image in DiscoverHtmlImages(HtmlPaths, Output, ProjectId)) {
		// Source 為 null 表示普通圖片；它只需要在 RewriteHtmlImages 時驗證存在。
		if (Image.Source is null) {
			continue;
		}
		foreach (var Format in Config.ImageFormats) {
			// 同一個生成源同時輸出 SVG（HTML）和 PNG（其他發布用途）。
			var Destination = Output/Image.AssetDirectory/$"{Image.Name}{Config.ImageGeneratedAssetSuffix}.{Format.Format}";
			await Mkdir(Path.GetDirectoryName(Destination)!, Ct);
			var CompileArgs = new List<string> {
				"compile", "--root", Publish, "--format", Format.Format,
			};
			if (Format.Ppi is not null) {
				// 位圖 PPI 由配置決定；SVG 等向量格式不添加 --ppi。
				CompileArgs.Add("--ppi");
				CompileArgs.Add(Format.Ppi.Value.ToString());
			}
			AddTypstInputs(CompileArgs, Config.PdfTarget);
			CompileArgs.Add(Output/Image.Source);
			CompileArgs.Add(Destination);
			await Exe(Typst, CompileArgs, Ct);
		}
	}

	// 資產就位後再編譯 PDF，因為 PDF 模式會直接讀取 image(...) 文件。
	foreach (var Doc in Docs) {
		// PDF 不使用 HTML marker；此時所有 .gen 圖片已經存在於發布副本。
		var OutputPath = Output/$"{Doc.Name}{Config.PdfExtension}";
		var CompileArgs = new List<string> {
			"compile", "--root", Publish, "--format", Config.PdfFormat,
		};
		AddTypstInputs(CompileArgs, Config.PdfTarget, Doc.Lang, Doc.Inputs);
		CompileArgs.Add(Output/Doc.Source);
		CompileArgs.Add(OutputPath);
		await Exe(Typst, CompileArgs, Ct);
	}

	// 最後把 HTML marker 改成相對 src。
	foreach (var HtmlPath in HtmlPaths) {
		// RewriteHtmlImages 必須在 Markdown 前執行，確保 Markdown 看到的是可搬運的相對路徑。
		await RewriteHtmlImages(HtmlPath, Output, Ct);
	}

	// Markdown 由現成的 ReverseMarkdown 庫從已處理 HTML 生成，不自製 HTML-to-Markdown 解析器。
	foreach (var Doc in Docs) {
		// 每個 HTML 入口都有獨立的同名 Markdown，避免多語言文檔互相覆蓋。
		await ConvertHtmlToMarkdown(
			Output/$"{Doc.Name}{Config.HtmlExtension}",
			Output/$"{Doc.Name}{Config.MarkdownExtension}",
			Ct);
	}

	// 每個項目目錄只寫一份 CSS；同目錄下的 HTML 以固定檔名引用。
	// 樣式從外部檔讀入；源檔缺失時直接失敗，避免發布出無樣式的 HTML。
	var StyleContent = await File.ReadAllTextAsync(Root/Config.HtmlStyleSourceFileName, Ct);
	await File.WriteAllTextAsync(Output/Config.HtmlStyleFileName, StyleContent, Ct);
	// CSS 僅供 HTML 引用；Markdown 不應包含發布頁樣式。
	foreach (var HtmlPath in HtmlPaths) {
		// 樣式只屬於瀏覽器 HTML；Markdown 保持純內容，方便被其他工具再次處理。
		await LinkHtmlStyle(HtmlPath, Output, Ct);
	}

	// 只保存項目和文檔索引，不把資產/輸出清單重新塞回 manifest。
	// 發布索引保留生成者信息，讓網站側知道每個目錄如何得到；V2 帶目錄清單，V1 帶文件清單。
	var Index = Manifest.V2 is not null
		? new PublishedIndex {
			Schema = Manifest.V2.Schema,
			Id = Manifest.Id,
			Slug = Manifest.V2.Slug,
			SrcDirs = Manifest.V2.SrcDirs,
			GeneratedDirs = Manifest.V2.GeneratedDirs,
		}
		: new PublishedIndex {
			Schema = Manifest.V1!.Schema,
			Id = Manifest.Id,
			Slug = Manifest.V1!.Slug,
			SrcDocs = Manifest.V1!.SrcDocs,
			GeneratedDocs = Manifest.V1!.GeneratedDocs,
		};
	await Write(Output/Config.PublishedManifestFileName, JsonSerializer.Serialize(Index, Json), Ct);
	await Echo($"built {Manifest.Id} -> {Output}", Ct);
}

List<ResolvedDoc> ResolveUnits(string Project, ManifestEnvelope Manifest) {
	// V1 與 V2 的入口建模方式不同，但都歸一到同一份編譯清單：
	// Name 決定產物名，Source 是發布副本內的相對 .typ 路徑，Lang 同時進 Typst 與發布索引。
	return Manifest.V2 is not null
		? ResolveV2Units(Project, Manifest.V2)
		: ResolveDocs(Project, Manifest.V1!);
}

List<ResolvedDoc> ResolveV2Units(string Project, ProjectManifestV2 Manifest) {
	// V2 的單位是目錄：SrcDirs 是手工維護的源碼樹，GeneratedDirs 是由生成器整棵產生的樹。
	// 這裡只驗證源項目一側；生成目錄的入口文件要等發布副本生成之後才存在。
	if (Manifest.SrcDirs.Count == 0) {
		throw new Exception("SrcDirs must declare at least one source directory");
	}
	var Result = new List<ResolvedDoc>();
	var DocPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
	var DirPaths = new List<string>();
	// 源目錄的入口清單，供生成目錄按同名同位置繼承。
	var SourceEntries = new Dictionary<string, List<DocEntryManifest>>(StringComparer.Ordinal);
	foreach (var Dir in Manifest.SrcDirs) {
		var Path = ValidateRelativeDirectory(Dir.Path, "SrcDirs.Path");
		RegisterDirectory(DirPaths, Path, Project, true);
		if (string.IsNullOrWhiteSpace(Dir.Lang)) {
			throw new Exception($"source directory language is required: {Dir.Path}");
		}
		if (Dir.Docs.Count == 0) {
			throw new Exception($"source directory has no compile entry: {Dir.Path}");
		}
		foreach (var Entry in Dir.Docs) {
			RequireSourceFile(Project, Path, Entry.File);
			var Doc = ResolveV2Doc(Path, Dir.Lang, Entry);
			if (!DocPaths.Add(Doc.Source)) {
				throw new Exception($"duplicate compile entry: {Doc.Source}");
			}
			Result.Add(Doc);
		}
		SourceEntries.Add(Path, Dir.Docs);
	}
	foreach (var Dir in Manifest.GeneratedDirs) {
		var Path = ValidateRelativeDirectory(Dir.Path, "GeneratedDirs.Path");
		// 生成目錄會被整棵刪除再重建，所以它不能是項目根。
		RegisterDirectory(DirPaths, Path, Project, false);
		if (string.IsNullOrWhiteSpace(Dir.Lang)) {
			throw new Exception($"generated directory language is required: {Dir.Path}");
		}
		var Options = Dir.GeneratorOptions ?? throw new Exception($"GeneratorOptions is required for {Dir.Path}");
		if (!string.Equals(Dir.Generator, Config.OpenCcGeneratorName, StringComparison.OrdinalIgnoreCase)) {
			throw new Exception($"unsupported directory generator '{Dir.Generator}' for {Dir.Path}");
		}
		if (string.IsNullOrWhiteSpace(Options.Mode)) {
			throw new Exception($"GeneratorOptions.Mode is required for {Dir.Path}");
		}
		var From = ValidateRelativeDirectory(Options.From, "GeneratorOptions.From");
		if (!SourceEntries.TryGetValue(From, out var Entries)) {
			// 來源必須先聲明，故順序硬約束為「先源目錄、後生成目錄」，也允許由已聲明的生成目錄再生成。
			throw new Exception($"generated directory source must be declared before {Dir.Path}: {Options.From}");
		}
		foreach (var Entry in Entries) {
			// 生成目錄不重列入口：整棵複製來源目錄，入口清單與來源一致，含各自的 Inputs。
			RequireSourceFile(Project, From, Entry.File);
			var Doc = ResolveV2Doc(Path, Dir.Lang, Entry);
			if (!DocPaths.Add(Doc.Source)) {
				throw new Exception($"duplicate compile entry: {Doc.Source}");
			}
			Result.Add(Doc);
		}
		SourceEntries.Add(Path, Entries);
	}
	return Result;
}

ResolvedDoc ResolveV2Doc(string Directory, string Lang, DocEntryManifest Entry) {
	// File 相對於所屬目錄，允許子目錄；不允許絕對路徑與上穿。
	var File = ValidateRelativeFile(Entry.File, Config.TypstDocumentExtension);
	var Source = Directory.Length == 0 ? File : Directory + "/" + File;
	return new ResolvedDoc(Source[..^Config.TypstDocumentExtension.Length], Source, Lang, CopyInputs(Entry.Inputs));
}

void RegisterDirectory(List<string> Existing, string Dir, string Project, bool AllowRoot) {
	// 兩條目錄不得相同，也不得互相包含：生成時整棵刪掉目標樹，包含關係會刪到源文件。
	if (Dir.Length == 0 && !AllowRoot) {
		throw new Exception("generated directory must not be the project root; declare a subdirectory instead");
	}
	foreach (var Other in Existing) {
		if (string.Equals(Other, Dir, StringComparison.Ordinal)) {
			throw new Exception($"duplicate directory: {Dir}");
		}
		if (IsUnder(Path.Combine(Project, Other), Path.Combine(Project, Dir))
			|| IsUnder(Path.Combine(Project, Dir), Path.Combine(Project, Other))) {
			throw new Exception($"directories must not contain each other: {Dir} and {Other}");
		}
	}
	Existing.Add(Dir);
}

void RequireSourceFile(string Project, string Dir, string Doc) {
	// 源項目裡的入口文件必須真實存在；生成目錄的對應文件要到發布副本生成後才檢查。
	var Relative = ValidateRelativeFile(Doc, Config.TypstDocumentExtension);
	var Full = Dir.Length == 0 ? Path.Combine(Project, Relative) : Path.Combine(Project, Dir, Relative);
	if (!File.Exists(Full)) {
		throw new Exception($"entry file does not exist: {Dir}/{Relative}");
	}
}

string ValidateRelativeDirectory(string Value, string Field) {
	// 目錄路徑會進入發布副本，禁止絕對路徑與上穿；"." 與空字串都表示項目根。
	if (string.IsNullOrWhiteSpace(Value) || Path.IsPathRooted(Value) || Value.Contains("..", StringComparison.Ordinal)) {
		throw new Exception($"invalid relative directory path in {Field}: {Value}");
	}
	var Normalized = Value.Replace('\\', '/').Trim('/');
	if (Normalized is "." or "") {
		return "";
	}
	// 同一目錄只允許一種寫法，避免 "a/b" 與 "a//b" 被當成兩棵樹。
	foreach (var Segment in Normalized.Split('/')) {
		if (Segment.Length == 0 || Segment == ".") {
			throw new Exception($"invalid relative directory path in {Field}: {Value}");
		}
	}
	return Normalized;
}

List<ResolvedDoc> ResolveDocs(string Project, ProjectManifest Manifest) {
	// 這裡只驗證 manifest 已列出的入口文件；其餘 .typ 文件不是文章入口。
	// 返回的列表同時驅動 HTML、PDF 和 Markdown 三種輸出，故三者入口保持完全一致。
	var Result = new List<ResolvedDoc>();
	var Names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
	var DocumentInputs = new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
	foreach (var Entry in Manifest.SrcDocs) {
		// SrcDocs 是用戶維護的源文件，必須在源項目中真實存在。
		var Source = ValidateRelativeFile(Entry.Key, Config.TypstDocumentExtension);
		var Name = Source[..^Config.TypstDocumentExtension.Length];
		var SourcePath = Path.GetFullPath(Path.Combine(Project, Source));
		if (!File.Exists(SourcePath)) {
			throw new Exception($"source document does not exist: {Source}");
		}
		if (!Names.Add(Source)) {
			throw new Exception($"duplicate document entry: {Source}");
		}
		var Inputs = CopyInputs(Entry.Value.Inputs);
		DocumentInputs.Add(Source, Inputs);
		Result.Add(new ResolvedDoc(Name, Source, Entry.Value.Lang, Inputs));
	}
	foreach (var Entry in Manifest.GeneratedDocs) {
		// GeneratedDocs 的目標文件尚未存在於源項目；它會先由 GenerateDocs 寫入發布副本。
		var Source = ValidateRelativeFile(Entry.Key, Config.TypstDocumentExtension);
		if (!Names.Add(Source)) {
			throw new Exception($"document is listed as both source and generated: {Source}");
		}
		var Options = Entry.Value.GeneratorOptions
			?? throw new Exception($"GeneratorOptions is required for {Source}");
		var From = ValidateRelativeFile(Options.From, Config.TypstDocumentExtension);
		if (!DocumentInputs.TryGetValue(From, out var InheritedInputs)) {
			throw new Exception($"generated document input source must be declared before {Source}: {From}");
		}
		var Inputs = MergeInputs(InheritedInputs, Entry.Value.Inputs);
		DocumentInputs.Add(Source, Inputs);
		Result.Add(new ResolvedDoc(Source[..^Config.TypstDocumentExtension.Length], Source, Entry.Value.Lang, Inputs));
	}
	if (Result.Count == 0) {
		throw new Exception("manifest has no source or generated documents");
	}
	return Result;
}

Dictionary<string, string> CopyInputs(IReadOnlyDictionary<string, string>? Inputs) {
	// Inputs 可省略；複製後避免反序列化結果在繼承或編譯參數組裝期間被修改。
	return Inputs is null
		? new Dictionary<string, string>(StringComparer.Ordinal)
		: new Dictionary<string, string>(Inputs, StringComparer.Ordinal);
}

Dictionary<string, string> MergeInputs(
	IReadOnlyDictionary<string, string> InheritedInputs,
	IReadOnlyDictionary<string, string>? Inputs) {
	// GeneratedDocs 先繼承 GeneratorOptions.From 的輸入，再由自身同名鍵覆蓋。
	var Result = CopyInputs(InheritedInputs);
	if (Inputs is not null) {
		foreach (var Input in Inputs) {
			Result[Input.Key] = Input.Value;
		}
	}
	return Result;
}

async Task GenerateDocs(string Output, ProjectManifest Manifest, CT Ct) {
	// 所有生成器都在發布副本上運行：源項目只讀，生成結果不會污染用戶手工維護的文件。
	foreach (var Entry in Manifest.GeneratedDocs) {
		// 目前先明確限制生成器名稱，新增生成器時必須在這裡增加對應的契約。
		var Target = ValidateRelativeFile(Entry.Key, Config.TypstDocumentExtension);
		var Generator = Entry.Value.Generator;
		if (!string.Equals(Generator, Config.OpenCcGeneratorName, StringComparison.OrdinalIgnoreCase)) {
			throw new Exception($"unsupported document generator '{Generator}' for {Target}");
		}
		var Options = Entry.Value.GeneratorOptions
			?? throw new Exception($"GeneratorOptions is required for {Target}");
		// From/Mode 是生成器的最小輸入；缺少 Mode 時不採用默認值，避免悄悄生成錯誤語言。
		if (string.IsNullOrWhiteSpace(Options.Mode)) {
			throw new Exception($"GeneratorOptions.Mode is required for {Target}");
		}
		var From = ValidateRelativeFile(Options.From, Config.TypstDocumentExtension);
		var Input = Path.GetFullPath(Path.Combine(Output, From));
		var Destination = Path.GetFullPath(Path.Combine(Output, Target));
		// From 也必須位於發布副本內，且要在生成前已經隨項目複製過來。
		if (!IsUnder(Input, Output) || !File.Exists(Input)) {
			throw new Exception($"OpenCC source document does not exist in publish copy: {From}");
		}
		if (!IsUnder(Destination, Output)) {
			throw new Exception($"generated document escapes publish directory: {Target}");
		}
		if (string.Equals(Input, Destination, StringComparison.OrdinalIgnoreCase)) {
			throw new Exception($"generated document cannot overwrite its source: {Target}");
		}
		await Mkdir(Path.GetDirectoryName(Destination)!, Ct);
		// 讀寫都使用異步 API，並傳入同一個取消令牌，讓長文檔生成可被上層中止。
		var SourceText = await File.ReadAllTextAsync(Input, Ct);
		var ConvertedText = ConvertOpenCc(SourceText, Options.Mode, Target);
		await Write(Destination, ConvertedText, Ct);
	}
}

string ConvertOpenCc(string Text, string Mode, string Target) {
	// 保留 manifest 的 t2s 語義，映射到 OpenCC 的通用繁體 -> 簡體詞庫。
	// OpenCC 的轉換器以詞庫名稱選擇方向；這裡不啟動外部程序，也不依賴 pip。
	// tw/cn 用於繁轉簡，cn/tw2 用於簡轉繁並保留詞語級轉換。
	if (Mode == Config.OpenCcTraditionalToSimplifiedMode) {
		return OpenCC.OpenCC.Converter(Config.OpenCcTraditionalDictionary, Config.OpenCcSimplifiedDictionary)(Text);
	}
	if (Mode == Config.OpenCcSimplifiedToTraditionalMode) {
		return OpenCC.OpenCC.Converter(Config.OpenCcSimplifiedDictionary, Config.OpenCcTraditionalDictionaryWithPhrases)(Text);
	}
	throw new Exception($"unsupported OpenCC mode '{Mode}' for {Target}; expected {Config.OpenCcTraditionalToSimplifiedMode} or {Config.OpenCcSimplifiedToTraditionalMode}");
}

async Task GenerateV2Dirs(Pth Output, ProjectManifestV2 Manifest, CT Ct) {
	// 生成目錄整棵重建：先刪目標樹再複製來源樹，避免上一輪留下的舊文件混進發布結果。
	// 轉換只作用在 Include 命中且未被 Exclude 排除的文件；Mvn 不判斷文件格式，命中即當文字轉。
	foreach (var Dir in Manifest.GeneratedDirs) {
		var Options = Dir.GeneratorOptions ?? throw new Exception($"GeneratorOptions is required for {Dir.Path}");
		var Target = ValidateRelativeDirectory(Dir.Path, "GeneratedDirs.Path");
		var Source = ValidateRelativeDirectory(Options.From, "GeneratorOptions.From");
		if (Target.Length == 0) {
			throw new Exception($"generated directory must not be the project root: {Dir.Path}");
		}
		var SourceRoot = Source.Length == 0 ? Output : Output/Source;
		var TargetRoot = Output/Target;
		// 刪目錄不可逆，發布副本邊界與來源存在性在這裡再檢查一次，不依賴 manifest 階段的校驗。
		if (!IsUnder(SourceRoot, Output) || !Directory.Exists(SourceRoot)) {
			throw new Exception($"generated directory source does not exist in publish copy: {Options.From}");
		}
		if (!IsUnder(TargetRoot, Output) || IsUnder(TargetRoot, SourceRoot) || IsUnder(SourceRoot, TargetRoot)) {
			throw new Exception($"generated directory escapes or contains its source: {Dir.Path}");
		}
		if (Directory.Exists(TargetRoot)) {
			Directory.Delete(TargetRoot, true);
		}
		await Mkdir(TargetRoot, Ct);
		await Cp(SourceRoot/"*", TargetRoot, new(Overwrite: true), Ct);
		var Converted = 0;
		foreach (var FilePath in Directory.EnumerateFiles(TargetRoot, "*", SearchOption.AllDirectories)) {
			var Relative = Path.GetRelativePath(TargetRoot, FilePath).Replace(Path.DirectorySeparatorChar, '/');
			if (Options.Include is not null && !Options.Include.Any(Pattern => GlobMatch(Pattern, Relative))) {
				continue;
			}
			if (Options.Exclude is not null && Options.Exclude.Any(Pattern => GlobMatch(Pattern, Relative))) {
				continue;
			}
			var Text = await File.ReadAllTextAsync(FilePath, Ct);
			await File.WriteAllTextAsync(FilePath, ConvertOpenCc(Text, Options.Mode, Relative), Ct);
			Converted++;
		}
		await Echo($"generated {Target} <- {Source} ({Converted} files converted)", Ct);
	}
}

bool GlobMatch(string Pattern, string Relative) {
	// 只支援 `**`、`*`、`?`：`*` 與 `?` 不跨 `/`，`**/` 匹配零層或多層目錄。
	// 這是檔名比對用的 glob，不用於掃描 Typst 正文，故不放寬「C# 不正則掃描正文」那條邊界。
	var Normalized = Pattern.Replace('\\', '/');
	var Builder = new StringBuilder("^");
	for (var Index = 0; Index < Normalized.Length; Index++) {
		var Character = Normalized[Index];
		if (Character == '*' && Index + 1 < Normalized.Length && Normalized[Index + 1] == '*') {
			Index++;
			if (Index + 1 < Normalized.Length && Normalized[Index + 1] == '/') {
				Index++;
				Builder.Append("(?:.*/)?");
			} else {
				Builder.Append(".*");
			}
			continue;
		}
		if (Character == '*') {
			Builder.Append("[^/]*");
			continue;
		}
		if (Character == '?') {
			Builder.Append("[^/]");
			continue;
		}
		Builder.Append(Regex.Escape(Character.ToString()));
	}
	Builder.Append('$');
	return Regex.IsMatch(Relative.Replace('\\', '/'), Builder.ToString());
}

async Task ConvertHtmlToMarkdown(string HtmlPath, string MarkdownPath, CT Ct) {
	// Markdown 的輸入必須是已完成 HTML 圖片重寫的文件，不能直接讀 Typst 源文件。
	var Html = await File.ReadAllTextAsync(HtmlPath, Ct);
	var Context = BrowsingContext.New(Configuration.Default);
	var Document = await Context.OpenAsync(Requester => Requester.Content(Html), Ct);
	// 只把文章內容交給 ReverseMarkdown；外層 article 是發布頁容器，不屬於正文 Markdown。
	var Article = Document.QuerySelector(Config.HtmlArticleSelector)?.InnerHtml
		?? Document.Body?.InnerHtml
		?? Html;
	// 只取 article 內文，避免把發布頁的容器本身寫成 Markdown 中的原始 HTML。
	// Typst HTML 會包含 figure 等語義容器；跳過未知外殼，讓庫繼續轉換其中的圖片和圖注。
	var Converter = new ReverseMarkdown.Converter(new ReverseMarkdown.Config {
		UnknownTags = ReverseMarkdown.Config.UnknownTagsOption.Bypass,
	});
	// ReverseMarkdown 負責 HTML 標籤、列表、代碼和圖片的轉換；本腳本不維護第二套解析器。
	var Markdown = Converter.Convert(Article).TrimEnd() + Environment.NewLine;
	await Write(MarkdownPath, Markdown, Ct);
}

List<HtmlImage> DiscoverHtmlImages(List<string> HtmlPaths, string Output, string ProjectId) {
	// 從 Typst 產生的 HTML 收集資產 marker。普通圖片只需驗證存在，.gen 圖片才需要找生成源。
	// 這是圖片處理的唯一發現入口：HTML 沒有 marker 的圖片不會被 C# 自行猜測或補登記。
	var Result = new Dictionary<string, HtmlImage>(StringComparer.Ordinal);
	foreach (var HtmlPath in HtmlPaths) {
		// 每份文檔都可能引用相同資產，Dictionary 用資產路徑去重跨文檔重複生成。
		var Html = File.ReadAllText(HtmlPath);
		var Context = BrowsingContext.New(Configuration.Default);
		var Document = Context.OpenAsync(Requester => Requester.Content(Html)).GetAwaiter().GetResult();
		foreach (var Image in Document.QuerySelectorAll(Config.HtmlImageSelector)) {
			// Typst image 函數輸出的 marker 放在 img.class；只讀這個受約定的 class。
			var Marker = Image.ClassList.FirstOrDefault(Class => Class.StartsWith(Config.ImageMarkerPrefix, StringComparison.Ordinal));
			if (Marker is null) {
				continue;
			}
			var AssetPath = Marker[Config.ImageMarkerPrefix.Length..];
			// marker 來自生成的 HTML，但仍要重新驗證，防止異常輸出穿越發布目錄。
			if (Path.IsPathRooted(AssetPath) || AssetPath.Contains("..", StringComparison.Ordinal)) {
				throw new Exception($"invalid HTML image asset path: {AssetPath}");
			}
			// 配置中的生成格式共同決定哪些 HTML 資產需要推斷 Typst 生成源。
			var AssetFile = BaseName(AssetPath)+"";
			var AssetStem = "";
			foreach (var Format in Config.ImageFormats) {
				var Suffix = Config.ImageGeneratedAssetSuffix + "." + Format.Format;
				if (AssetFile.EndsWith(Suffix, StringComparison.Ordinal)) {
					AssetStem = AssetFile[..^Suffix.Length];
					break;
				}
			}
			if (AssetStem == "") {
				// 普通圖片（不匹配任何配置中的生成格式）不需要推斷 Typst 生成源。
				Result.TryAdd(AssetPath, new HtmlImage(AssetPath, null, "", ""));
				continue;
			}
			var AssetDirectory = DirName(AssetPath);
			// V2 的 HTML 位於語言目錄，生成圖的來源可能就在同一個語言目錄；先在該目錄找，再回項目根找共用來源。
			var HtmlDirectory = Path.GetDirectoryName(Path.GetRelativePath(Output, HtmlPath))?.Replace(Path.DirectorySeparatorChar, '/') ?? "";
			if (HtmlDirectory == ".") {
				HtmlDirectory = "";
			}
			var Source = FindGeneratorSource(Output, HtmlDirectory, AssetStem, ProjectId);
			Result[AssetPath] = new HtmlImage(AssetPath, Source, AssetDirectory, AssetStem);
		}
	}
	return Result.Values.ToList();
}

string? FindGeneratorSource(string Output, string HtmlDirectory, string AssetStem, string ProjectId) {
	// 不解析 Typst 內容，只按資產文件名嘗試固定候選：完整名、去項目後綴名、首段名。
	// 例如 Keyboard_AltNav.gen.svg 依次嘗試 Keyboard_AltNav.typ、Keyboard.typ 等候選。
	var Candidates = new List<string> { AssetStem + Config.TypstDocumentExtension };
	var ProjectSuffix = "_" + ProjectId;
	if (AssetStem.EndsWith(ProjectSuffix, StringComparison.Ordinal)) {
		Candidates.Add(AssetStem[..^ProjectSuffix.Length] + Config.TypstDocumentExtension);
	}
	var Prefix = AssetStem.Split('_', 2)[0];
	Candidates.Add(Prefix + Config.TypstDocumentExtension);
	foreach (var Candidate in Candidates.Distinct(StringComparer.Ordinal)) {
		// 候選按優先級檢查，第一個存在的 Typst 文件就是生成圖片的入口。
		// 先看 HTML 自己所在的目錄，再看項目發布目錄根，故語言目錄裡的圖源優先於項目根的同名圖源。
		if (HtmlDirectory.Length > 0 && File.Exists(Output/HtmlDirectory/Candidate)) {
			return HtmlDirectory + "/" + Candidate;
		}
		if (File.Exists(Output/Candidate)) {
			return Candidate;
		}
	}
	var ExistingAsset = Output/Config.ImageAssetDirectoryName/(AssetStem + Config.ImageGeneratedAssetSuffix + "." + Config.ImageExistingVectorFormat);
	// 若 SVG 已由源項目提供而沒有生成源，允許其作為普通現成資產使用。
	return File.Exists(ExistingAsset)
		? null
		: throw new Exception($"cannot infer generator source for HTML asset: {AssetStem}{Config.ImageGeneratedAssetSuffix}.{Config.ImageExistingVectorFormat}");
}

async Task RewriteHtmlImages(string HtmlPath, string Output, CT Ct) {
	// 將 class marker 解析為項目發布目錄下的文件，並計算相對於 HTML 的 src。
	// 這一步不生成資產，只把 HTML 中的臨時協議轉成最終可搬運的文件引用。
	var Html = await File.ReadAllTextAsync(HtmlPath, Ct);
	var Context = BrowsingContext.New(Configuration.Default);
	var Document = await Context.OpenAsync(Requester => Requester.Content(Html), Ct);
	var HtmlDirectory = Path.GetDirectoryName(HtmlPath)!;
	foreach (var Image in Document.QuerySelectorAll(Config.HtmlImageSelector)) {
		// 只處理帶有 Mvn marker 的圖片，保留其他 HTML 圖片屬性和引用不變。
		var Marker = Image.ClassList.FirstOrDefault(Class => Class.StartsWith(Config.ImageMarkerPrefix, StringComparison.Ordinal));
		if (Marker is null) {
			continue;
		}
		var AssetPath = Marker[Config.ImageMarkerPrefix.Length..].Replace('/', Path.DirectorySeparatorChar);
		var AssetAbsolutePath = Path.GetFullPath(Path.Combine(Output, AssetPath));
		// 同時檢查路徑邊界和文件存在性，避免生成一個打開後才失效的 HTML。
		if (!IsUnder(AssetAbsolutePath, Output) || !File.Exists(AssetAbsolutePath)) {
			throw new Exception($"HTML image asset does not exist: {AssetPath}");
		}
		var Relative = Path.GetRelativePath(HtmlDirectory, AssetAbsolutePath).Replace(Path.DirectorySeparatorChar, '/');
		// HTML 使用正斜線，即使在 Windows 發布副本中也保持跨平台路徑格式。
		Image.SetAttribute("src", Relative);
		Image.ClassList.Remove(Marker);
		if (string.IsNullOrWhiteSpace(Image.GetAttribute("class"))) {
			Image.RemoveAttribute("class");
		}
	}
	await File.WriteAllTextAsync(HtmlPath, Document.ToHtml(), Ct);
}

async Task LinkHtmlStyle(string HtmlPath, string Output, CT Ct) {
	// 以 data-mvn-style 做冪等判斷，避免重跑腳本時重複加入 link。
	// 這裡使用 AngleSharp 修改 DOM，而不是用字串拼接插入 <link>，避免破壞 HTML 結構。
	var Html = await File.ReadAllTextAsync(HtmlPath, Ct);
	var Context = BrowsingContext.New(Configuration.Default);
	var Document = await Context.OpenAsync(Requester => Requester.Content(Html), Ct);
	var Head = Document.Head ?? throw new Exception($"HTML head is missing: {HtmlPath}");
	var StyleMarkerSelector = $"[{Config.HtmlStyleMarkerAttribute}='{Config.HtmlStyleMarkerValue}']";
	foreach (var InlineStyle in Head.QuerySelectorAll($"style{StyleMarkerSelector}")) {
		// 刪除舊版構建器留下的內嵌樣式；其他來源的 style 不受影響。
		InlineStyle.Remove();
	}
	var Link = Head.QuerySelector($"link{StyleMarkerSelector}") ?? Document.CreateElement("link");
	// data-mvn-style 同時是冪等標識和樣式來源標識，方便檢查發布文件。
	Link.SetAttribute(Config.HtmlStyleMarkerAttribute, Config.HtmlStyleMarkerValue);
	Link.SetAttribute("rel", "stylesheet");
	// CSS 只在項目發布目錄寫一份；V2 的 HTML 在語言目錄下，故 href 要用相對路徑指回那一份。
	var StylePath = Path.GetFullPath(Path.Combine(Output, Config.HtmlStyleFileName));
	var StyleRelative = Path.GetRelativePath(Path.GetDirectoryName(HtmlPath)!, StylePath).Replace(Path.DirectorySeparatorChar, '/');
	Link.SetAttribute("href", StyleRelative);
	if (Link.Parent is null) {
		Head.AppendChild(Link);
	}
	await File.WriteAllTextAsync(HtmlPath, Document.ToHtml(), Ct);
}

async Task<ManifestEnvelope> ReadManifest(string ManifestPath, CT Ct) {
	// manifest 本身也是 Typst，但只通過 Typst query 讀 metadata，不解析正文源碼。
	// 這是刻意的格式邊界：Typst 負責求值 metadata，C# 只消費 query 返回的 JSON。
	if (!File.Exists(ManifestPath) || Path.GetFileName(ManifestPath) != Config.ManifestFileName) {
		throw new Exception($"{Config.ManifestFileName} is required: {ManifestPath}");
	}
	// V1 與 V2 兩個 label 一次取出：查不到的 label 回空數組而不報錯，所以舊項目不改也能繼續構建。
	await using var Command = Cmd(Typst, [
		"eval", Config.ManifestQueryExpression, "--in", ManifestPath,
		"--root", Root, "--pretty",
	], Ct);
	var Result = await Command.Text(Ct);
	var Found = JsonSerializer.Deserialize<ManifestQueryResult>(Result.Stdout, Json)
		?? throw new Exception($"empty manifest: {ManifestPath}");
	if (Found.V1.Count > 0 && Found.V2.Count > 0) {
		throw new Exception($"manifest must not declare both {Config.ManifestLabelV1} and {Config.ManifestLabelV2}: {ManifestPath}");
	}
	if (Found.V1.Count > 1 || Found.V2.Count > 1) {
		throw new Exception($"manifest must declare exactly one metadata block: {ManifestPath}");
	}
	// Id 不從 metadata 讀取，而由 manifest 所在目錄補入，避免同一項目被寫進另一個發布目錄。
	var Id = Path.GetFileName(Path.GetDirectoryName(ManifestPath)!);
	if (Found.V2.Count == 1) {
		var Manifest = Deserialize<ProjectManifestV2>(Found.V2[0], ManifestPath);
		if (Manifest.Schema != Config.ManifestSchemaV2 || Manifest.SrcDirs.Count == 0) {
			// Schema 和至少一棵源碼樹是 V2 能理解的最低契約。
			throw new Exception($"invalid manifest: {ManifestPath}");
		}
		return new ManifestEnvelope(Manifest.Schema, Id, Manifest.Slug, null, Manifest);
	}
	if (Found.V1.Count == 1) {
		var Manifest = Deserialize<ProjectManifest>(Found.V1[0], ManifestPath);
		if (Manifest.Schema != Config.ManifestSchema || (Manifest.SrcDocs.Count == 0 && Manifest.GeneratedDocs.Count == 0)) {
			// Schema 和至少一個文檔入口是 V1 能理解的最低契約。
			throw new Exception($"invalid manifest: {ManifestPath}");
		}
		return new ManifestEnvelope(Manifest.Schema, Id, Manifest.Slug, Manifest, null);
	}
	throw new Exception($"manifest metadata not found: {ManifestPath}");
}

T Deserialize<T>(JsonElement Value, string ManifestPath) {
	// manifest 是手寫檔案，反序列化失敗時必須能指回是哪一份。
	return Value.Deserialize<T>(Json) ?? throw new Exception($"cannot read manifest: {ManifestPath}");
}

string ValidateRelativeFile(string Value, string Extension) {
	// manifest 文件路徑會進入發布副本，禁止絕對路徑、上穿目錄和錯誤擴展名。
	// 這個檢查同時覆蓋源入口、生成目標和 OpenCC 的 From 路徑。
	if (string.IsNullOrWhiteSpace(Value) || Path.IsPathRooted(Value) || Value.Contains("..", StringComparison.Ordinal)) {
		throw new Exception($"invalid relative file path: {Value}");
	}
	var Normalized = Value.Replace('\\', '/').Trim('/');
	// 統一分隔符後再做擴展名驗證，讓 manifest 在 Windows 和其他平台保持相同語義。
	if (!Normalized.EndsWith(Extension, StringComparison.OrdinalIgnoreCase)) {
		throw new Exception($"document path must end with {Extension}: {Value}");
	}
	return Normalized;
}

bool IsUnder(string Candidate, string Parent) {
	// 發布路徑檢查，防止 HTML marker 把 src 指向發布目錄之外。
	// 兩邊都補上目錄分隔符，避免 /publish/app2 被誤判為 /publish/app 的子路徑。
	var CandidatePath = Path.GetFullPath(Candidate).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
	var ParentPath = Path.GetFullPath(Parent).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
	return CandidatePath.StartsWith(ParentPath, StringComparison.OrdinalIgnoreCase);
}

// MvnConfig 是腳本級配置，不是項目 manifest；它描述工具如何構建，而不是項目有哪些文檔。
// 可調整值集中在此處定義一次，流程函數只引用配置，不重複散落字面量。
sealed class MvnConfig {
	// 發布副本的根目錄名稱。
	public string PublishDirectoryName { get; } = "_Publish";
	// 發布副本需要共享的 Typst 公共文件名稱。
	public string CommonTypstFileName { get; } = "_Common.typ";
	// 公共文件旁邊的同名目錄：_Common.typ 只是聚合器，實作拆在 _Common/ 下。
	// 整個目錄都要複製，不能按副檔名挑：聚合器的 import 指着它，
	// 而目錄裏日後也可能出現非 .typ 的資源（被 read() 讀的腳本或數據檔）。
	public string CommonDirectoryName { get; } = "_Common";
	// _Common.typ 以相對路徑引用的代碼高亮主題；編譯按 _Common.typ 所在目錄解析，須隨之複製到發布根。
	public string CommonTypstThemeFileName { get; } = "DarkModern.tmTheme";
	// 发布索引文件名称。
	public string PublishedManifestFileName { get; } = "manifest.json";
	// manifest metadata 使用的 Typst label。兩種格式並存：舊項目用 V1，目錄為單位的項目用 V2。
	public string ManifestLabelV1 { get; } = "<ManifestV1>";
	public string ManifestLabelV2 { get; } = "<ManifestV2>";
	// 一次取出兩個 label 的值；Typst query 對不存在的 label 回空數組而不報錯，故兩種格式可共存。
	public string ManifestQueryExpression =>
		$"(V1: query({ManifestLabelV1}).map(it => it.value), V2: query({ManifestLabelV2}).map(it => it.value))";
	// 项目 manifest 文件名。
	public string ManifestFileName { get; } = "_Manifest.typ";
	// 当前支持的 manifest schema 版本。
	public string ManifestSchema { get; } = "1";
	public string ManifestSchemaV2 { get; } = "2";
	// manifest 和图片生成源使用的 Typst 文件扩展名。
	public string TypstDocumentExtension { get; } = ".typ";
	// 可通过环境变量覆盖 Typst 可执行文件路径的变量名。
	public string TypstEnvironmentVariableName { get; } = "MVN_TYPST_PATH";
	// 未设置环境变量时交给 PATH 查找的 Typst 命令名。
	public string DefaultTypstExecutable { get; } = "typst";
	// 命令行子命令名称。
	public string CheckCommand { get; } = "check";
	public string BuildCommand { get; } = "build";
	public string BuildAllCommand { get; } = "build-all";
	public string ListCommand { get; } = "list";
	public string ZhihuCommand { get; } = "zhihu";
	// 知乎控制台取得的圖片地址目前都位於 pic*.zhimg.com；限制 host 可及早發現複製到非 URL 資料。
	public string ZhihuImageHostSuffix { get; } = ".zhimg.com";
	// 无参数时显示的命令行用法。
	public string UsageText => $"Usage: dotnet script Scriptorium.csx <check|build|build-all|list|zhihu> [Manifest{TypstDocumentExtension}]";
	// manifest 中声明的 OpenCC 生成器名称。
	public string OpenCcGeneratorName { get; } = "OpenCC";
	// manifest 暴露的 OpenCC 转换模式名称。
	public string OpenCcTraditionalToSimplifiedMode { get; } = "t2s";
	public string OpenCcSimplifiedToTraditionalMode { get; } = "s2t";
	// OpenCC 模式对应的词库名称；tw2 用于保留词语级繁体转换。
	public string OpenCcTraditionalDictionary { get; } = "tw";
	public string OpenCcSimplifiedDictionary { get; } = "cn";
	public string OpenCcTraditionalDictionaryWithPhrases { get; } = "tw2";
	// Typst 输出模式及其传给 _Common.typ 的 Target 值。
	public string HtmlTarget { get; } = "Html";
	public string PdfTarget { get; } = "Pdf";
	// HTML 输出所需的 Typst feature 名称。
	public string HtmlFeature { get; } = "html";
	// HTML 图片 marker 的 class 前缀。
	public string ImageMarkerPrefix { get; } = "mvn-img-asset-";
	// 项目图片资产的相对目录名称。
	public string ImageAssetDirectoryName { get; } = "assets";
	// 生成图片文件名与源文件名之间的后缀。
	public string ImageGeneratedAssetSuffix { get; } = ".gen";
	// 未找到生成源时允许直接使用的现成向量资产格式。
	public string ImageExistingVectorFormat { get; } = "svg";
	// 生成图片的格式和位图 PPI；PPI 为空表示不传 --ppi。
	public ImageOutput[] ImageFormats { get; } = [
		new("svg", null),
		new("png", 600),
	];
	// AngleSharp 查询带图片 marker 的 img 元素。
	public string HtmlImageSelector { get; } = "img[class]";
	// Markdown 转换时保留的正文容器选择器。
	public string HtmlArticleSelector { get; } = "article";
	// 共用 CSS 檔名；同一項目的 HTML 與它位於同一發布目錄。
	public string HtmlStyleFileName { get; } = "_mvn.css";
	// HTML 連結樣式使用的冪等標記屬性和值。
	public string HtmlStyleMarkerAttribute { get; } = "data-mvn-style";
	public string HtmlStyleMarkerValue => HtmlStyleFileName;
	// 发布文件的格式和扩展名。
	public string HtmlFormat { get; } = "html";
	public string HtmlExtension { get; } = ".html";
	public string PdfFormat { get; } = "pdf";
	public string PdfExtension { get; } = ".pdf";
	public string MarkdownExtension { get; } = ".md";
	// 解析 Typst query 与写出发布 manifest 共用的 JSON 选项。
	public JsonSerializerOptions JsonSerializerOptions { get; } = new() {
		PropertyNameCaseInsensitive = true,
		WriteIndented = true,
	};
	// 每個項目共用的 HTML 基礎樣式。
	// 樣式源檔放在 Typst 這邊的目錄：值要與 _Common.typ 的 PDF 靶對應，寫在 C# 字串裏看不出這層關係。
	public string HtmlStyleSourceFileName { get; } = "Article.css";
}

// Ppi 為 null 表示該格式不需要 --ppi；格式和分辨率在 Config.ImageFormats 中各配置一次。
sealed record ImageOutput(string Format, int? Ppi);

// 對應 _Manifest.typ 的 #metadata(( _Schema: "1", SrcDocs: (...), GeneratedDocs: (...) ))。
record ProjectManifest {
	// Typst metadata 使用 _Schema，Schema 屬性只提供 C# 內部較易讀的名稱。
	public string _Schema { get; init; } = "";
	public string Schema => _Schema;
	// Id 不從 JSON 讀取，而是在 ReadManifest 中由 manifest 所在項目目錄補入。
	public string Id { get; init; } = "";
	// Slug 是網站側的路徑名；構建只把它原樣帶進發布索引，不做推導。
	public string Slug { get; init; } = "";
	// 源文件由用戶維護；生成文件由腳本在發布副本中建立。
	public Dictionary<string, DocManifest> SrcDocs { get; init; } = new();
	public Dictionary<string, GeneratedDocManifest> GeneratedDocs { get; init; } = new();
}

// Typst query 一次取出兩個 label 的結果；查不到的 label 是空數組。
record ManifestQueryResult {
	public List<JsonElement> V1 { get; init; } = new();
	public List<JsonElement> V2 { get; init; } = new();
}

// 讀 manifest 的結果：與格式版本無關的部分共用，兩個版本各自保留原始區塊。
record ManifestEnvelope(
	string Schema,
	string Id,
	string Slug,
	ProjectManifest? V1,
	ProjectManifestV2? V2);

// 對應 _Manifest.typ 的 #metadata(( _Schema: "2", SrcDirs: (...), GeneratedDirs: (...) ))。
// 單位是目錄：SrcDirs 一條等於一棵源碼樹，GeneratedDirs 一條等於一棵生成出來的樹。
record ProjectManifestV2 {
	// Typst metadata 使用 _Schema；Schema 只提供 C# 內部較易讀的名稱。
	public string _Schema { get; init; } = "";
	public string Schema => _Schema;
	// Slug 是網站側的路徑名，構建只原樣帶進發布索引。
	public string Slug { get; init; } = "";
	// Id 由 ReadManifest 從 manifest 所在目錄補入，不從 JSON 讀取。
	public string Id { get; init; } = "";
	public List<SrcDirManifest> SrcDirs { get; init; } = new();
	public List<GeneratedDirManifest> GeneratedDirs { get; init; } = new();
}

// 一棵源碼樹：Path 是位置，Lang 是語言，兩者互不推導。
record SrcDirManifest {
	public string Path { get; init; } = "";
	public string Lang { get; init; } = "";
	// 每個元素是一次獨立的 typst compile。
	public List<DocEntryManifest> Docs { get; init; } = new();
	// 主入口可省略；構建不校驗它，只原樣帶進發布索引供網站側決定 index.html 用哪一篇。
	public string? EntryPoint { get; init; }
}

// 一次編譯入口：File 相對於所屬目錄，Inputs 省略即沒有額外 --input。
record DocEntryManifest {
	public string File { get; init; } = "";
	public Dictionary<string, string>? Inputs { get; init; }
}

// 一棵生成目錄：由 Generator 按 GeneratorOptions 從另一棵樹整包產生，入口清單繼承來源目錄。
record GeneratedDirManifest {
	public string Path { get; init; } = "";
	public string Lang { get; init; } = "";
	public string Generator { get; init; } = "";
	public OpenCcTreeOptions? GeneratorOptions { get; init; }
	public string? EntryPoint { get; init; }
}

// V2 的 OpenCC 選項：From 是來源目錄，Include/Exclude 是相對來源樹根的 glob。
record OpenCcTreeOptions {
	public string From { get; init; } = "";
	public string Mode { get; init; } = "";
	// 省略 Include 等於全部匹配；匹配到的文件一律當文字讀入再轉換，故不要把二進位檔寫進來。
	public List<string>? Include { get; init; }
	// Exclude 優先於 Include；null 表示不排除任何文件。
	public List<string>? Exclude { get; init; }
}

// 單個文檔入口的 metadata；Lang 同時控制 Typst 本地化與發布索引。
record DocManifest {
	// Lang 傳給 Typst 的 --input Lang=...，並保留在發布索引。
	public string Lang { get; init; } = "";
	// Inputs 可省略；每個鍵值會作為該文檔 HTML/PDF 編譯的 --input 傳給 Typst。
	public Dictionary<string, string>? Inputs { get; init; }
}

// GeneratedDocs 目前支持 OpenCC；GeneratorOptions.From 是發布副本內的 .typ 路徑。
record GeneratedDocManifest {
	// Lang 描述生成結果的語言；Generator 決定使用哪個已實現的生成器。
	public string Lang { get; init; } = "";
	public string Generator { get; init; } = "";
	// 不同生成器的選項共用這個欄位，以便將來擴展而不改 manifest 外層結構。
	public OpenCcOptions? GeneratorOptions { get; init; }
	// Inputs 可省略；它先繼承 GeneratorOptions.From 的輸入，再以自身同名鍵覆蓋。
	public Dictionary<string, string>? Inputs { get; init; }
}

record OpenCcOptions {
	// From 是發布副本內的源文件路徑，不是相對於腳本的路徑。
	public string From { get; init; } = "";
	// Mode 使用 manifest 層的 t2s/s2t 名稱，不直接暴露 OpenCC 詞庫名稱。
	public string Mode { get; init; } = "";
}

// 構建過程中解析出的文檔源文件。
// Name 用於輸出文件名，Source 用於 Typst 輸入路徑，Lang 用於後續索引。
record ResolvedDoc(
	string Name,
	string Source,
	string Lang,
	IReadOnlyDictionary<string, string> Inputs);
// HTML marker 對應的資產；Source 為 null 表示普通已存在資產。
// AssetDirectory/Name 只在需要重新編譯 .gen 圖片時使用。
record HtmlImage(string AssetPath, string? Source, string AssetDirectory, string Name);
// zhihu 命令的三個顯式文件參數；來源與輸出必須分開，避免覆寫網站用 HTML。
record ZhihuOptions(string HtmlPath, string OutputPath, string ImagesPath);
// 發布目錄中的輕量索引，不是第二份構建配置。
// 它保留語言和生成器信息，讓發布消費者知道每個文檔如何得到。
record PublishedIndex {
	public string Schema { get; init; } = "";
	public string Id { get; init; } = "";
	// Slug 讓網站側不必從項目名推導路徑；manifest 沒寫就是空字串。
	public string Slug { get; init; } = "";
	// V1 項目帶文件清單，V2 項目帶目錄清單；未使用的一側為 null。
	public Dictionary<string, DocManifest>? SrcDocs { get; init; }
	public Dictionary<string, GeneratedDocManifest>? GeneratedDocs { get; init; }
	public List<SrcDirManifest>? SrcDirs { get; init; }
	public List<GeneratedDirManifest>? GeneratedDirs { get; init; }
}

/* 
知乎文章編寫頁,
上傳docx後
用以下代碼獲取上傳的文件地址
   const root = [...document.querySelectorAll('[contenteditable="true"]')]
     .sort((a, b) => b.querySelectorAll('img').length - a.querySelectorAll('img').length)[0];

   copy(
     [...root.querySelectorAll('img')]
       .map(img => img.dataset.originalSrc || img.src)
       .join('\n')
   );
 */