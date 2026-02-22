local M = {
	config = {
		favor = { "pdflatex", "xelatex", "lualatex" },
		compile_args = { "-interaction=nonstopmode", "-file-line-error", "-synctex=1" },
	},
}
local util = require("nvimtex.util")
local bit = require("bit")
local job = require("plenary.job")
local cache = {}
local compiler = {
	pdflatex = 1,
	xelatex = 2,
	lualatex = 4,
	all = 7,
	notpdf = 6,
	notxe = 5,
	notlua = 3,
}
---@param source number|string
---@return number
function M.get_compiler_by_documentclass(source)
	local compiler_table = {
		ctexart = compiler.all - compiler.pdflatex,
		ctexbook = compiler.all - compiler.pdflatex,
		article = compiler.all,
		book = compiler.all,
	}
	local class = util.get_documentclass(source)
	return compiler_table[class.name]
end
---@param source number|string
---@return number
function M.get_compiler_by_magic_comment(source)
	return compiler[util.get_magic_comment("ts-program", true, source)] or compiler.all
end

---@param source number|string
---@return number
function M.get_compiler_by_packages(source)
	local packages = util.get_packages(source)
	local res = compiler.all
	if packages.xeCJK then
		return compiler.xelatex
	end
	if packages.luatexja or packages.luacode or packages.luadraw then
		return compiler.lualatex
	end
	if packages.CJK then
		return compiler.pdflatex
	end
	if packages.ctex or packages.fontspec or packages["unicode-math"] then
		res = bit.band(res, compiler.notpdf)
	end
	return res
end

--- smart get compiler for a buffer
---@param buffer number
---@return string?
function M.get_compiler(buffer)
	local magic_comment = M.get_compiler_by_magic_comment(buffer)
	local packages = M.get_compiler_by_packages(buffer)
	local documentclass = M.get_compiler_by_documentclass(buffer)
	local res
	if magic_comment ~= compiler.all then
		res = magic_comment
	else
		res = bit.band(packages, documentclass)
	end
	for _, program in ipairs(M.config.favor) do
		if bit.band(compiler[program], res) ~= 0 then
			return program
		end
	end
end
local function aux_need_rerun(old, new)
	if #old ~= #new then
		return true
	end
	local skip_command = {
		pgfsyspdfmark = true,
	}
	for i = 1, #old do
		local old_line = old[i]
		local new_line = new[i]
		local command = string.match(old_line, "\\(%a+)")
		if not skip_command[command] and old_line ~= new_line then
			return true
		end
	end
	return false
end
function M.compile(opts)
	opts = opts or {}
	--TODO: maybe source is not current buffer
	local source = vim.api.nvim_win_get_buf(0)
	local compile_args = vim.deepcopy(opts.compile_args or M.config.compile_args)
	local path = opts.path or vim.fn.expand("%:p")
	-- 提取文件名（去除路径和.tex扩展名）
	local jobname = vim.fn.fnamemodify(path, ":t:r") --(path, "([^/]*)%.tex$")
	-- 获取文件所在目录
	local cwd = vim.fn.fnamemodify(path, ":h") --(path, "(.*)/[^/]*%.tex$")
	local log = util.readfile(cwd .. "/" .. jobname .. ".log")
	local aux = util.readfile(cwd .. "/" .. jobname .. ".aux")
	local bcf = util.readfile(cwd .. "/" .. jobname .. ".bcf")
	table.insert(compile_args, jobname)
	local command = opts.command or M.get_compiler(source)
	if not command then
		error("Can't guess which compiler to use, please set compiler mamually")
	end

	local on_exit = function(j, return_val)
		if return_val == 0 then
			local new_aux = util.readfile(cwd .. "/" .. jobname .. ".aux")
			if aux_need_rerun(aux, new_aux) then
				vim.schedule(function()
					M.compile(opts)
				end)
				return true
			end
			local out = table.concat(j:result(), "\n")
			vim.notify(out, vim.log.levels.INFO)
		else
			vim.schedule(function()
				util.showbelow(j:result())
			end)
		end
	end
	job:new({ command = command, cwd = cwd, args = compile_args, on_exit = on_exit }):start()
end
return M
