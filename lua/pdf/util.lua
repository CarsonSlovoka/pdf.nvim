local M = {}

function M.notify(msg, level)
  vim.notify("[pdf.nvim] " .. msg, level or vim.log.levels.INFO)
end

function M.err(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

function M.executable(name)
  return name and name ~= "" and vim.fn.executable(name) == 1
end

function M.ensure_dir(path)
  vim.fn.mkdir(path, "p")
  return path
end

function M.basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

function M.stem(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

function M.dirname(path)
  return vim.fn.fnamemodify(path, ":h")
end

function M.abs(path)
  return vim.fn.fnamemodify(path, ":p")
end

function M.sibling(path, suffix)
  local dir = M.dirname(path)
  local stem = M.stem(path)
  return vim.fs.joinpath(dir, stem .. suffix .. ".pdf")
end

--- Run a command. argv is a list. Returns stdout, ok, stderr.
function M.run(argv, opts)
  opts = opts or {}
  local cmd = table.concat(vim.tbl_map(function(x)
    return vim.fn.shellescape(tostring(x))
  end, argv), " ")
  local stderr_file = vim.fn.tempname()
  local full = cmd .. " 2> " .. vim.fn.shellescape(stderr_file)
  local out = vim.fn.system(full)
  local ok = vim.v.shell_error == 0
  local err = ""
  local f = io.open(stderr_file, "r")
  if f then
    err = f:read("*a") or ""
    f:close()
    os.remove(stderr_file)
  end
  if opts.trim ~= false then
    out = (out or ""):gsub("%s+$", "")
    err = err:gsub("%s+$", "")
  end
  return out, ok, err
end

function M.write_file(path, content)
  M.ensure_dir(M.dirname(path))
  local f, e = io.open(path, "w")
  if not f then
    return false, e
  end
  f:write(content)
  f:close()
  return true
end

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

--- Parse qpdf/pdf page ranges like "1-3,5,8-z"
function M.parse_range(spec)
  spec = vim.trim(spec or "")
  if spec == "" then
    return nil, "empty page range"
  end
  return spec
end

function M.confirm(prompt)
  local ans = vim.fn.confirm(prompt, "&Yes\n&No", 2)
  return ans == 1
end

function M.default_open_cmd()
  if vim.fn.has("mac") == 1 then
    return "open"
  elseif vim.fn.has("win32") == 1 then
    return "start"
  end
  return "xdg-open"
end

function M.has_cjk(s)
  return s:find("[\228-\233]") ~= nil -- rough UTF-8 CJK lead bytes
end

function M.buf_set_lines(bufnr, lines)
  local mod = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = mod
end

function M.json_decode(s)
  local ok, data = pcall(vim.json.decode, s)
  if ok then
    return data
  end
  return nil, data
end

return M
