-- RateLimitMiddleware
-- Stephen Leitnick
-- November 24, 2025

local function RateLimitMiddleware(rateLimit: number)
	local lastCallTime = {}
	
	return function(player: Player, args: {any})
		local lastCall = lastCallTime[player] or 0
		local now = os.clock()
		
		if now - lastCall < rateLimit then
			warn(`[RateLimit] Rate limit exceeded for {player.Name}`)
			return false
		end
		
		lastCallTime[player] = now
		return true
	end
end

return RateLimitMiddleware
