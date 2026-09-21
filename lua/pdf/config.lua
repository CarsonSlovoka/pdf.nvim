local M = {}

local defaults = {
  tools = {
    pdfinfo = "pdfinfo",
    pdftotext = "pdftotext",
    pdftoppm = "pdftoppm",
    qpdf = "qpdf",
    -- optional helpers used when available
    pandoc = "pandoc",
    paps = "paps",
    ps2pdf = "ps2pdf",
    open = nil, -- auto: xdg-open / open / start
  },
  view = {
    mode = "auto", -- auto | image | text
    dpi = 140,
    zoom = 1.0,
    zoom_step = 0.15,
    min_zoom = 0.4,
    max_zoom = 3.0,
    cache_dir = nil, -- default: stdpath("cache")/pdf.nvim
    layout_text = true, -- pdftotext -layout
  },
  auto_open = true,
  confirm_overwrite = true,
  keymaps = true,
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if not M.values.view.cache_dir or M.values.view.cache_dir == "" then
    M.values.view.cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "pdf.nvim")
  end
  return M.values
end

function M.get()
  if not M.values.view.cache_dir then
    M.setup()
  end
  return M.values
end

return M
