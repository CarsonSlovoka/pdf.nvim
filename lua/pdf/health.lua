local cli = require("pdf.cli")
local config = require("pdf.config")

local M = {}

function M.check()
  vim.health.start("pdf.nvim") -- 段落
  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("需要 Neovim 0.12+（本插件以 vim.pack / 0.12 API 為前提）")
  end

  local required = { "pdfinfo", "pdftotext", "pdftoppm", "qpdf" }
  for _, name in ipairs(required) do
    local bin = cli.which(name)
    if bin then
      vim.health.ok(name .. " → " .. bin)
    else
      vim.health.error("缺少 " .. (config.get().tools[name] or name) .. "（poppler-utils / qpdf）")
    end
  end

  vim.health.start("pdf.nvim optional")
  local optional = { "pandoc", "paps", "ps2pdf" }
  for _, name in ipairs(optional) do
    local bin = cli.which(name)
    if bin then
      vim.health.ok(name .. " → " .. bin)
    else
      vim.health.info(name .. " 未安裝（文字回寫中文時建議安裝 pandoc+xelatex 或 paps）")
    end
  end

  local ok_img = pcall(require, "image")
  local ok_snacks = pcall(require, "snacks.image")
  if ok_img then
    vim.health.ok("image.nvim 可用（影像頁預覽）")
  elseif ok_snacks then
    vim.health.ok("snacks.image 可用（影像頁預覽）")
  else
    vim.health.info("未安裝 image.nvim；影像模式會改顯示快取 PNG 路徑 + 文字")
  end
end

return M
