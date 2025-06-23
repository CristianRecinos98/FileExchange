-- k this could be like our image class?


local Image = File.GetFile("LONGASS UUID") -- how do we reference ourself, or another function within ourself?
-- HOLD UP A CLASS SHOULD NOT 'DEPEND' ON ITSELF AND HOLD A REFERENCE TO ITSELF, THAT MEANS A HARD REFERENCE CONTAINS A HARD REFERENCE TO ITSELF, THEREFORE IT NEVER GETS GARBAGE COLLECTED, THAT WOULD BE A NIGHTMARE. SO THEN HOW DO WE ACCESS CLASS FUNCS? UNLESS WE LITERALLY
-- WAIT WHAT IF A CLASS REFERENCE ITSELF? WAIT FILES ARE STORED IN WEAK TABLES ITS FINE
-- OKAY SO A CLASS LOADER FUNC COULD DO A BUNCH OF LOCAL VARS FOR ITS OWN METHODS. THAT WOULD ACTUALLY CREATE INLINE REFERENCES TO THEM WHICH WOULD BE SUPER DUPER QUICK SO YEAH LETS DO THAT.
-- GetFiles(List("all dem dependencies go hereeeeee"), function()
-- 
-- end)

LoadImageFromFile = function(instance, imageFile)
	-- references Object2D in engine and tells it what texture2D object also in engine to display
	API_Image_SetImage(instance.cPtr, imageFile.cPtr)
end
--DIVIDER

	-- how does this object get added to the world?
	-- world.menu.namebar

-- 'name' and 'parent' properties are stored within the object for debugging purposes or for "removing" an Object2D from the screen (we do parent[name] = nil, and in all contained object2Ds we set its parent property to nil SHEESH wait what if other variables are Object2Ds, isn't the parent property an object2D as well? snap i think we need a designed array for children Object2Ds)
world["menu"] = Image("menu", world, 100, 100, 50, 50, 0, File.GetFile("This image's UUID lul"))
-- but how does the editor display these objects?
-- a program init with spawn these tings

-- sample 2D object editor
-- we gotta make the play/pause button
world = Object2D()
table.insert(world.children["menu"], Image(blahhhhh))



-- User's won't normally be writing this code. Some kind of 2D application editor interface will let users place objects visually and set constructor parameters, but the editior will internally convert it to its corresponding lua-script code.
init = function(instance, name, parent, positionX, positionY, sizeX, sizeY, rotation, imageFile)
	-- idk, should be a weak table to all children for delayed HUD instantation on UE i think ?????
	table.insert(World2D.children, instance)

	
	instance.cPtr = API_Object2D_Create(instance)
	instance.SetPosition(instance, 100, 100)
	Image.SetSize(instance, 100, 100)
	-- Image.SetSize
	-- hard reference i think? THIS image object references THAT image file (png, jpg, whataver...)
	instance.imageFile = imageFile
	
	File.RunWhenLoaded(imageFile, EventListener(instance, LoadImageFromFile))
end
--DIVIDER
myfuncie = function(str)
	-- k function comments should go inside the bitches now
	return "fuck it up " .. str
end
--DIVIDER
_myvar = 5
--DIVIDER
muhstring = "yessy"
--DIVIDER
fuck = "shit"
--DIVIDER
yuh = true
--DIVIDER
-- WE COULD USE PRIVATE BEHVIOR TO MARK FUNCTIONS IN DATA, FOR HOW THEY ARE TRANSMITTED. CERTAIN FUNCTIONS MAY REQUIRE A SPECIAL PERMISSION TO CHECK TO BE TRANSMITTED. THE FUNCTION IS STILL DEFINED WITH THE CLASS, AVOIDS THE HASSLE OF CREATING A SEPARATE CLASS AND OBJECT, AND IT JUST HAS WHATEVER LABEL TO INCIDATE WHATEVER RULES FOR HOW IT GETS TRANSMITTED IN THE NETWORK SYSTEM, SO IT CAN BE LIKE A UNIVERSAL VARIABLE 'TRAIT' KEY, SOMETHING THAT ANYBODY COULD TECHNICALLY USE, ANYTHING COULD ATTACH ANY ARBITRARY 'TRAIT' OR 'ATTRIBUTE' TO A VARIABLE, AND THAT ATTRIBUTE MAY BE UTILIZED BY WHATEVER USER PROGRAM MAY. IDEALLY THESE SHOULD BE MADE SOMEHOW SO THEY WOULD NOT COLLIDE WITH OTHER PROGRAMS WHO HAVE CHOSEN THE SAME NAME, SUCH AS ATTACHING A RANDOMLY GENERATED UUID TO IT!