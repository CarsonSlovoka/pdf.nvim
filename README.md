# pdf.nvim

在 Neovim 裡檢視 PDF，並做頁面級編輯、文字層匯出／回寫、AcroForm 填表

這不是 Acrobat。PDF 的字型、欄位座標、向量圖無法在純文字編輯器裡做 WYSIWYG 還原。本插件把「檢視」和「結構操作」留在 Neovim，把排版還原交給 Poppler / qpdf

## 能力

| 面向 | 做得到 | 做不到 |
| --- | --- | --- |
| 檢視 | 影像頁（`pdftoppm`）+ 文字頁（`pdftotext -layout`），可切換 | 連續捲動多頁縮圖牆（未做） |
| 頁面 | 抽頁、合併、拆頁、旋轉、刪頁、重排、壓縮 | 裁切、浮水印 |
| 文字 | 抽出全文到 buffer、改完匯出成新 PDF | 原地替換並保留原排版 |
| 表單 | 列出 AcroForm、在 buffer 填值、經 qpdf JSON 寫回 | 任意 XFA / 破碎表單 |

## 目錄

```
pdf.nvim/
├── plugin/pdf.lua          -- 啟動：命令 + BufReadCmd
├── ftdetect/pdf.lua
├── doc/pdf.txt
├── lua/pdf/
│   ├── init.lua            -- setup() / open()
│   ├── config.lua
│   ├── health.lua          -- :checkhealth pdf
│   ├── util.lua
│   ├── cli.lua             -- poppler / qpdf 包裝
│   ├── state.lua           -- 每個 buffer 的 session
│   ├── viewer.lua          -- 雙模式檢視、翻頁、縮放
│   ├── pages.lua           -- 頁面級操作
│   ├── text.lua            -- 文字層編輯與匯出
│   ├── form.lua            -- AcroForm
│   └── commands.lua
└── README.md
```

## 相依

必裝：

- Neovim 0.12+
- [Poppler](https://poppler.freedesktop.org/)：`pdfinfo` `pdftotext` `pdftoppm`
- [qpdf](https://github.com/qpdf/qpdf)

選裝：

- [`3rd/image.nvim`](https://github.com/3rd/image.nvim)：buffer 內嵌頁面圖
- `pandoc` + `xelatex`，或 `paps` + `ps2pdf`：文字回寫含中文

```bash
# Debian / Ubuntu
sudo apt install poppler-utils qpdf

# macOS
brew install poppler qpdf
```

## 安裝（Neovim 0.12 `vim.pack`）

在 `init.lua` 裡用內建套件管理器即可，不必裝 lazy.nvim

```lua
vim.pack.add({
  "https://github.com/CarsonSlovoka/pdf.nvim",
  { src = "https://github.com/3rd/image.nvim" }, -- 可選，內嵌頁面圖
})

require("pdf").setup({
  view = { mode = "auto", dpi = 140 },
})
```

本機開發（這個目錄還沒有遠端 repo）把套件掛進 runtimepath，或放到 packpath：

```lua
-- 方式 A：直接 prepend（最快）
vim.opt.runtimepath:prepend("/path/to/pdf.nvim")
require("pdf").setup({
  view = { mode = "auto", dpi = 140 },
})

-- 方式 B：Vim 傳統套件目錄（重啟後自動載入 plugin/）
-- ln -s /path/to/pdf.nvim ~/.local/share/nvim/site/pack/pdf/start/pdf.nvim
```

`plugin/pdf.lua` 會在套件載入時註冊命令與自動開啟 `*.pdf`。`setup()` 只負責覆寫預設設定，不叫也有預設行為

更新已用 `vim.pack` 裝的外掛：

```lua
vim.pack.update()
```

## 使用

直接 `:e file.pdf` 或 `:PdfOpen file.pdf`

檢視（PDF buffer）：

| 鍵 | 動作 |
| --- | --- |
| `j` / `n` | 下一頁 |
| `k` / `p` | 上一頁 |
| `g` / `G` | 首頁 / 末頁 |
| `i` / `t` | 影像 / 文字 |
| `e` | 抽出文字層 |
| `f` | 表單編輯 |
| `+` / `-` | 縮放 |
| `o` | 系統閱讀器 |
| `q` | 關閉 |

命令：

```
:PdfPage 12
:PdfExtract 1-3
:PdfMerge other.pdf
:PdfSplit
:PdfRotate 90
:PdfDeletePages 2,5-6
:PdfReorder 3,1,2,4-z
:PdfCompress
:PdfTextEdit
:PdfTextWrite
:PdfForm
:PdfFormApply
```

頁面操作預設另存 `原名-xxx.pdf`，不會直接覆寫來源

## 文字層與表單的真實行為

**文字回寫**
`pdftotext` 只有字、沒有可靠的位置／字型。`:PdfTextWrite` 會產生**新的** PDF：

1. 有 `pandoc` + `xelatex`／`lualatex` 就走這條（中文可用）
2. 否則試 `paps` + `ps2pdf`
3. 再不行用內建 Helvetica 寫入（中文會變成 `?`）

**表單**
用 `qpdf --json` 讀 AcroForm，改物件的 `/V`，再 `--update-from-json` 與 `--generate-appearances`。外觀產生有 qpdf 自己的限制，複雜表單請用專門工具核對

## 設定

```lua
require("pdf").setup({
  tools = {
    pdfinfo = "pdfinfo",
    pdftotext = "pdftotext",
    pdftoppm = "pdftoppm",
    qpdf = "qpdf",
  },
  view = {
    mode = "auto", -- auto | image | text
    dpi = 140,
    zoom = 1.0,
    layout_text = true,
  },
  auto_open = true,
  confirm_overwrite = true,
  keymaps = true,
})
```

`:checkhealth pdf` 檢查工具鏈

## MVP 以後可以加

- TOC / 書籤 picker
- 全文搜尋跨頁
- 標註（highlight / note）——需要比 qpdf CLI 更完整的註解 API
- SyncTeX
- 以頁為單位的文字原地 patch（QDF 串流，脆弱）
