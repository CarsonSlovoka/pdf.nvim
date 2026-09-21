local cli = require("pdf.cli")
local config = require("pdf.config")
local state = require("pdf.state")
local textmod = require("pdf.text")
local util = require("pdf.util")

local M = {}

local function image_api()
  local ok, image = pcall(require, "image")
  if ok and image then
    return image
  end
  local ok2, snacks = pcall(require, "snacks.image")
  if ok2 and snacks then
    return snacks
  end
  return nil
end

local function cache_prefix(s)
  local dir = vim.fs.joinpath(config.get().view.cache_dir, vim.fn.sha256(s.path):sub(1, 16))
  util.ensure_dir(dir)
  return vim.fs.joinpath(dir, "page")
end

local function header(s)
  return {
    string.format("pdf.nvim  %s  page %d/%d  zoom %.0f%%", s.mode, s.page, s.pages, s.zoom * 100),
    "file: " .. s.path,
    "keys: j/n next  k/p prev  g/G first/last  i image  t text  e edit-text  f form  +/− zoom  o external  q close",
    "",
  }
end

local function set_buf_opts(bufnr, path)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].filetype = "pdf"
  vim.bo[bufnr].binary = false
  pcall(vim.api.nvim_buf_set_name, bufnr, path)
end

local function map(bufnr)
  if not config.get().keymaps then
    return
  end
  local function n(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, desc = "pdf: " .. desc })
  end
  n("j", function()
    M.next()
  end, "next page")
  n("n", function()
    M.next()
  end, "next page")
  n("<PageDown>", function()
    M.next()
  end, "next page")
  n("k", function()
    M.prev()
  end, "prev page")
  n("p", function()
    M.prev()
  end, "prev page")
  n("<PageUp>", function()
    M.prev()
  end, "prev page")
  n("g", function()
    M.goto_page(1)
  end, "first page")
  n("G", function()
    M.goto_page(nil, true)
  end, "last page")
  n("i", function()
    M.set_mode("image")
  end, "image mode")
  n("t", function()
    M.set_mode("text")
  end, "text mode")
  n("e", function()
    require("pdf.text").edit()
  end, "edit text layer")
  n("f", function()
    require("pdf.form").open_editor()
  end, "edit form")
  n("+", function()
    M.zoom(1)
  end, "zoom in")
  n("=", function()
    M.zoom(1)
  end, "zoom in")
  n("-", function()
    M.zoom(-1)
  end, "zoom out")
  n("o", function()
    M.external()
  end, "open external")
  n("r", function()
    M.reload()
  end, "reload")
  n("q", function()
    vim.cmd("bdelete")
  end, "close")
end

local function clear_image(s)
  if s.image then
    pcall(function()
      if s.image.clear then
        s.image:clear()
      elseif s.image.close then
        s.image:close()
      end
    end)
    s.image = nil
  end
end

local function render_image(s)
  local api = image_api()
  local dpi = math.floor(config.get().view.dpi * s.zoom)
  local prefix = cache_prefix(s)
  local png, err = cli.pdftoppm(s.path, prefix, { page = s.page, dpi = dpi })
  local lines = header(s)
  if not png then
    table.insert(lines, "影像轉檔失敗：" .. tostring(err))
    table.insert(lines, "自動退回文字模式。")
    s.mode = "text"
    local t = textmod.extract_page(s.path, s.page) or ""
    for _, l in ipairs(vim.split(t, "\n", { plain = true })) do
      table.insert(lines, l)
    end
    util.buf_set_lines(s.bufnr, lines)
    return
  end
  table.insert(lines, "raster: " .. png)
  if not api then
    table.insert(lines, "")
    table.insert(lines, "未偵測到 image.nvim / snacks.image，只快取 PNG。")
    table.insert(lines, "可安裝 3rd/image.nvim，或按 o 用系統閱讀器開啟。")
    table.insert(lines, "")
    local t = textmod.extract_page(s.path, s.page) or ""
    for _, l in ipairs(vim.split(t, "\n", { plain = true })) do
      table.insert(lines, l)
    end
  end
  util.buf_set_lines(s.bufnr, lines)
  if api and api.from_file then
    clear_image(s)
    local ok, img = pcall(api.from_file, png, {
      buffer = s.bufnr,
      window = vim.api.nvim_get_current_win(),
      with_virtual_padding = true,
    })
    if ok and img then
      s.image = img
      pcall(function()
        img:render()
      end)
    end
  end
end

local function render_text(s)
  clear_image(s)
  local t, err = textmod.extract_page(s.path, s.page)
  local lines = header(s)
  if not t then
    table.insert(lines, "文字抽取失敗：" .. tostring(err))
  else
    for _, l in ipairs(vim.split(t, "\n", { plain = true })) do
      table.insert(lines, l)
    end
  end
  util.buf_set_lines(s.bufnr, lines)
end

function M.render(s)
  s = s or state.get()
  if not s then
    return
  end
  if s.page < 1 then
    s.page = 1
  end
  if s.pages > 0 and s.page > s.pages then
    s.page = s.pages
  end
  if s.mode == "image" then
    render_image(s)
  else
    render_text(s)
  end
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.foldcolumn = "0"
  vim.wo.wrap = s.mode == "text"
end

function M.reload(s)
  s = s or state.get()
  if not s then
    return
  end
  local info = cli.pdfinfo(s.path)
  if info then
    s.info = info
    s.pages = info.pages
  end
  M.render(s)
end

local function pick_mode(requested, info)
  if requested and requested ~= "auto" then
    return requested
  end
  local pref = config.get().view.mode
  if pref == "text" then
    return "text"
  end
  if pref == "image" or pref == "auto" then
    if cli.which("pdftoppm") and image_api() then
      return "image"
    end
    if pref == "image" and cli.which("pdftoppm") then
      return "image"
    end
    return "text"
  end
  return "text"
end

function M.attach(bufnr, path, opts)
  opts = opts or {}
  path = util.abs(path)
  local info, err = cli.pdfinfo(path)
  if not info then
    util.err("無法讀取 PDF：" .. tostring(err))
    return
  end
  set_buf_opts(bufnr, path)
  local session = state.set(bufnr, {
    bufnr = bufnr,
    path = path,
    pages = info.pages,
    page = opts.page or 1,
    mode = pick_mode(opts.mode, info),
    zoom = opts.zoom or config.get().view.zoom,
    info = info,
  })
  map(bufnr)
  M.render(session)
  return session
end

function M.goto_page(n, last)
  local s = state.get()
  if not s then
    return
  end
  if last then
    n = s.pages
  end
  n = tonumber(n)
  if not n then
    return
  end
  s.page = math.max(1, math.min(s.pages, n))
  M.render(s)
end

function M.next()
  local s = state.get()
  if not s then
    return
  end
  M.goto_page(s.page + 1)
end

function M.prev()
  local s = state.get()
  if not s then
    return
  end
  M.goto_page(s.page - 1)
end

function M.set_mode(mode)
  local s = state.get()
  if not s then
    return
  end
  if mode ~= "image" and mode ~= "text" then
    util.err("mode 只能是 image 或 text")
    return
  end
  s.mode = mode
  M.render(s)
end

function M.zoom(dir)
  local s = state.get()
  if not s then
    return
  end
  local cfg = config.get().view
  s.zoom = math.max(cfg.min_zoom, math.min(cfg.max_zoom, s.zoom + dir * cfg.zoom_step))
  M.render(s)
end

function M.external(path)
  local s = state.get()
  path = path or (s and s.path)
  if not path then
    util.err("沒有 PDF 路徑")
    return
  end
  local cmd = config.get().tools.open or util.default_open_cmd()
  vim.fn.jobstart({ cmd, path }, { detach = true })
end

function M.info()
  local s = state.get()
  if not s then
    util.err("目前不是 PDF buffer")
    return
  end
  local lines = { "pdf.nvim info", "" }
  local keys = { "Title", "Author", "Creator", "Producer", "CreationDate", "ModDate", "Pages", "Page size", "Encrypted", "PDF version" }
  for _, k in ipairs(keys) do
    if s.info[k] then
      table.insert(lines, string.format("%s: %s", k, s.info[k]))
    end
  end
  util.notify(table.concat(lines, "\n"))
  print(table.concat(lines, "\n"))
end

return M
