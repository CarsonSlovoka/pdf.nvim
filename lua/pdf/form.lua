local cli = require("pdf.cli")
local config = require("pdf.config")
local state = require("pdf.state")
local util = require("pdf.util")

local M = {}

local function session_or_err()
  local s = state.get()
  if not s then
    -- form edit buffers keep source on b:
    local src = vim.b.pdf_source
    if src then
      return { path = src, bufnr = vim.api.nvim_get_current_buf() }
    end
    util.err("目前不是 PDF buffer")
    return nil
  end
  return s
end

local function field_name(f)
  return f.fullyqualifiedname or f.fullqualifiedname or f.partialfieldname or f.name
end

local function field_value(f)
  local v = f.fieldvalue or f.value or f.currentvalue
  if type(v) == "table" then
    return vim.inspect(v)
  end
  return v and tostring(v) or ""
end

local function field_type(f)
  return f.fieldtype or f.type or ""
end

local function field_object(f)
  return f.object or f.obj or f.field
end

function M.list(path)
  local data, err = cli.qpdf_json(path, { "acroform" })
  if not data then
    return nil, err
  end
  local acro = data.acroform or {}
  local fields = acro.fields or {}
  if type(fields) ~= "table" then
    return {}
  end
  -- qpdf may return object map or array
  if fields[1] then
    return fields
  end
  local list = {}
  for _, v in pairs(fields) do
    if type(v) == "table" then
      table.insert(list, v)
    end
  end
  return list
end

function M.open_editor()
  local s = session_or_err()
  if not s then
    return
  end
  local fields, err = M.list(s.path)
  if not fields then
    util.err(err or "無法讀取表單")
    return
  end
  if #fields == 0 then
    util.warn("這個 PDF 沒有 AcroForm 欄位")
    return
  end
  local lines = {
    "# pdf.nvim form",
    "# 格式：欄位名稱 = 值",
    "# :PdfFormApply 寫回（另存 *-filled.pdf）",
    "# source: " .. s.path,
    "",
  }
  for _, f in ipairs(fields) do
    local name = field_name(f)
    if name and name ~= "" then
      table.insert(lines, string.format("# type %s object %s", field_type(f), tostring(field_object(f) or "")))
      table.insert(lines, string.format("%s = %s", name, field_value(f)))
      table.insert(lines, "")
    end
  end
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, s.path .. ".form.ini")
  vim.bo[buf].filetype = "dosini"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.b[buf].pdf_source = s.path
  vim.b[buf].pdf_kind = "form-edit"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
end

local function parse_editor(bufnr)
  local values = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local k, v = line:match("^%s*(.-)%s*=%s*(.*)$")
      if k and k ~= "" then
        values[k] = v
      end
    end
  end
  return values
end

local function parse_obj_ref(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local n, g = ref:match("^(%d+)%s+(%d+)%s+R$")
  if n then
    return n, g or "0"
  end
  n = ref:match("^(%d+)$")
  if n then
    return n, "0"
  end
end

local function set_v_in_obj(obj, value)
  -- qpdf JSON v2: object is { "value": { "/V": "...", "/T": "...", ... } } or similar
  if type(obj) ~= "table" then
    return false
  end
  if obj.value and type(obj.value) == "table" then
    obj.value["/V"] = value
    return true
  end
  if obj["/V"] ~= nil or obj["/T"] then
    obj["/V"] = value
    return true
  end
  -- walk one level
  for _, v in pairs(obj) do
    if type(v) == "table" and (v["/T"] or v["/FT"] or v["/V"] ~= nil) then
      v["/V"] = value
      return true
    end
  end
  return false
end

function M.apply(out)
  local buf = vim.api.nvim_get_current_buf()
  local source = vim.b[buf].pdf_source
  local s = state.get()
  if not source and s then
    source = s.path
  end
  if not source then
    util.err("沒有表單來源 PDF")
    return
  end
  local values = parse_editor(buf)
  local fields, err = M.list(source)
  if not fields then
    util.err(err or "無法讀取表單")
    return
  end

  local wanted = {}
  for _, f in ipairs(fields) do
    local name = field_name(f)
    if name and values[name] ~= nil then
      local obj = field_object(f)
      local n, g = parse_obj_ref(tostring(obj or ""))
      if n then
        table.insert(wanted, { n = n, g = g, value = values[name], name = name })
      end
    end
  end
  if #wanted == 0 then
    util.err("沒有可寫入的欄位（JSON 裡缺少 object 參照，或欄位名對不上）")
    return
  end

  local json_args = { "--json-output" }
  for _, w in ipairs(wanted) do
    table.insert(json_args, string.format("--json-object=%s,%s", w.n, w.g))
  end
  table.insert(json_args, source)
  local dumped, jerr = cli.qpdf(json_args)
  if not dumped then
    util.err(jerr or "qpdf --json-output 失敗")
    return
  end
  local data, derr = util.json_decode(dumped)
  if not data then
    util.err("解析 qpdf JSON 失敗：" .. tostring(derr))
    return
  end

  local qpdf_objs = data.qpdf and data.qpdf[2] or data.objects or data
  local patched = 0
  for _, w in ipairs(wanted) do
    local key = string.format("%s %s R", w.n, w.g)
    local obj = qpdf_objs and (qpdf_objs[key] or qpdf_objs[w.n .. " 0 R"])
    if not obj and data.qpdf then
      -- v2 layout: qpdf is array [meta, objects]
      for _, block in ipairs(data.qpdf) do
        if type(block) == "table" and block[key] then
          obj = block[key]
          qpdf_objs = block
          break
        end
      end
    end
    if obj and set_v_in_obj(obj, w.value) then
      patched = patched + 1
    end
  end
  if patched == 0 then
    util.err("無法在 JSON 物件裡寫入 /V。qpdf 版本可能過舊或表單結構特殊。")
    return
  end

  out = (out and out ~= "") and vim.fn.fnamemodify(out, ":p") or util.sibling(source, "-filled")
  if vim.fn.filereadable(out) == 1 and config.get().confirm_overwrite then
    if not util.confirm("覆寫 " .. out .. " ?") then
      return
    end
  end

  local patch = vim.fn.tempname() .. ".json"
  util.write_file(patch, vim.json.encode(data))
  local _, uerr = cli.qpdf({ source, "--update-from-json=" .. patch, out })
  os.remove(patch)
  if uerr then
    util.err(uerr)
    return
  end
  -- best-effort appearance regeneration
  cli.qpdf({ out, "--generate-appearances", "--replace-input" })
  util.notify(string.format("已填寫 %d 個欄位 → %s", patched, out))
  require("pdf").open(out)
end

return M
