-- SETUP ENVIRONMENT VARIABLES =========================================================================================
-- register global environment variables here. some may be set by the engine, so check if they first before giving them some kind of default value

-- host program should set, blank string otherwise. consider renaming to INSTALLATION_PATH since it refers to that maybe? or are files stored in another folder inside the installation path?
CACHE_PATH = CACHE_PATH or "" 

-- NOTE: The 'print' function will be overrided by the engine so that the engine handles outputting print mesasages

-- override package.path here cause it gets set to some to some dumb value when 'package' is loaded in luaL_openLibs() call in UE, in the future we should overwrite luaL_openLibs to fix this but also to control what default packages load to remove the unnecessary ones
package.path = LUA_PATH
package.cpath = "C:\\Users\\imdoe\\AppData\\Roaming\\luarocks\\lib\\lua\\5.1\\?.dll"

local ffi = require"ffi"
local bit = require"bit"

-- COOL LUA HACKS ==================================================================================================
-- found this trick online, this converts primitive function 'next' to a local variable, meaning its lookup will be faster, since a global variable is accessed by hashing into the environment table. local access is always quicker!
local next = next
local type = type

-- BASIC STRUCTURES ===============================================================================================
MATH CLASS
-- interpolate from a to b by t which moves in the range 0.0 to 1.0
Lerp = function(a, b, t)
	return a * (1 - t) + b * t
end
SET CLASS
LIST CLASS
List.length = 0
List.Init = function(instance, ...)
	local elements = {...}
	for _,v in elements do
		List.Add(instance, v)
	end
end
List.Add = function(instance, value)
	table.insert(instance, value)
	instance.length = instance.length + 1
end
List.Remove = function(instance, index)
	table.remove(instance, index)
	instance.length = instance.length - 1
end
QUEUE CLASS
Queue.first = 0
Queue.last = 0
Queue.length = 0
Queue.Peek = function(instance)
	return instance[instance.first]
end
Queue.Enqueue = function(instance, value)
	instance.last = instance.last + 1
	instance[instance.last] = value
	instance.length = instance.length + 1
end
Queue.Dequeue = function(instance)
	local value = instance[instance.first]
	instance[instance.first] = nil
	instance.first = instance.first + 1
	instance.length = instance.length - 1
	return value
end
ENUM CLASS
EVENT LISTENER CLASS -- it's just a 'pair' object with a listener and a callback I CALL U BACKKKKK
EventListener.Init = function(instance, listener, callback)
	self.listener = listener
	self.callback = callback
end

-- BASIC SYSTEMS ====================================================================================================
I/O CLASS

NETWORK CLASS

FILE CLASS
File.files = setmetatable({}, {__mode = "v"}) -- STATIC VAR
File.PendingFileLoads = setmetatable({}, {__mode = "k"}) -- STATIC VAR
File.RunWhenLoaded = function(file, eventListener)
	-- if 'PendingFileLoads' contains an entry for 'file', then add the eventListener to the list for that listener
	local listeners = File.PendingFileLoads[file]
	if listeners then
		-- if 'listeners' already contains a table for 'eventListener.listener', add this callback to that table array-style. This allows one listener to have multiple callbacks, even duplicates of the same callback function.
		local callbacks = listeners[eventListener.listener]
		if callbacks then
			table.insert(callbacks, eventListener.callback)
		else
			-- if 'listeners' did not yet contain a table for 'eventListener.listener', initialize one with the callback as the first entry of the array
			listeners[eventListener.listener] = {eventListener.callback}
		end
	else
		-- if there was no entry for 'file' in 'PendingFileLoads', it means that the file has already been loaded, so just run the callback immediately
		eventListener.callback(eventListener.listener, file)
	end
end
File.GetFile = function(uuid, eventListener)
	local file = files[uuid]
	if file then
		if eventListener then
			File.RunWhenLoaded(file, eventListener)
		end
		return file
	end

	-- if we reached here, it means the file is not registered in the file system, so we gotta create that bishhhhhhhhhh
	-- we initialize the file and its metatable here so that its immediately referenceable while its contents load. Also assign the 'uuid' here (remember not all class, mesh, texture, etc. objects will have a 'uuid' associated with them since they can also be programmatically created instead of loaded from a file. WAIT WE MAY WANT THIS AS AN OBJECT PROPERTY INSTEAD OF A METATABLE PROPERTY SINCE NON-CLASS FILES STORE DATA IN THE OBJECTS, MAYBE THEY CAN BE STATIC VALUES IN CLASSES SO THAT INSTANCES DON'T COPY THEM? COULD WE DO THE SAME FOR DEPENDENCIES???
	local mt = {uuid = uuid}
	file = setmetatable({}, mt)
	files[uuid] = file

	-- Insert file into 'PendingFileLoads' here instead of in 'Class()' because that function is also used for making classes directly from code rather than loading from files. And there's no case where we skip it entirely since the file will be pending load for at least a frame since files will be loaded via a multi-threaded load queue.
	File.PendingFileLoads[file] = WeakKeysTable()
	
	if eventListener then
		-- listeners is a table which maps objects to an array-style table which contains callback functions, thus which can include duplicate functions
		local listeners = File.PendingFileLoads[file]
		listeners[eventListener.listener] = {eventListener.callback}
	end

	-- TESTING FILE LOADING FROM STORAGE
	local data = ReadFile(CACHE_PATH .. "/" .. uuid)-- .. ".lua")
	if data then
		-- scan for the file extension to use the appropriate loading operation, first by finding the period then retrieving the rest of the string
		local index = string.find(uuid, ".", 1, true)
		if index then
			-- NOTE: index '-1' refers to the last character of the string, negative indexes wrap around to the end of the string in lua
			local extension = string.sub(uuid, index + 1, -1)
			if extension == "lua" then
				local func = assert(loadstring(data))
				func(file)
			elseif extension == "png" then
				LoadPng(file, data)
			end
		end
	end
	
	
	
	local OnReceivedCallback = function()
		
	end
	
	-- ATTEMPT TO LOAD VIA VARIOUS methods
	
	return file
end
File.GetFiles = function(files, eventListener)
	local CheckLoads = function(caller, loadedFile)
		--remove loaded file from files
		files[loadedFile] = nil
		if table.isEmpty(files) then
			eventListener.callback(eventListener.listener)
		end
		--check if the list is empty, if so run OnLoadedCallback
	end
	for i,_ in files do
	-- could prob use the parameter eventListener.listener for the individual file listener arguments.
		GetFile(i, EventListener(eventListener.listener, function(caller, loadedFile)
			files[loadedFile] = nil
			if table.isEmpty(files) then
				eventListener.callback(eventListener.listener)
			end
		end))
	end
end

PHYSICS CLASS
Physics.Raycast = function(Origin, EndLocation, LayerMask)
	-- UE.Raycast3d or 2d depending on layermask hahahahahaaaaaaaaaaaaaaaaaa
	-- maybe layers also have a property associated which indicates 2d or 3d, maybe another property can have an assigned "color", so a layer is really like an object with the layer name and all its metadata
end

INPUT CLASS
Input.KeyPressedListeners = WeakKeysTable()
Input.IsKeyPressed = function(key)
	return true -- check engine to see if key is being pressed. it won't be graphics engine i guess, what will it be? InputAPI?
	-- actually might wanna just reigster this directly from engine
end
Input.OnKeyPressed(key, eventListener)
Input.OnKeyReleased(key, eventListener)
Input.mouseEventListeners = {}
Input.mouseRaycastResultCache = {} -- maps bitmask (an integer) to a hit result table, which includes distance, so ray can be fired again if the callback requires further distance to be checked. technically it can even start from the ending point of the last ray, since that distance has already been checked hahahaha

-- wait it only adds the key when one object wants to listen on that key
Input.OnKeyPressed(key, EventListener)
	for mask, listeners in mouseEventListeners["press"][key] do
		result = Physics.Raycast(...........)
		listener = listeners[result.hitObject]
		if listener and listener.maxDistance < result.distance then
			listener.callback(listener, result)
		end
	end
end
Input.OnMousePress = function(key, eventListener, maxDistance, layerMask)
	local keys = mouseEventListeners["press"]
	if not keys then
		keys = {}
		mouseEventListeners["press"] = keys
	end
	
	local masks = keys[key]
	if not masks then
		masks = {}
		keys[key] = masks
	end
	
	local listeners = masks[mask]
	if not listeners then
		listeners = {}
		masks[mask] = listeners
		-- i think we wanted to do something here and i forgot what, something about how we're trying to store the callbacks for easiest add/remove maybe? now that we figured out how they look in code, we can figure this out too
	end
	
	local value = listeners[eventListener.listener]
	if not value then
		-- value doesn't exist, so add the new callback there
		listeners[eventListener.listener] = {callback = eventListener.callback, maxDistance = maxDistance}
	elseif InstanceOf(value, List) then
		-- value is already a list, just add the new callback
		listeners[eventListener.listener].Add({callback = eventListener.callback, maxDistance = maxDistance})
	else
		-- value is a callback, create a list in its place with the callback that was there and the new one
		listeners[eventListener.listener] = List(listeners[eventListener.listener], {callback = eventListener.callback, maxDistance = maxDistance})
	end
end
Input.OnMouseClick = function(key, eventListener, maxDistance, layerMask)
	-- 'click' requires us to fire a ray on the press event too because when the release event occurs, we need to confirm that the object released over is the same object as the one most recently pressed on
	-- HOWEVER, THIS IS KINDA REDUDANT IF THERE'S LIKE 100 OF THIS SAME FUNC FOR 100 CLICK EVENTS. CAN'T THIS JUST BE A ONE AND DONE THING? WELL NO BECAUSE OF THE SPECIFIC RAY RIGHT? YEAH I GUESS
	local pressed = false
	Input.OnKeyPressed(key, EventListener(eventListener.listener, function(listener)
		local ray = Input.mouseRaycastResultCache[layerMask]
		if not ray or ray.distance < maxDistance then
			ray = Physics.Raycast(mousePosToWorld, mouseWorldDirection, layerMask)
			Input.mouseRaycastResultCache[layerMask] = ray
		end
		
		-- check if this object was hit by the ray, and if so mark the flag
		if ray.hitObject == listener then
			pressed = true
		end
	end))
	Input.OnKeyReleased(key, EventListener(eventListener.listener, function(listener)
		-- if this object was not pressed, abort
		if not pressed then
			return false
		end
		pressed = false
	
		-- check if we are releasing over the same key that was most recently 'pressed', assume for now we are
		local ray = Input.mouseRaycastResultCache[layerMask]
		if not ray or ray.distance < maxDistance then
			ray = Physics.Raycast(mousePosToWorld, mouseWorldDirection, layerMask)
			Input.mouseRaycastResultCache[layerMask] = ray
		end
		
		if ray.HitObject == listener then
			eventListener.callback(listener)
		end
		
		return true
	end))
end
Input.OnMousePress = function(key, eventListener, maxDistance, layerMask)
	Input.OnKeyPressed(key, EventListener(eventListener.listener, function(listener)
		local ray = Input.mouseRaycastResultCache[layerMask]
		if not ray or ray.distance < maxDistance then
			ray = Physics.Raycast(mousePosToWorld, mouseWorldDirection, layerMask)
			Input.mouseRaycastResultCache[layerMask] = ray
		end
		
		if ray.hitObject == listener then
			eventListener.callback(listener)
		end
		
		return true
	end))
end
Input.OnMouseRelease = function(key, eventListener)
	Input.OnKeyReleased(key, EventListener(eventListener.listener, function(listener)	
		local ray = Input.mouseRaycastResultCache[layerMask]
		if not ray or ray.distance < maxDistance then
			ray = Physics.Raycast(mousePosToWorld, mouseWorldDirection, layerMask)
			Input.mouseRaycastResultCache[layerMask] = ray
		end
		
		if ray.HitObject == listener then
			eventListener.callback(listener)
		end
		
		return true
	end))
end
Input.OnMouseHover = function(eventListener, layerMask)
	local hovered = true
	Graphics.OnTick(EventListener(eventListener.listener, function(listener)
		local ray = Input.mouseRaycastResultCache[layerMask]
		if not ray or ray.distance < maxDistance then
			ray = Physics.Raycast(mousePosToWorld, mouseWorldDirection, layerMask)
			Input.mouseRaycastResultCache[layerMask] = ray
		end
		
		if ray.HitObject == listener then
			if not hovered then
				eventListener.callback(listener)
				hovered = true
			end
			return true
		elseif ray.HitObject ~= listener and hovered then
			if hovered then
				hovered = false
			end
			hovered = false
			return false
		end
	end))
end
Input.OnMouseUnhover = function(eventListener)
	
end
-- subscribing to input events may utilize optional parameters to identify an event's priority in the order that "fire" runs callbacks. By default, they can all have the same priority. There doesn't need to be a parameter for whether the event should be removed from the list when triggered once, a nonce basically, because that can be easily implemented by the user. A listener's code could simply remove itself from the list, code that fires an event to many listeners can itself clear the list of listeners after firing, code that fires an event could use an algorithm to determine whether a listener should have their callback run or not, etc.









-- COMMON HELPER FUNCTIONS ==========================================================================================

DeepCopy = function

-- adding a custom empty table check function
table.isEmpty = function(t)
	return next(t) == nil
end

a 'Class()' function? not sure it's even needed with our cool new loading system. a loader func is both a parser and a class constructor

-- 'self' should be a class object, 'class' is the target class we want to check if 'self' is a subclass of
function SubclassOf(class, targetClass)
	if class == targetClass then
		return true
	end
	
	local searchList = List()
	searchList:Push(class)
	while searchList.length > 0 do
		local curClass = searchList:PopLeft()
		mt = getmetatable(parent)
		if mt.parents[targetClass] then
			return true
		else
			for i,_ in pairs(mt.parents) do
				searchList:Push(i)
			end
		end
	end
	
	return false
end

function InstanceOf(object, class)
	return SubclassOf(getmetatable(object).classObject, class)
end  


-- GRAPHICS ENGINE RENDER TICK ==========================================================================================
API STUFF ???
TickDelegates
API IS FOR ENGINE
AN INTERFACE FOR THE ENGINE
ENGINE INTERFACE?
GRAPHICS API ! -- similar to Render Hardware Interface (RHI) in UE, i wonder if we can set this up so like users can use a unity or UE version of the platform lol

GraphicsAPI.OnTick(timeSinceLastTick)

WAIT AN OBJECT2D CAN BE ANYTHING, AN OBJECT IN UNITY, AN APPLICATION WINDOW ON WINDOWS, A SCREEN ON AN EMBEDDED SYSTEM. UNVIERSAL AF NO? SO IT SEEMS ITS AN OBJECT HERE IN LUA PRIMARILY, AND DEPENDING ON WHAT SYSTEM ITS CREATED FOR, IT WILL CREATE A CORRESPONDING OBJECT AND CREATE A C-POINTER FOR IT


-- All below are common classes, but prob should be in core
BASE CLASS? both have:
parent
Vector2 -- should build this using ffi right? is it more efficient?
Transform2D
init = function(instance, parent)
	instance.parent = parent
	instance.position = Vector2()
	instance.rotation = 0
	instance.size = Vector2()
	-- after all the transform's properties are ready, register it within its parent's list of children
	if parent then
		parent.children -- add this new instance to the parent's children
	end
end

OBJECT2D CLASS
init = function(instance, parent)
	instance.transform = Transform2D(parent)
	-- create Object2D in UE and grab its cPtr
end
BUTTON CLASS -- inherits from Object2D
init = function(instance, parent, OnClicked)
	-- call parent cstr
	-- setup OnClicked callback to run
end
OBJECT3D CLASS
MESH CLASS
IMAGE CLASS
ANIMATION CLASS
STATE MACHINE CLASS -- must subscribe to engine tick delegates for animation ticking

SOFTWARE EDITOR CLASS -- our first 'project'
init = function(instance)
	PlayButton = Button(nil, function()
		-- PRINT SOMETHING OUT !!!
	end)
end