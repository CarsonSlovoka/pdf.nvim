local config = require("pdf.config")
local viewer = require("pdf.viewer")

local M = {}

function M.setup(opts)
  config.setup(opts)
  require("pdf.commands").create()
end

function M.open(path, opts)
  opts = opts or {}
  if not path or path == "" then
    path = vim.fn.expand("%:p")
  end
  path = vim.fn.fnamemodify(path, ":p")
  if vim.fn.filereadable(path) ~= 1 then
    require("pdf.util").err("找不到檔案：" .. tostring(path))
    return
  end
  local bufnr = opts.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    vim.cmd.edit(vim.fn.fnameescape(path))
    bufnr = vim.api.nvim_get_current_buf()
    local existing = require("pdf.state").get(bufnr)
    if existing and existing.path == path then
      return existing
    end
  end
  return viewer.attach(bufnr, path, opts)
end

-- convenience re-exports
M.next = viewer.next
M.prev = viewer.prev
M.page = viewer.goto_page
M.mode = viewer.set_mode

return M
