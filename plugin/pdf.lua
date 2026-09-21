if vim.g.loaded_pdf_nvim then
  return
end
vim.g.loaded_pdf_nvim = true

require("pdf.commands").create()

local group = vim.api.nvim_create_augroup("PdfNvimAutoOpen", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = { "*.pdf", "*.PDF" },
  callback = function(ev)
    if require("pdf.config").get().auto_open then
      require("pdf").open(ev.file, { bufnr = ev.buf })
    end
  end,
})

-- lazy.nvim 若用 ft=pdf 載入，BufReadCmd 可能已經錯過；FileType 再掛一次
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "pdf",
  callback = function(ev)
    if not require("pdf.config").get().auto_open then
      return
    end
    if require("pdf.state").get(ev.buf) then
      return
    end
    local name = vim.api.nvim_buf_get_name(ev.buf)
    if name:lower():match("%.pdf$") then
      require("pdf").open(name, { bufnr = ev.buf })
    end
  end,
})
