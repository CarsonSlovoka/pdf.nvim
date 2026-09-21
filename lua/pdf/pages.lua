local cli = require("pdf.cli")
local config = require("pdf.config")
local state = require("pdf.state")
local util = require("pdf.util")

local M = {}

local function session_or_err()
  local s = state.get()
  if not s then
    util.err("目前不是 PDF buffer，請先 :PdfOpen")
    return nil
  end
  return s
end

local function dest_path(s, suffix, explicit)
  if explicit and explicit ~= "" then
    return vim.fn.fnamemodify(explicit, ":p")
  end
  return util.sibling(s.path, suffix)
end

local function maybe_overwrite(path)
  if vim.fn.filereadable(path) == 1 and config.get().confirm_overwrite then
    return util.confirm("覆寫 " .. path .. " ?")
  end
  return true
end

local function run_and_open(s, args, out)
  local _, err = cli.qpdf(args)
  if err then
    util.err(err)
    return
  end
  util.notify("已寫入 " .. out)
  if out ~= s.path then
    require("pdf").open(out)
  else
    require("pdf.viewer").reload(s)
  end
end

function M.extract(range, out)
  local s = session_or_err()
  if not s then
    return
  end
  range = range or tostring(s.page)
  out = dest_path(s, "-p" .. range:gsub("[^%w%-]+", "_"), out)
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { s.path, "--pages", ".", range, "--", out }, out)
end

function M.merge(other, out)
  local s = session_or_err()
  if not s then
    return
  end
  if not other or other == "" then
    util.err("用法：:PdfMerge {file} [output]")
    return
  end
  other = vim.fn.fnamemodify(other, ":p")
  if vim.fn.filereadable(other) ~= 1 then
    util.err("找不到 " .. other)
    return
  end
  out = dest_path(s, "-merged", out)
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { "--empty", "--pages", s.path, other, "--", out }, out)
end

function M.split(outdir)
  local s = session_or_err()
  if not s then
    return
  end
  outdir = outdir and outdir ~= "" and outdir or vim.fs.joinpath(util.dirname(s.path), util.stem(s.path) .. "-pages")
  util.ensure_dir(outdir)
  local pattern = vim.fs.joinpath(outdir, "page-%d.pdf")
  local _, err = cli.qpdf({ s.path, "--split-pages=1", pattern })
  if err then
    -- older qpdf may not expand %d the same way; fall back
    local fallback = vim.fs.joinpath(outdir, "page.pdf")
    _, err = cli.qpdf({ "--split-pages=1", s.path, fallback })
    if err then
      util.err(err)
      return
    end
  end
  util.notify("已拆到 " .. outdir)
end

function M.rotate(angle, pages)
  local s = session_or_err()
  if not s then
    return
  end
  angle = tonumber(angle) or 90
  if angle ~= 90 and angle ~= 180 and angle ~= 270 and angle ~= -90 then
    util.err("角度只支援 90 / 180 / 270 / -90")
    return
  end
  pages = (pages and pages ~= "") and pages or tostring(s.page)
  local spec = string.format("%+d:%s", angle, pages)
  local out = dest_path(s, "-rot")
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { "--rotate=" .. spec, s.path, out }, out)
end

function M.delete(pages)
  local s = session_or_err()
  if not s then
    return
  end
  pages = pages or tostring(s.page)
  -- keep everything except listed pages: build inverse range via qpdf by listing keepers
  local drop = {}
  for part in pages:gmatch("[^,]+") do
    local a, b = part:match("^(%d+)%-(%d+)$")
    if a then
      for i = tonumber(a), tonumber(b) do
        drop[i] = true
      end
    else
      local n = tonumber(part)
      if n then
        drop[n] = true
      end
    end
  end
  local keep = {}
  for i = 1, s.pages do
    if not drop[i] then
      table.insert(keep, tostring(i))
    end
  end
  if #keep == 0 then
    util.err("不能刪光所有頁")
    return
  end
  local out = dest_path(s, "-edit")
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { s.path, "--pages", ".", table.concat(keep, ","), "--", out }, out)
end

function M.reorder(order)
  local s = session_or_err()
  if not s then
    return
  end
  if not order or order == "" then
    util.err("用法：:PdfReorder 3,1,2,4-z")
    return
  end
  local out = dest_path(s, "-reorder")
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { s.path, "--pages", ".", order, "--", out }, out)
end

function M.compress(out)
  local s = session_or_err()
  if not s then
    return
  end
  out = dest_path(s, "-opt", out)
  if not maybe_overwrite(out) then
    return
  end
  run_and_open(s, { "--compress-streams=y", "--recompress-flate", "--object-streams=generate", s.path, out }, out)
end

return M
