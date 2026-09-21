local M = {}

function M.create()
  local cmd = vim.api.nvim_create_user_command

  cmd("PdfOpen", function(opts)
    require("pdf").open(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", complete = "file", desc = "Open a PDF in pdf.nvim" })

  cmd("PdfNext", function()
    require("pdf.viewer").next()
  end, { desc = "Next PDF page" })

  cmd("PdfPrev", function()
    require("pdf.viewer").prev()
  end, { desc = "Previous PDF page" })

  cmd("PdfPage", function(opts)
    require("pdf.viewer").goto_page(tonumber(opts.args))
  end, { nargs = 1, desc = "Go to PDF page" })

  cmd("PdfMode", function(opts)
    require("pdf.viewer").set_mode(opts.args)
  end, {
    nargs = 1,
    complete = function()
      return { "image", "text" }
    end,
    desc = "Switch image/text view",
  })

  cmd("PdfInfo", function()
    require("pdf.viewer").info()
  end, { desc = "Show PDF metadata" })

  cmd("PdfExternal", function()
    require("pdf.viewer").external()
  end, { desc = "Open PDF in system viewer" })

  cmd("PdfExtract", function(opts)
    local a = vim.split(opts.args or "", "%s+", { trimempty = true })
    require("pdf.pages").extract(a[1], a[2])
  end, { nargs = "+", desc = "Extract page range to a new PDF" })

  cmd("PdfMerge", function(opts)
    local a = vim.split(opts.args or "", "%s+", { trimempty = true })
    require("pdf.pages").merge(a[1], a[2])
  end, { nargs = "+", complete = "file", desc = "Merge another PDF after this one" })

  cmd("PdfSplit", function(opts)
    require("pdf.pages").split(opts.args)
  end, { nargs = "?", complete = "dir", desc = "Split into single-page PDFs" })

  cmd("PdfRotate", function(opts)
    local a = vim.split(opts.args or "", "%s+", { trimempty = true })
    require("pdf.pages").rotate(a[1], a[2])
  end, { nargs = "+", desc = "Rotate pages: :PdfRotate 90 [pages]" })

  cmd("PdfDeletePages", function(opts)
    require("pdf.pages").delete(opts.args)
  end, { nargs = "?", desc = "Delete pages from a copy of the PDF" })

  cmd("PdfReorder", function(opts)
    require("pdf.pages").reorder(opts.args)
  end, { nargs = 1, desc = "Reorder pages: :PdfReorder 3,1,2,4-z" })

  cmd("PdfCompress", function(opts)
    require("pdf.pages").compress(opts.args)
  end, { nargs = "?", complete = "file", desc = "Compress streams with qpdf" })

  cmd("PdfTextEdit", function()
    require("pdf.text").edit()
  end, { desc = "Extract text layer into an editable buffer" })

  cmd("PdfTextWrite", function(opts)
    require("pdf.text").write(opts.args)
  end, { nargs = "?", complete = "file", desc = "Write edited text to a new PDF" })

  cmd("PdfForm", function()
    require("pdf.form").open_editor()
  end, { desc = "Open AcroForm field editor" })

  cmd("PdfFormApply", function(opts)
    require("pdf.form").apply(opts.args)
  end, { nargs = "?", complete = "file", desc = "Write form values back to a new PDF" })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = vim.api.nvim_create_augroup("PdfNvimWrite", { clear = true }),
    pattern = { "*.txt", "*.form.ini" },
    callback = function(ev)
      local kind = vim.b[ev.buf].pdf_kind
      if kind == "text-edit" then
        require("pdf.text").write()
        vim.bo[ev.buf].modified = false
      elseif kind == "form-edit" then
        require("pdf.form").apply()
        vim.bo[ev.buf].modified = false
      end
    end,
  })
end

return M
