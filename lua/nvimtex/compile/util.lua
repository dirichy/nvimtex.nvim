local M = {}
function M.showlog(path)
	path = path or vim.fn.expand("%:p")
	-- 提取文件名（去除路径和.tex扩展名）
	local jobname = vim.fn.fnamemodify(path, ":t:r") --(path, "([^/]*)%.tex$")
	-- 获取文件所在目录
	local cwd = vim.fn.fnamemodify(path, ":h") --(path, "(.*)/[^/]*%.tex$")
	local cmd = table.concat({ "texlogsieve", cwd .. "/" .. jobname .. ".log", "--color" }, " ")
	-- 获取命令输出并写入 buffer
	local lines = vim.fn.systemlist(cmd)
	M.showbelow(lines)
end
function M.showbelow(lines)
	-- 计算 30% 的高度
	local total = vim.o.lines
	local height = math.floor(total * 0.3)
	if height < 1 then
		height = 1
	end

	-- 创建 scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	-- 打开普通 split 在当前窗口下方
	local win = vim.api.nvim_open_win(buf, true, {
		win = 0,
		split = "below",
		height = height,
	})

	require("baleia").setup({}).buf_set_lines(buf, 0, -1, false, lines)

	-- 设置 buffer-local 选项：filetype 和 modifiable
	vim.api.nvim_set_option_value("filetype", "terminal", { scope = "local", buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = buf })
	-- 设置 window-local 选项：concealcursor
	vim.api.nvim_set_option_value("concealcursor", "nvic", { scope = "local", win = win })

	-- 设置 buffer-local q 键映射关闭窗口
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end
return M
