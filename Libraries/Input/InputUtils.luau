-- InputUtils
-- Utility for processing Input Schemas
-- November 23, 2025

local ContextClass = require(script.Parent.Context)

local CONTEXT_MARKER = newproxy(true)
getmetatable(CONTEXT_MARKER).__tostring = function() return "CONTEXT_MARKER" end

local ACTION_MARKER = newproxy(true)
getmetatable(ACTION_MARKER).__tostring = function() return "ACTION_MARKER" end

local InputUtils = {}

function InputUtils.Context(def: { [any]: any })
	def._MARKER = CONTEXT_MARKER
	return def
end

function InputUtils.Action(def: { [any]: any })
	def._MARKER = ACTION_MARKER
	return def
end

function InputUtils.IsContextDefinition(def: any): boolean
	return type(def) == "table" and def._MARKER == CONTEXT_MARKER
end

function InputUtils.IsActionDefinition(def: any): boolean
	return type(def) == "table" and def._MARKER == ACTION_MARKER
end

function InputUtils.CreateContextFromSchema(controller, schema)
	local contextName = schema.Name or controller.Name
	
	local context = ContextClass.new(contextName)
	
	-- Store actions for easy access
	context.Actions = {}
	
	-- Process Actions
	for _, item in pairs(schema) do
		if InputUtils.IsActionDefinition(item) then
			local actionName = item.Name
			local actionType = item.Type or "Bool"
			
			local action = context:CreateAction(actionName, actionType)
			
			-- Bindings
			if item.Bind then
				if type(item.Bind) == "table" then
					for _, bind in ipairs(item.Bind) do
						action:Bind(bind)
					end
				else
					action:Bind(item.Bind)
				end
			end
			

			
			context.Actions[actionName] = action
		end
	end
	
	return context
end

return InputUtils
