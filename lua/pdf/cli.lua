local config = require("pdf.config")
local util = require("pdf.util")

local M = {}

local function tool(name)
  return config.get().tools[name] or name
end

function M.which(name)
  local bin = tool(name)
  if util.executable(bin) then
    return bin
  end
  return nil
end

function M.require_tool(name)
  local bin = M.which(name)
  if not bin then
    util.err(("找不到指令 `%s`（請安裝 poppler-utils / qpdf）"):format(tool(name)))
    return nil
  end
  return bin
end

function M.pdfinfo(path)
  local bin = M.require_tool("pdfinfo")
  if not bin then
    return nil
  end
  local out, ok, err = util.run({ bin, path })
  if not ok then
    return nil, err ~= "" and err or out
  end
  local info = { raw = out, path = path }
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    local k, v = line:match("^([^:]+):%s*(.*)$")
    if k then
      info[k] = v
    end
  end
  info.pages = tonumber((info.Pages or ""):match("%d+")) or 0
  info.title = info.Title
  info.encrypted = (info.Encrypted or ""):lower():find("yes") ~= nil
  return info
end

function M.pdftotext(path, opts)
  opts = opts or {}
  local bin = M.require_tool("pdftotext")
  if not bin then
    return nil
  end
  local argv = { bin }
  if opts.layout ~= false then
    table.insert(argv, "-layout")
  end
  if opts.first then
    table.insert(argv, "-f")
    table.insert(argv, tostring(opts.first))
  end
  if opts.last then
    table.insert(argv, "-l")
    table.insert(argv, tostring(opts.last))
  end
  table.insert(argv, path)
  table.insert(argv, "-")
  local out, ok, err = util.run(argv, { trim = false })
  if not ok then
    return nil, err ~= "" and err or out
  end
  return out
end

function M.pdftoppm(path, dest_prefix, opts)
  opts = opts or {}
  local bin = M.require_tool("pdftoppm")
  if not bin then
    return nil
  end
  local dpi = opts.dpi or config.get().view.dpi
  local argv = { bin, "-png", "-r", tostring(dpi), "-f", tostring(opts.page), "-l", tostring(opts.page), path, dest_prefix }
  local _, ok, err = util.run(argv)
  if not ok then
    return nil, err
  end
  -- pdftoppm writes prefix-N.png (sometimes prefix-01.png)
  local page = tonumber(opts.page) or 1
  local candidates = {
    dest_prefix .. "-" .. page .. ".png",
    dest_prefix .. "-" .. string.format("%d", page) .. ".png",
    dest_prefix .. "-" .. string.format("%02d", page) .. ".png",
    dest_prefix .. "-" .. string.format("%03d", page) .. ".png",
    dest_prefix .. ".png",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end
  local found = vim.fn.glob(dest_prefix .. "*.png", false, true)
  if found and found[1] then
    return found[1]
  end
  return nil, "pdftoppm 沒有產生 PNG"
end

function M.qpdf(args)
  local bin = M.require_tool("qpdf")
  if not bin then
    return nil, "qpdf missing"
  end
  local argv = { bin }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  local out, ok, err = util.run(argv, { trim = false })
  if not ok then
    return nil, (err ~= "" and err or out)
  end
  return out or ""
end

function M.qpdf_json(path, keys)
  local args = { "--json" }
  if keys then
    for _, k in ipairs(keys) do
      table.insert(args, "--json-key=" .. k)
    end
  end
  table.insert(args, path)
  local out, err = M.qpdf(args)
  if not out then
    return nil, err
  end
  return util.json_decode(out)
end

return M
