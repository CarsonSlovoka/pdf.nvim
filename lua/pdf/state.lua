local M = {}

---@class PdfSession
---@field bufnr integer
---@field path string
---@field pages integer
---@field page integer
---@field mode "image"|"text"
---@field zoom number
---@field info table
---@field dirty boolean
---@field image any|nil

local sessions = {}

function M.get(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return sessions[bufnr]
end

function M.set(bufnr, session)
  sessions[bufnr] = session
  return session
end

function M.clear(bufnr)
  local s = sessions[bufnr]
  if s and s.image and s.image.clear then
    pcall(function()
      s.image:clear()
    end)
  end
  sessions[bufnr] = nil
end

function M.for_path(path)
  path = vim.fn.fnamemodify(path, ":p")
  for _, s in pairs(sessions) do
    if s.path == path then
      return s
    end
  end
end

vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("PdfNvimState", { clear = true }),
  callback = function(ev)
    M.clear(ev.buf)
  end,
})

return M
