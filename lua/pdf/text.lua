local cli = require("pdf.cli")
local config = require("pdf.config")
local state = require("pdf.state")
local util = require("pdf.util")

local M = {}

local function session_or_err()
  local s = state.get()
  if not s then
    util.err("目前不是 PDF buffer")
    return nil
  end
  return s
end

function M.extract_all(path)
  return cli.pdftotext(path, { layout = config.get().view.layout_text })
end

function M.extract_page(path, page)
  return cli.pdftotext(path, {
    layout = config.get().view.layout_text,
    first = page,
    last = page,
  })
end

--- Open an editable text buffer for the whole document.
function M.edit()
  local s = session_or_err()
  if not s then
    return
  end
  local text, err = M.extract_all(s.path)
  if not text then
    util.err(err or "無法抽出文字")
    return
  end
  local buf = vim.api.nvim_create_buf(true, true)
  local name = s.path .. ".txt"
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].filetype = "text"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.b[buf].pdf_source = s.path
  vim.b[buf].pdf_kind = "text-edit"
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  util.notify("文字層已抽出。:w 或 :PdfTextWrite 會匯出成新 PDF（無法保留原排版）")
end

local function latin1_ok(s)
  return not s:find("[\128-\255]") or not util.has_cjk(s)
end

local function escape_pdf_string(s)
  s = s:gsub("\\", "\\\\"):gsub("%(", "\\("):gsub("%)", "\\)")
  return s
end

--- Minimal PDF 1.4 writer (Helvetica / WinAnsi). Fallback when no better engine exists.
local function write_simple_pdf(lines, out)
  local pages = {}
  local content_objs = {}
  local page_w, page_h = 595, 842 -- A4
  local margin = 50
  local leading = 12
  local font_size = 10
  local max_lines = math.floor((page_h - 2 * margin) / leading)

  local function flush_page(page_lines)
    local stream = { "BT", "/F1 " .. font_size .. " Tf", leading .. " TL" }
    table.insert(stream, string.format("1 0 0 1 %d %d Tm", margin, page_h - margin))
    for _, line in ipairs(page_lines) do
      line = line:gsub("\r", "")
      -- drop bytes we cannot encode
      line = line:gsub("[\128-\255]", "?")
      table.insert(stream, "(" .. escape_pdf_string(line) .. ") '")
    end
    table.insert(stream, "ET")
    table.insert(content_objs, table.concat(stream, "\n"))
    table.insert(pages, #content_objs)
  end

  local bucket = {}
  for _, line in ipairs(lines) do
    table.insert(bucket, line)
    if #bucket >= max_lines then
      flush_page(bucket)
      bucket = {}
    end
  end
  if #bucket > 0 or #pages == 0 then
    flush_page(bucket)
  end

  local objs = {}
  local function add(s)
    table.insert(objs, s)
    return #objs
  end

  add("<< /Type /Catalog /Pages 2 0 R >>") -- 1
  -- 2 filled later
  add("placeholder")
  local font_id = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

  local content_ids = {}
  local page_ids = {}
  for i, stream in ipairs(content_objs) do
    content_ids[i] = add(string.format("<< /Length %d >>\nstream\n%s\nendstream", #stream, stream))
  end
  for i, _ in ipairs(content_objs) do
    page_ids[i] = add(string.format(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >> >>",
      page_w,
      page_h,
      content_ids[i],
      font_id
    ))
  end

  local kids = {}
  for _, id in ipairs(page_ids) do
    table.insert(kids, id .. " 0 R")
  end
  objs[2] = string.format("<< /Type /Pages /Kids [%s] /Count %d >>", table.concat(kids, " "), #page_ids)

  local chunks = { "%PDF-1.4\n" }
  local xref = { 0 }
  local pos = #chunks[1]
  for i, obj in ipairs(objs) do
    local piece = string.format("%d 0 obj\n%s\nendobj\n", i, obj)
    table.insert(chunks, piece)
    table.insert(xref, pos)
    pos = pos + #piece
  end
  local xref_pos = pos
  local xref_tbl = { "xref", string.format("0 %d", #objs + 1), "0000000000 65535 f " }
  for i = 1, #objs do
    table.insert(xref_tbl, string.format("%010d 00000 n ", xref[i + 1]))
  end
  table.insert(chunks, table.concat(xref_tbl, "\n") .. "\n")
  table.insert(
    chunks,
    string.format("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", #objs + 1, xref_pos)
  )
  return util.write_file(out, table.concat(chunks, ""))
end

local function write_via_pandoc(text_path, out)
  local pandoc = cli.which("pandoc")
  if not pandoc then
    return false, "no pandoc"
  end
  for _, engine in ipairs({ "xelatex", "lualatex", "wkhtmltopdf", "weasyprint", "pdflatex" }) do
    if util.executable(engine) then
      local _, ok, err = util.run({ pandoc, text_path, "-o", out, "--pdf-engine=" .. engine })
      if ok and vim.fn.filereadable(out) == 1 then
        return true
      end
      err = err
    end
  end
  -- pandoc without engine may still emit PDF via default
  local _, ok = util.run({ pandoc, text_path, "-o", out })
  return ok and vim.fn.filereadable(out) == 1, "pandoc failed"
end

local function write_via_paps(text_path, out)
  local paps = cli.which("paps")
  local ps2pdf = cli.which("ps2pdf")
  if not paps or not ps2pdf then
    return false, "no paps"
  end
  local ps = out .. ".ps"
  local _, ok, err = util.run({ "sh", "-c", string.format("%s --encoding=UTF-8 %s > %s", vim.fn.shellescape(paps), vim.fn.shellescape(text_path), vim.fn.shellescape(ps)) })
  if not ok then
    return false, err
  end
  local _, ok2, err2 = util.run({ ps2pdf, ps, out })
  os.remove(ps)
  return ok2, err2
end

function M.write(out)
  local buf = vim.api.nvim_get_current_buf()
  local source = vim.b[buf].pdf_source
  local s = state.get()
  if not source and s then
    source = s.path
  end
  if not source then
    util.err("沒有對應的 PDF 來源")
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  out = (out and out ~= "") and vim.fn.fnamemodify(out, ":p") or util.sibling(source, "-text")
  if vim.fn.filereadable(out) == 1 and config.get().confirm_overwrite then
    if not util.confirm("覆寫 " .. out .. " ?") then
      return
    end
  end

  local tmp = vim.fn.tempname() .. ".txt"
  util.write_file(tmp, table.concat(lines, "\n"))

  local ok = false
  local why
  ok, why = write_via_pandoc(tmp, out)
  if not ok then
    ok, why = write_via_paps(tmp, out)
  end
  if not ok then
    local text = table.concat(lines, "\n")
    if util.has_cjk(text) then
      util.warn("未找到 pandoc/xelatex 或 paps，內建寫入只支援 Latin；中文會變成 ?")
    end
    local w_ok, w_err = write_simple_pdf(lines, out)
    ok = w_ok
    why = w_err
  end
  os.remove(tmp)
  if not ok then
    util.err("寫出 PDF 失敗：" .. tostring(why))
    return
  end
  util.notify("已匯出文字 PDF：" .. out)
  require("pdf").open(out)
end

return M
