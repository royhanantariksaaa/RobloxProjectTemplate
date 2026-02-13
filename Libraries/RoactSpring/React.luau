local Library = script.Parent.Parent
local Roact = Library:FindFirstChild("Roact")

if Roact then
	return require(Roact)
end

error("Roact/React not found in Library. Ensure Roact is present in " .. Library:GetFullName())
