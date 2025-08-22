-- override package.path here cause it gets set to some to some dumb value when 'package' is loaded in luaL_openLibs() call in UE, in the future we should overwrite luaL_openLibs to fix this but also to control what default packages load to remove the unnecessary ones
package.path = LUA_PATH
package.cpath = "C:\\Users\\imdoe\\AppData\\Roaming\\luarocks\\lib\\lua\\5.1\\?.dll"

local ffi = require"ffi"
local bit = require"bit"

-- 'isServer' global variable set from engine will be true if program is running on a server, false if running on a client
-- use bit.tohex(number) to convert a value into hexadecimal
-- use tonumber(string, base) to convert an encoded data string with an arbitrary base back into a number

-- found this trick online, this converts primitive function 'next' to a local variable, meaning its lookup will be faster, since a global variable is accessed by hashing into the environment table. local access is always quicker!
local next = next



print = API_PrintString




-- API library for Lua and the engine to communicate with each other, containing functions which can callback either way
API = {}

-- doesn't overwrite if CACHE_PATH is set by the host program before this script is run
CACHE_PATH = CACHE_PATH or "" 

require"World3DEditor"
--API_PrintString(GOODBABY)

-- for now updating a network variable uses a single function, though in the future when we design our compiler we can use distinct functions for each network update type to avoid an indirect jump from branching. Network variables might be set frequently so this should be a pretty high-priority optimization.
SetNetworkVariable = function(object, name, value)
	object[name] = value
	-- if broadcast once per loop, then add it to a list that another function will iterate through to RPC every change
	-- if broadcast every change, immediately fire an RPC to change it (UE fires them at the end of the frame for network efficiency, we could also consider optimizing the new system by firing not immediately but as a group with other RPCs for network efficiency, or simply fired at the end of frame if not enough were produced to be sent as a group)
end



NetworkVariableChanges = {}
-- we'll need some kind of API_SendRPC(functionID - whatever func we want to be called, data - the arguments, possibly compressed)
--API.TickDelegates:Subscribe(nil, function(self, deltaTime))
--	for i,v in pairs(NetworkVariableChanges) do
		
--	end
--	table.clear(NetworkVariableChanges)
--end



IsTableEmpty = function(t)
	return next(t) == nil
end

-- 'Set' maker function from lua online guide
-- exampleSet = Set{"val1", "val2", "val3"}
Set = function(list)
	local set = {}
	for _, v in ipairs(list) do
		set[v] = true
	end
	return Set
end

-- the seen parameter is meant to be ignored by the initial caller, as its only used recursively to deal with recursive table properties
DeepCopy = function(src, seen)
	if type(src) == 'cdata' then
		local ctype = ffi.typeof(src)
		local copy = ctype()
		ffi.copy(copy, src, ffi.sizeof(ctype))
		return copy
	end
	if type(src) ~= 'table' then
		return src
	end
	if seen and seen[src] then
		return seen[src]
	end
	
	
	local s = seen or {}
	local copy = {}
	s[src] = copy
	for i,v  in pairs(src) do
		--if type(v) == 'cdata' then
			--copy[DeepCopy(i, s)] = ffi.copy(
		copy[DeepCopy(i, s)] = DeepCopy(v, s)
	end
	
	return setmetatable(copy, getmetatable(src))
end

-- interpolate from a to b by t which moves in the range 0.0 to 1.0
Lerp = function(a, b, t)
	return a * (1 - t) + b * t
end

-- not sure if we need this vvv
function AddPropertyModifiers(object, name, ...)
	local modifiers = {...}
	-- convert modifiers from table to set for easier searching when its stored
	local set = {}
	for i,v in pairs(modifiers) do
		set[v] = true
	end
	
	getmetatable(object).modifiers[name] = set
end

function CreateClass(name, parents)
	--local name = debug.getinfo(1, "n").name THIS OVERRIDES NAME IN A BAD WAY DONT DO IT LOL
	-- a class is just a table which acts as the 'metatable' for its instances (for prototype object pattern)
	local class = {}
	local mt = {}
	-- class and mt need to be kept separate so that class only contains its default values that need to be copied and not any metamethods or metavalues
	
	-- custom metavalue to denote an object's type; to distinguish between class and instance, just check if the object equals the metatable since a class is its own metatable!
	mt.__call = function(self, ...)
		local o = setmetatable({}, getmetatable(self))
		
		-- DO A DEEP COPY OF ALL VALUES IN CLASS OBJECT -> NEW INSTANCE OBJECT
		for i,v in pairs(self) do
			if type(v) == 'table' or type(v) == 'cdata' then
				local modifiers = mt[i]
				if modifiers ~= nil and modifiers.pointer then
					o[i] = v
				else
					o[i] = DeepCopy(v)
				end
			else
				o[i] = v
			end
			-- IF THE VALUE IS A TABLE, IF ITS A POINTER, SET DIRECTLY, IF ITS A VALUE, SET BY MAKING A DEEP COPY
			-- we could prob store that info in the class metatable. its a property that for the most part will only get checked for creating instances. when other classes wanna reference those values, they can do so by normal means of assigning the value (which is already a ptr) or making a deep copy if they care to
		end
		
		if self.Init then
			self.Init(o, ...)
		end
		
		return o
	end
	mt.type = name
	-- parents should be kept as indexed by integers rather than be a set because order matters for initialization and possibly other things
	mt.parents = parents
	mt.modifiers = {}
	
	if parents then
		for i=1, #parents do
			for i, v in pairs(parents[i]) do
				--if i ~= 'parents' then PARENTS STORED IN CLASS METATABLE NOW, SHOULDN'T BE AN ISSUE HERE!
					class[i] = v
				--end
			end
		end
	end	
	
	-- this metatable will be shared by the class with all its instances
	setmetatable(class, mt)
	
	-- set the newly created class object as a global variable
	_G[name] = class
end

-- 'name' is a string, a basic name for the class which need not be unique
-- 'dependencies' is a set of either tables or strings, where strings correspond to UUIDs of class files that need to be retrieved from the file system, and tables correspond to class objects that are either already loaded files or programmatically generated class objects
-- 'onDependenciesLoaded' is the class body itself which works as a setup function, consider renaming to 'setup'
-- 'premadeClassObject' works like an 'out' parameter that lets callers pass in an existing table to be populated by the setup function 'onDependenciesLoaded' instead of creating a new table in this function and populating that, thus avoiding having to copy the properties of the returned class object into the existing file object. It's useful for file loading since the class object must be created and referenceable before the class file is actually loaded.
Class = function(name, dependencies, onDependenciesLoaded, premadeClassObject)
	
	-- this class implementation follows the prototype object pattern, where classes are objects themselves
	-- metatables are shared between classes and their instances, as they define behaviors such as operator overrides. They may also store useful information such as a reference to the class object for instances to easily refer to it.
	
	-- if the out parameter 'premadeClassObject' exists, use that as the class object with its metatable. Otherwise create a new table and metatable for the class object. In any case, the class object will be returned by the function. (maybe we can optimize in the future by not returning anything if the out parameter was given? Not sure it would make a big difference. Maybe good to just remove confusion/redundancy?)
	local mt
	local classObject
	if premadeClassObject then
		mt = getmetatable(premadeClassObject)
		classObject = premadeClassObject
	else
		mt = {}
		classObject = setmetatable({}, mt)
	end
	

	-- assign the setup function's environment to be the class object. this can be done at anytime, as every function has an environment variable as an upvalue I'm pretty sure from what I've read, so might as well assign it here.
	--setfenv(onDependenciesLoaded, classObject)
	
	-- TODO: WE COULD PROBABLY MOVE A BUNCH OF THESE PROPERTIES TO THE CLASS OBJECT ITSELF AND MAKE THEM STATIC SO THAT INSTANCES DON'T COPY THEM, THOUGH IT WOULD ADD SLIGHTLY MORE WORK WHEN CREATING INSTANCES TO TRAVERSE THESE PROPERTIES AS WELL. HMMMMMMMMMMMMMM
	mt.classObject = classObject
	mt.type = name
	-- NOTE: parent table is mapped as classObject -> index order for faster searching (in 'SubclassOf' for example) while maintaining information about order of inheritance
	mt.parents = {}
	mt.modifiers = {}
	mt.__call = function(self, constructor, ...)
		local o = setmetatable({}, getmetatable(self))
		
		if constructor then
			constructor(o, ...)
		end
		
		return o
	end
	
	--mt.__gc BIG NOTE: I read in the lua manual that the __gc method needs to be in the metatable when you assign it to the object. Could maybe create __gc then set metatable to the object again as a workaround. Do testing to verify.
	
	-- reference dependencies from this class's metatable to keep them alive
	mt.dependencies = {}
	
	if not dependencies then
		return classObject
	end
	
	-- we must do two traversals of dependencies, the first to count references and the next to actually request class dependencies from UUIDs. We cannot do it in the same traversal because if the first dependency is already loaded, its callback will run immediately and reference count will become 0, prompting the class to load even if there are still more dependencies to load. Doing two traversals is more efficient than any alternative to counting references, since storing and traversing a table for remaining dependencies would require much more work. To optimize, however, instead of creating a separate table with only strings, we set non-string dependencies to nil (these are existing class objects, so no loading necessary) which does not cause the table to resize at all, then we add them to the metatable dependency list here, and in the second traversal, the iterator will only traverse the remaining string keys, meaning we avoid needing to check again if the values are strings or not.
	local numUnloadedDependencies = 0
	for i,_ in pairs(dependencies) do
		if type(i) ~= "string" then
			mt.dependencies[i] = true
			dependencies[i] = nil
		else
			numUnloadedDependencies = numUnloadedDependencies + 1
		end
	end
	
	if numUnloadedDependencies == 0 then
		onDependenciesLoaded()
		-- if this class object exists in 'PendingFileLoads', run its event listener callbacks if any. This is only for classes loaded from files
		local listeners = File.PendingFileLoads[classObject]
		if listeners then
			for listener,callbacks in pairs(listeners) do
				for _,callback in pairs(callbacks) do
					callback(listener, classObject)
				end
				--if v.listener then
				--	v.callback(v.listener, classObject)
				--end
			end
			-- remove this file from 'PendingFileLoads' now that it's loaded
			File.PendingFileLoads[classObject] = nil
		end
	else
		for i,_ in pairs(dependencies) do
			-- now load the dependency file with a call to GetFile, and assign its callback operations
			local dependencyFile = GetFile(i, EventListener{classObject, function(callerFile, loadedFile)
				numUnloadedDependencies = numUnloadedDependencies - 1
				if numUnloadedDependencies == 0 then
					onDependenciesLoaded()
					-- if this class object exists in 'PendingFileLoads', run its event listener callbacks if any. This is only for classes loaded from files
					local listeners = File.PendingFileLoads[callerFile]
					if listeners then
						for listener,callbacks in pairs(listeners) do
							for _,callback in pairs(callbacks) do
								callback(listener, callerFile)
							end
						end
						-- remove this file from 'PendingFileLoads' now that it's loaded
						File.PendingFileLoads[callerFile] = nil
					end
				end
			end})
			-- add dependency file that 'GetFile' returned to the metatable dependency list
			mt.dependencies[dependencyFile] = true
		end
	end
	
	
	
	-- TODO: COME BACK TO INHERITANCE IMPLEMENTATION LATER, SHOULD MOVE THIS LOGIC TO WHEN CLASS GETS LOADED, OR MAYBE IT SHOULD BE INSIDE SETUP FUNCTION ITSELF?
	--if mt.parents then
	--	for i=1, #mt.parents do
	--		for i, v in pairs(mt.parents[i]) do
	--			classObject[i] = v
	--		end
	--	end
	--end
	
	return classObject
end

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


CreateClass("NetworkList")

CreateClass("Network")
Network.networkIDs = NetworkList() -- maps integer to a network ID for some network object
Network.networkObjects = {} -- maps network ID to a network object
Network.pendingNetworkObjectLoads = {} -- a set which contains network objects yet to be instantiated. The ID must exist in 'networkIDs', and will be entered into 'networkObjects' once the class UUID, constructor, and arguments are received from the server
-- maybe func can be an enum which is generated from the networkFunctions table, so programmers can type a function name but that corresponds to the actual index ID when sent
Network.SendRPC = function(reliable, networkID, func, ...)
	API_SendRPC(reliable, networkID, func, ...)
end
Network.RecieveRPC = function(networkId, funcID, ...)
	networkObjects[networkId].networkFunctions[funcID](...)
end

CreateClass("NetworkProfile") -- maybe network functions can be registered directly in 'Network' singleton, and networkID can simply be a property on the object? thus removing the need for a component. maybe even network ID can live in 'Network' via a map that maps object key to networkID. would mean objects themselves are less polluted with network details
NetworkProfile.networkID = 0
NetworkProfile.networkFunctions = {}
NetworkProfile.RPC = function()

end
NetworkProfile.OnRecieveRPC = function()

end



ffi.cdef[[
	typedef struct {
		float x;
		float y;
	} Vector2;
	typedef struct {
		float x;
		float y;
		float z;
	} Vector3;
]]

Vector2 = ffi.typeof("Vector2") -- gets the 'ctype' of a given cdef
Vector3 = ffi.typeof("Vector3")

CreateClass("Table")
-- TODO: define an __add function that just combines the entries of both tables and returns the combined table

CreateClass("WeakKeysTable", Table)
getmetatable(WeakKeysTable).__mode = "k"

CreateClass("WeakValuesTable", Table)
getmetatable(WeakValuesTable).__mode = "v"

CreateClass("List")
List.first = 0
List.last = -1
List.length = 0
List.Push = function(self, value)
	self.last = self.last + 1
	self[self.last] = value
	self.length = self.length + 1
end
-- in the future we can combine pop into one function that takes an index and does whatever it needs to shift the other elements as needed
List.PopLeft = function(self)
	local value = self[self.first]
	self[self.first] = nil -- null the value to allow garbage collection
	self.first = self.first + 1
	self.length = self.length - 1
	return value
end



CreateClass("EnumValue")
EnumValue.name = "UnnamedEnum"
EnumValue.value = nil
EnumValue.Init = function(self, args)
	self.name = args[1] -- first arg should be enum name
	getmetatable(self).__tostring = function(self) return self.name end
end
CreateClass("Enum")
Enum.Init = function(self, args)
	--setmetatable(enum, {__tostring = function() return self.name end})
  for _,v in pairs(args) do
		-- values need to be sets because comparing them is quicker than comparing strings (just checks if they point to the same object) and we don't have to manually calculate/re-calculate unique values each time it gets set or changed. those tables can also be used to store custom information for each enumeration
    self[v] = EnumValue{v}
  end
end
Enum.Add = function(enum, name, customValue)
	customValue = customValue or 0
	enum[name] = {}
end

-- ============ DELEGATE STUFF AND API TICK EVENT STUFF ==============================
CreateClass("EventListener")
EventListener.Trigger = function(eventListeners, ...)
	for i,v in pairs(eventListeners) do
		v(i, ...)
	end
end
EventListener.Init = function(self, listener, callback) -- THIS ISN'T NECESSARY, THE WEAKKEYSTABLE IS ALREADY A TABLE OF LISTENERS (KEYS) AND CALLBACK FUNCS (VALUES)
	self.listener = listener
	self.callback = callback
end

CreateClass("DelegateTable")
DelegateTable.delegates = {}--setmetatable({}, {__mode = "k"})
DelegateTable.Subscribe = function(self, caller, callbackFunc)
	self.delegates[caller] = callbackFunc
end
DelegateTable.Unsubscribe = function(self, caller)
	self.delegates[caller] = nil
end
DelegateTable.Fire = function(self, args)
	for i,v in pairs(self.delegates) do
		v(i, args)
	end
end

API.TickDelegates = DelegateTable()
API.Tick = function(deltaTime)
	-- fire tick events here, like ticking animation
	API.TickDelegates:Fire(deltaTime)
end

API.OnFileLoadedDelegates = DelegateTable() -- unused for now, basically just OnAssetLoaded type thing, doesn't NEED to be in API though, should be global
-- =====================================================================================



cacheCatalog = {}

-- UTexture2D* needs to be stored in a file object so that all the images that references it don't need duplicates and can refer to the same loaded object indexed by its uuid
-- im not sure this should properly be a 'File', what should this be????????
-- wait yeah a jpg is a system file and our 'File' is jpg, png, whatever (can be imported from anything) wrapper class that's loaded as a UTexture2D that can be used in any image object, plane object, material and can even be edited
-- the 'File' is our programs usable interpretation of whatever kind of file data
-- it shoud be able to contain any kind of arbitrary data in case of very custom file types
CreateClass("File") -- A FILE SHOULD NOT BE ITS OWN CLASS, SHOULD JUST BE AN OBJECT FOR EASIER REFERENCE TRACKING, BELOW PROPS SHOULD BE PART OF THE METATABLE
File.loaded = false -- UNUSED
File.OnLoadedDelegates = DelegateTable() -- UNUSED
-- 'PendingFileLoads' doubles as a list of files yet to be successfully loaded and as a way to store 'OnLoaded' callbacks. The callbacks should be stored here instead of the class objects or their metatables because it's not really 'metadata' and would just add clutter. It maps file object keys (weak) to a table of listeners which maps listener object keys (also weak) to an array-style table of callback functions to run when the file loads
File.PendingFileLoads = WeakKeysTable() -- STATIC VAR
File.RunWhenLoaded = function(file, eventListener) -- PROB NOT GOOD DESIGN, SHOULD USE SINGLE GETFILE FUNC W/ CALLBACK
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
File.OnFileLoaded = function(file, status) -- same nomenclature for callbacks, should probably rename, something that passes or fails loading, or retries it another way
	-- status is unused for now, but should indicate whether file load was successful, unsuccesful, reason for failure maybe as a code, etc.
	
	for listener,callbacks in pairs(File.PendingFileLoads[file]) do
		-- i is a listener
		-- v is array w/ callbacks
		for i=1, #callbacks do
			callbacks[i](listener, file)
		end
	end
	
	File.PendingFileLoads[file] = nil
end

-- Registered files (scripts, images, SFX, etc.), maps uuid string -> file object, which may or may not be pending load
files = WeakValuesTable() -- IN NEW CORE IM ADDING THIS TO FILE CLASS

LoadScript = function(file, bytes)
	func = loadstring(bytes)
	func()
end
LoadPng = function(file, bytes)
	file.cPtr = API_CreateImageFromBytes(bytes, #bytes)
	File.OnFileLoaded(file, "success")
end


-- loads file by looking in the system cache, or if not found there, requesting it from some authority
GetFile = function(uuid, eventListener)--OnLoadedCallback) -- MAKE THE PARAM A DELEGATE OBJECTTTTTT (PAIR OF CALLER AND CALLBACK) ?????
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

	-- ATTEMPT TO LOAD VIA VARIOUS methods

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
		-- this should be for net requests
	end
	-- File.RunWhenLoaded(file, EventListener(file, OnReceivedCallback)) idk wtf im doing im tired figure this out tomorrow
	
	
	
	return file
end

GetFiles = function(files, OnLoadedCallback)
	local CheckLoads = function(successfullyLoaded, file)
		--remove loaded file from files
		--check if the list is empty, if so run OnLoadedCallback
	end
	for i,_ in files do
		GetFile(i, CheckLoads)
	end
end

-- FOR TESTINGGGGGGGGGG BINDED TO V KEY IN UE
DisplayFilesLoaded = function()
	API_PrintString("=========================================================================================================================")
	for i,v in pairs(files) do
		API_PrintString("File ID: " .. i)
	end
	API_PrintString("=========================================================================================================================")
end



CreateClass("ObjectBase") -- rename to 'WorldObjectBase'?
ObjectBase.components = {}
ObjectBase.children = {}

CreateClass("Object2D", {ObjectBase})
Object2D.position = Vector2()
Object2D.rotation = 0
Object2D.size = Vector2()
Object2D.size.x = 100
Object2D.size.y = 100
Object2D.anchorPoint = Vector2()
Object2D.opacity = 1.0
Object2D.OnClicked = function(self)
	API_PrintString("LOLOLOLOLOLLLLLLLLLLLLLLLLLLLLLLLL")
end

World2D = Object2D()

CreateClass("Object3D", {ObjectBase})
Object3D.position = Vector3()
Object3D.rotation = Vector3()
Object3D.size = Vector3()
Object3D.size.x = 100
Object3D.size.y = 100
Object3D.size.z = 100

CreateClass("Mesh", {Object3D})
Mesh.id = ""
Mesh.cPtr = nil
Mesh.Init = function(self, args)
	self.id = args["id"] or ""
	-- self.cPtr = API_Object3D_Create(self) -- TODO IMPLEMENT THIS FUNC
end

-- we need Object2D constructor to hook up to C++ Object2D, but how do we override or extend the base constructor elegantly?
-- find a good solution for calling super methods. consider the distinction between class definitions and baked class objects, as well as the problems posed by multiple inheritance

function filesize (fd)
   local current = fd:seek()
   local size = fd:seek("end")
   fd:seek("set", current)
   return size
end

ReadFile = function(path)
	local file = assert(io.open(path, "rb"))
	if not file then
		return nil
	end
	--local content = file:read(filesize(file))
	local content = file:read("*a")
	file:close()
	return content
end

-- LOAD JSON HERE
local json = assert(loadstring(ReadFile(CACHE_PATH .. "/json.lua")))()


CreateClass("Image", {Object2D})
--Class("Image")
Image.cPtr = nil -- pointer to image Object2D
Image.id = "69696969AFAOSDFIJA" -- TODO:: PASS THIS TO API_Object2D_Create SO IT KNOWS TO GET ITS IMAGE ASSET
-- id: the image's uuid
Image.NEWINIT_RENAMELATER = function(self, properties)
	-- SET UP BINDINGS AND CALLBACKS FOR C++ Object2D
	-- call 'CreateObject2D' func registered from c++, receive its generated objectID, which returns a c ptr, store it as light user data
	-- another global func which takes void* or Object2D* and whatever value its gotta replace
	-- need funcs in c++ Object2D for event callbacks (OnClick, OnHover, etc.)
	
	-- set this to be child of World2D here for now, though we should actually have this in some base ctr for Object2D
	table.insert(World2D.children, self)
	
	properties.objectType = "Image"

	for key,value in pairs(properties) do -- should
		self[key] = value
	end
	
	-- API_Object2D_Create takes (reference to THIS instance for registry reference, object type, and properties table)
	-- the object type should be its own parameter and not included with properties to prevent unnecesary bloat, since 'type' is already the class of this object,
	-- though maybe in the future we can have independent API functions to create each primitive if we feel that's better, but that feels unnecessary too
	-- !!! ALSO CONSIDER USING OUR OWN REGISTRY SYSTEM TO PREVENT LUA REGISTRY FROM KEEP REFERENCES ALIVE SINCE ITS NOT A WEAK TABLE I DON'T THINK !!!
	--self.cPtr = API_Object2D_Create(self, "Image", properties) -- should we pass in 'properties' or set properties to instance first, then it can use instance?
	self.cPtr = API_Object2D_CreateImage(self) -- maybe we can shave off the type parameter too by having engine read class? nah extra unneeded work right
	
	-- image file is one cptr, slate object2d is another cptr
	
	-- NEW IMPLEMENTATION
	self.imageFile = imageFile
	
	-- we may need to do additional checks if an 'imageFile' can exist separate from our current file system
	File.RunWhenLoaded(imageFile, EventListener(self, Image.LoadImageFromFile))
	
	
	
end
Image.Init = function(self, imageFile)
	-- SET UP BINDINGS AND CALLBACKS FOR C++ Object2D
	-- call 'CreateObject2D' func registered from c++, receive its generated objectID, which returns a c ptr, store it as light user data
	-- another global func which takes void* or Object2D* and whatever value its gotta replace
	-- need funcs in c++ Object2D for event callbacks (OnClick, OnHover, etc.)
	
	-- set this to be child of World2D here for now, though we should actually have this in some base ctr for Object2D
	table.insert(World2D.children, self)
	
	self.cPtr = API_Object2D_Create(self) -- TODO: set its image's uuid
	--self.id = args[1]
	self.SetPosition(self, 100, 100)
	self.SetSize(self, 100, 100)
	-- image file is one cptr, slate object2d is another cptr
	
	-- NEW IMPLEMENTATION
	self.imageFile = imageFile
	
	-- we may need to do additional checks if an 'imageFile' can exist separate from our current file system
	File.RunWhenLoaded(imageFile, EventListener(self, Image.LoadImageFromFile))
	
	
	
end
Image.LoadImageFromFile = function(self, file)
	API_Image_SetImage(self.cPtr, file.cPtr)
end
Image.x__SETTER = function(self, newValue) --should this live in metatable or out here? maybe yes to avoid polluting the class property table? or maybe it SHOULD live there?
	--self.position.x = x IS 'POSITION' NEEDED? IT'S MAYBE USEFUL FOR 3D TRANSFORMS BUT NOT FOR 2D TRANSFORMS
	self.x = newValue
	API_Object2D_SetX(self.cPtr, newValue)
end
Image.width__SETTER = function(self, newValue)
	-- can we implement this without conditional jumps?
	local newValueType = type(newValue)
	if newValueType == "string" then
		-- parse new suffix or detect keyword like "auto"
	elseif newValueType == "number" then
		-- "
	end
end
Image.SetPositionX = function(self, x)
	self.position.x = x
	API_Object2D_SetPosition(self.cPtr, x, self.position.y)
end
Image.SetPositionY = function(self, y)
	self.position.y = y
	API_Object2D_SetPosition(self.cPtr, self.position.x, y)
end
Image.SetPosition = function(self, x, y)
	self.position.x = x
	self.position.y = y
	API_Object2D_SetPosition(self.cPtr, x, y)
end
Image.SetSize = function(self, width, length)
	self.size.x = width
	self.size.y = length
	API_Object2D_SetSize(self.cPtr, width, length)
	--API_PrintString(self.id)
	for i,v in ipairs(World2D.children) do
	--if v == self then
		--API_PrintString("YEP IM IN HERE")
		--API_PrintString(tostring(v.size.x))
		--end
	end
end
Image.SetOpacity = function(self, opacity)
	self.opacity = opacity
	API_Object2D_SetOpacity(self.cPtr, opacity)
end

CreateClass("Object3D", {ObjectBase})
Object3D.position = ffi.new("Vector3")
Object3D.rotation = ffi.new("Vector3")
Object3D.scale = ffi.new("Vector3")




CreateClass("AnimationNode")
-- statics
AnimationNode.TYPES = Enum{"Transform", "Event", "Animation", "Jump"}
-- instance data
AnimationNode.type = nil
AnimationNode.value = nil
AnimationNode.low = 0
AnimationNode.high = 0
-- max 'high' value that in whatever subtree this node is the root of, used for quicker searching for getting 'NodesInRange'
AnimationNode.max = 0
AnimationNode.left = nil
AnimationNode.right = nil
AnimationNode.next = nil -- for interpolating between frames on the same track
AnimationNode.last = nil
AnimationNode.Init = function(self, args)
	self.type = args[1]
	self.value = args[2]
	self.low = args[3]
	self.high = args[4]
	if self.type == AnimationNode.TYPES.Transform then
		self.propertyPath = args[5]
	end
	
end

CreateClass("Animation")
Animation.name = ""
Animation.root = nil
Animation.properties = {}
Animation._GetTreeHeight = function(root)
	if root == nil then
		return 0
	end
	
	return 1 + math.max(Animation._GetTreeHeight(root.left), Animation._GetTreeHeight(root.right))
end
Animation._LeftRotate = function(root)

	local oldRight = root.right
	root.right = oldRight.left
	oldRight.left = root
	oldRight.max = root.max
	if root.left ~= nil and root.right ~= nil then
		root.max = math.max(root.high, root.left.max, root.right.max)
	elseif root.left ~= nil then
		root.max = math.max(root.high, root.left.max)
	elseif root.right ~= nil then
		root.max = math.max(root.high, root.right.max)
	else
		root.max = root.high
	end
	return oldRight
	
end
Animation._RightRotate = function(root)

	local oldLeft = root.left
	root.left = oldLeft.right
	oldLeft.right = root
	-- root.max is at least as big as oldLeft.max, so since oldLeft is the new overall root, set its max equal to root.max in the case that root.max was bigger (would be if its right hand branch had a higher max value), and since root is now a smaller branch, recalculate its max by comparing its children
	oldLeft.max = root.max
	if root.left ~= nil and root.right ~= nil then
		root.max = math.max(root.high, root.left.max, root.right.max)
	elseif root.left ~= nil then
		root.max = math.max(root.high, root.left.max)
	elseif root.right ~= nil then
		root.max = math.max(root.high, root.right.max)
	else
		root.max = root.high
	end
	return oldLeft
	
end
Animation.Insert = function(self, newNode)

	self.root = Animation._Insert(self.root, newNode)
	
	-- also do whatever's needed to insert it on its specific track linked list
	--if self.properties[ -- HOW THE FUCK DO WE IDENTIFY AN ANIMATED PROPERTY 
	-- a propery is:
	-- a single value, like a float (complex values are just compounded single VALUES
	-- a path, something like self.componentShit.target
	-- if NIL then this new node is the first of its property kind, so add a reference to its head
	if newNode.type == AnimationNode.TYPES.Transform then
		local curNode = self.properties[newNode.propertyPath]
		if curNode == nil then
			self.properties[newNode.propertyPath] = newNode
		else
			-- search through the chain until we find the location of the new node
			if newNode.low < curNode.low then
				curNode.last = newNode
				newNode.next = curNode
				self.properties[newNode.propertyPath] = newNode
			else
				-- check if we ever have to stick this node behind another node
				while curNode.next ~= nil do
					if newNode.low < curNode.next.low then
						curNode.next.last = newNode
						break
					end
					curNode = curNode.next
				end
				-- at this point we either found the node to stick newNode after and broke out the loop, or we reached the very last node of the chain
				curNode.next = newNode
			end
		end
	end
end
Animation._Insert = function(root, newNode)

	if root == nil then
		return newNode
	end
	
	if root.max < newNode.max then
		root.max = newNode.max
	end
	
	if root.low <= newNode.low then
		root.right = Animation._Insert(root.right, newNode)
	else
		root.left = Animation._Insert(root.left, newNode)
	end
	
	
	
	local balance = Animation._GetTreeHeight(root.right) - Animation._GetTreeHeight(root.left)
	if balance > 1 then
		balance = Animation._GetTreeHeight(root.right.right) - Animation._GetTreeHeight(root.right.left)
		if balance > 0 then
			return Animation._LeftRotate(root)
		else
			root.right = Animation._RightRotate(root.right)
			return Animation._LeftRotate(root)
		end
	elseif balance < -1 then
		balance = Animation._GetTreeHeight(root.left.right) - Animation._GetTreeHeight(root.left.left)
		if balance > 0 then
			root.right = Animation._LeftRotate(root.left)
			return Animation._RightRotate(root)
		else
			return Animation._RightRotate(root)
		end
	end
	
	-- just return root if no balances were needed
	return root
	
end
Animation.GetNodesInRange = function(self, low, high)

	local nodes = {}
	
	if self.root ~= nil then
		Animation._GetNodesInRange(self.root, low, high, nodes)
	end
	
	return nodes
	
end
Animation._GetNodesInRange = function(root, low, high, outList)
	
	if root.left ~= nil and root.left.max >= low then
		Animation._GetNodesInRange(root.left, low, high, outList)
	end

	if not (root.low > high or root.high < low) then
		table.insert(outList, root)
	end
	
	if root.right ~= nil and root.low < high then
		Animation._GetNodesInRange(root.right, low, high, outList)
	end
	
end
Animation.PrintInOrder = function(self)

	Animation._PrintInOrder(self.root)

end
Animation._PrintInOrder = function(root)

	if root == nil then
		API_PrintString("Error: root is nil in 'Animation.PrintInOrder', THIS SHOULD NEVER HAPPEN")
		return
	end
	
	if root.left ~= nil then
		Animation._PrintInOrder(root.left)
	end
		
	API_PrintString("Node( low: " .. root.low .. " high: " .. root.high .. " )")
		
	if root.right ~= nil then
		Animation._PrintInOrder(root.right)
	end
	
end



CreateClass("State")
State.name = "Unnamed State"
State.length = 1.5 -- keep length as an overall animation state length because people might want to leave some empty space at the end of the sequence to simply help visualize the animation better.
State.timeScale = 1.0
State.fps = 24 -- move to Animation?
State.animation = Animation() -- interval tree implementation for storing animation nodes for efficient lookup
State.Init = function(self, args)
	-- TODO: insert all nodes from list into a living interval tree
	for _,v in pairs(args) do
		self.animation:Insert(AnimationNode(v))
	end
end


CreateClass("StateMachine")
StateMachine.parent = nil -- the base object for this component
StateMachine.currentState = nil
StateMachine.animationTime = 0.0
StateMachine.lastFrameTimestamp = 0.0
StateMachine.stateBeginTimestamp = 0.0
StateMachine.timeScale = 1.0
StateMachine.allMachines = {} -- TODO: give it a static modifier
StateMachine.Init = function(self, args)
	-- subscribe to tick event here for processing animation frames
	table.insert(StateMachine.allMachines, self)
	
	self.currentState = args[1] -- PASS IN A BUILT STATE FOR FIRST AND ONLY ARGS PARAM
	self.stateBeginTimestamp = os.clock()
	self.lastFrameTimestamp = os.clock()
end
-- subscribe a func to tick that scrolls through all of StateMachine.allMachines and runs anims on them
API.TickDelegates:Subscribe(StateMachine, function(self, deltaTime)
	local currentFrameTimestamp = os.clock()
	for _,sm in pairs(StateMachine.allMachines) do
		-- FIGURE OUT WHERE THESE TRANSFORMATIONS SHOULD ACTUALLY BE HAPPENING
		--local nodes = sm.currentState.animation:GetNodesInRange(sm.lastFrameTimestamp - sm.stateBeginTimestamp, currentFrameTimestamp - sm.stateBeginTimestamp)
		local nodes = sm.currentState.animation:GetNodesInRange(sm.animationTime, sm.animationTime + deltaTime)
		for i,v in ipairs(nodes) do
		  -- TODO==== STORE NODES AS A SET FOR O(1) SEARCHING
			if v.type == AnimationNode.TYPES.Transform then--and nodes[v.next] == nil then
				local target = sm
				local lastTarget = nil
				for str in string.gmatch(v.propertyPath, "([^.]+)") do
					lastTarget = target
					target = target[str]
				end
				
				if v.next ~= nil then
					--target(lastTarget, Lerp(v.value, v.next.value, (currentFrameTimestamp - sm.stateBeginTimestamp - v.low) / (v.next.low - v.low)))
					target(lastTarget, Lerp(v.value, v.next.value, (sm.animationTime + deltaTime - v.low) / (v.next.low - v.low)))
				else
					target(lastTarget, v.value)
				end
			elseif v.type == AnimationNode.TYPES.Jump then
				sm.animationTime = v.value
			end
		end
		sm.animationTime = sm.animationTime + deltaTime
		sm.lastFrameTimestamp = currentFrameTimestamp
	end
end)




-- base program class???
CreateClass("Program", {Object})

-- this should be called whenever the UI system is ready to load UI (when HUDManager loads for example)
function InitializeObject2Ds() -- WHERE IS THIS SUPPOSED TO LIVE IN THE NEW CORE?
	local list = List()
	
	for i,v in pairs(World2D.children) do
			--API_PrintString(v.id)
		list:Push(v)
	end
	
	while list.length > 0 do
		local obj = list:PopLeft()
		obj.cPtr = API_Object2D_Create(obj)
		API_Object2D_SetPosition(obj.cPtr, obj.position.x, obj.position.y)
		API_Object2D_SetSize(obj.cPtr, obj.size.x, obj.size.y)
		API_Object2D_SetOpacity(obj.cPtr, obj.opacity)
		-- in this case we don't want to make a delegate in the 'GetFile' call to set the image because the original 'Image.Init' function would have already set a delegate to set its own image, so we wouldn't need to do it again here. Rather we must simply check if its already been loaded since that means even the 'Image.Init' delegate is fully completed, so we NEED to set the image from here.
		local file = GetFile(obj.id)
		if file.loaded then
			API_Image_SetImage(obj.cPtr, file.cPtr)
		end
		
		for i,v in pairs(obj.children) do
			list:Push(v)
		end
	end
end


--ApplicationEditorClass = GetFile("3DApplicationEditor.lua")--, function()
--	curApp = ApplicationEditorClass()
--end)






return 0 -- THIS MUST BE LAST LINE

