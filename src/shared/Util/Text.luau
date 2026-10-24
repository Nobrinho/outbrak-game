--!strict
-- Text helpers. string.upper only knows ASCII, so Portuguese accents would stay lowercase
-- ("MUNIçãO"); upper() also maps the accented letters the game's texts use.

local Text = {}

local ACCENTS: { [string]: string } = {
	["á"] = "Á",
	["à"] = "À",
	["â"] = "Â",
	["ã"] = "Ã",
	["é"] = "É",
	["ê"] = "Ê",
	["í"] = "Í",
	["ó"] = "Ó",
	["ô"] = "Ô",
	["õ"] = "Õ",
	["ú"] = "Ú",
	["ç"] = "Ç",
}

function Text.upper(s: string): string
	local upper = string.upper(s)
	for lower, capital in ACCENTS do
		upper = string.gsub(upper, lower, capital)
	end
	return upper
end

return Text
