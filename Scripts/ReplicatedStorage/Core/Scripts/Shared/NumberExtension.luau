local NumberExtension = {}

--格式化大数字
function NumberExtension.FormatBigNumber(num: number): string
	if num < 1e3 then
		return tostring(num)
	elseif num < 1e6 then
		return math.floor(num / 10) / 100 .. "K"
	elseif num < 1e9 then
		return math.floor(num / 1e4) / 100 .. "M"
	elseif num < 1e12 then
		return math.floor(num / 1e7) / 100 .. "B"
	elseif num < 1e15 then
		return math.floor(num / 1e10) / 100 .. "T"
	elseif num < 1e18 then
		return math.floor(num / 1e13) / 100 .. "Q"
	elseif num < 1e21 then
		return math.floor(num / 1e16) / 100 .. "Qi"
	elseif num < 1e24 then
		return math.floor(num / 1e19) / 100 .. "S"
	elseif num < 1e27 then
		return math.floor(num / 1e22) / 100 .. "Sp"
	elseif num < 1e30 then
		return math.floor(num / 1e25) / 100 .. "O"
	elseif num < 1e33 then
		return math.floor(num / 1e28) / 100 .. "N"
	else
		return math.floor(num / 1e31) / 100 .. "D"
	end
end

return NumberExtension
