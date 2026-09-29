// `--input bundle=true` 啓用 bundle 導出。
// 未傳入時保持普通文檔模式，方便 Tinymist 預覽。
#let IsBundle = sys.inputs.at("bundle", default: "false") == "true"

#let TargetPdf = "Pdf"
#let TargetHtml = "Html"
#let Target = sys.inputs.at("Target", default: TargetPdf)