-- Option
-- Stephen Leitnick
-- August 11, 2020

--[=[
	@class Option

	Represents an optional value that may or may not exist.
	Useful for avoiding nil checks and providing safe access to values.

	```lua
	local Option = require(Packages.Option)

	local maybeValue = Option.Some(42)
	local noValue = Option.None

	maybeValue:Match {
		Some = function(value)
			print("Value:", value)
		end,
		None = function()
			print("No value")
		end,
	}
	```
]=]

-- Type exports for autocomplete
export type Option<T> = {
	Match: (self: Option<T>, matches: { Some: ((value: T) -> any)?, None: (() -> any)? }) -> any,
	Unwrap: (self: Option<T>) -> T,
	UnwrapOr: (self: Option<T>, default: T) -> T,
	Expect: (self: Option<T>, msg: string) -> T,
	IsSome: (self: Option<T>) -> boolean,
	IsNone: (self: Option<T>) -> boolean,
	Contains: (self: Option<T>, value: T) -> boolean,
}

local Option = {}
Option.__index = Option

--[=[
	@within Option
	@function Some
	@param value T -- The value to wrap
	@return Option<T>
	
	Creates an Option containing a value.
]=]
function Option.Some(value)
	assert(value ~= nil, "Option.Some value cannot be nil")
	return setmetatable({
		_v = value,
		_s = true,
	}, Option)
end

--[=[
	@within Option
	@function Wrap
	@param value T? -- The value to wrap (may be nil)
	@return Option<T>
	
	Creates an Option from a value that may be nil.
	Returns Some if value exists, None if nil.
]=]
function Option.Wrap(value)
	if value ~= nil then
		return Option.Some(value)
	else
		return Option.None
	end
end

--[=[
	@within Option
	@function Is
	@param obj any -- Object to check
	@return boolean
	
	Checks if the given object is an Option.
]=]
function Option.Is(obj)
	return type(obj) == "table" and getmetatable(obj) == Option
end

--[=[
	@within Option
	@method Match
	@param matches { Some: ((value: T) -> any)?, None: (() -> any)? }
	@return any
	
	Pattern matches on the Option, calling the appropriate handler.
]=]
function Option:Match(matches)
	if self._s then
		if matches.Some then
			return matches.Some(self._v)
		end
	elseif matches.None then
		return matches.None()
	end
	return nil
end

--[=[
	@within Option
	@method Unwrap
	@return T
	
	Returns the contained value.
	@error "Cannot unwrap None option" -- Throws if called on None
]=]
function Option:Unwrap()
	if self._s then
		return self._v
	end
	error("Cannot unwrap None option", 2)
end

--[=[
	@within Option
	@method UnwrapOr
	@param default T -- Default value if None
	@return T
	
	Returns the contained value or the provided default.
]=]
function Option:UnwrapOr(default)
	if self._s then
		return self._v
	end
	return default
end

--[=[
	@within Option
	@method Expect
	@param msg string -- Error message if None
	@return T
	
	Returns the contained value or throws with the provided message.
]=]
function Option:Expect(msg)
	if self._s then
		return self._v
	end
	error(msg, 2)
end

--[=[
	@within Option
	@method IsSome
	@return boolean
	
	Returns true if the Option contains a value.
]=]
function Option:IsSome()
	return self._s
end

--[=[
	@within Option
	@method IsNone
	@return boolean
	
	Returns true if the Option is empty.
]=]
function Option:IsNone()
	return not self._s
end

--[=[
	@within Option
	@method Contains
	@param value T -- Value to check
	@return boolean
	
	Returns true if the Option contains the specified value.
]=]
function Option:Contains(value)
	return self._s and self._v == value
end

--[=[
	@within Option
	@prop None Option<any>
	
	Represents the absence of a value.
]=]
Option.None = setmetatable({
	_s = false,
}, Option)

return Option
