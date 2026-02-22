local rainbow = { "Special", "Function", "Identifier", "ErrorMsg", "DiagnosticHint", "Normal" }
return {
	rainbow = function(index)
		return rainbow[index % #rainbow + 1]
	end,
	constant = "Constant",
	symbol = "Special",
	reference = "Special",
	_delim = "Special",
	delim = "_delim",
	operator = "Operator",
	hugeoperator = "Operator",
	chapter = "ErrorMsg",
	section = "Constant",
	subsection = "DiagnosticHint",
	subsubsection = "Special",
	enumerate = {
		enumi = "ErrorMsg",
		enumii = "Constant",
		enumiii = "DiagnosticHint",
		enumiv = "Special",
		error = "ErrorMsg",
	},
	itemize = { "ErrorMsg", "Constant", "DiagnosticHint", "Special", "ErrorMsg" },
	greek = "DiagnosticHint",
	operatorname = "Constant",
	arrow = "Function",
	relationship = "Identifier",
	fraction = "Constant",
	footnotemark = "Special",
	error = "ErrorMsg",
	script = "Identifier",
	default = "MathZone",
}
