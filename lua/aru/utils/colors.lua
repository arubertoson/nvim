local M = {}

local function lshift(x, by)
	return x * 2 ^ by
end

local function rshift(x, by)
	return math.floor(x / 2 ^ by)
end

local function dec_to_rgb(dec)
	local r = rshift(dec, 16) % 256
	local g = rshift(dec, 8) % 256
	local b = dec % 256
	return r, g, b
end

local function rgb_to_dec(r, g, b)
	return lshift(r, 16) + lshift(g, 8) + b
end

local function adjust_brightness(r, g, b, factor)
	r = math.floor(r * factor)
	g = math.floor(g * factor)
	b = math.floor(b * factor)
	return math.max(0, math.min(255, r)), math.max(0, math.min(255, g)), math.max(0, math.min(255, b))
end

-- We assume that we want highlights from the global namespace, until another usecase arises.
function M.get_adjusted_hl(name, factor)
	local hl = vim.api.nvim_get_hl(0, { name = name, link = false})

	local r1, g1, b1 = dec_to_rgb(hl.bg)
	local r2, g2, b2 = adjust_brightness(r1, g1, b1, factor)

	return rgb_to_dec(r2, g2, b2)
end

return M
