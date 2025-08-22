function tprint (tbl, indent)
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2 
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "   
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end

--ApplicationEditorClass = nil
--File.PendingFileLoads = nil
--collectgarbage()
--DisplayFilesLoaded()

--Network.SendRPC(true, 69000, 5, "yuhhhh", true, 42, false)

--API_PrintString(tostring(Image.LoadImageFromFile == nil))

Image(GetFile("02X561A743D35260BF97698F1G3AB3AE01J9MEE0.png"))

-- BELOW IS 'EDITOR INTERFACE CLASS' -inherits from 'VerticalGroup'?
-- this will have the utility tab bar, the file tab bar, and space for whatever file editor for most of the screen

tabBar = LayeredGroup({width: "100%", height: "30px"})
tabBar.BackgroundImage = Image({width: "100%", height: "100%", imageFile: "UUID goes here?"})
tabBar.HG = HorizontalGroup({width: "100%", height: "100%", spacing: "left-align"})

-- maybe also write how this is tokened in the save file. soooo will it be stored/read differently than normal class files?
-- wait this IS the save file isn't it?
tab = LayeredGroup({stretchWeight: "1", min-width: "20px", max-width: "100px", height:"100%"})
tab.BackgroundImage = Image({width: "100%", height: "100%", imageFile: "UUID goes here?"})
tab.HG = HorizontalGroup({width: "100%", height: "100%", spacing: "custom"})
tab.HG[0] = Image({width: "100px", height: "auto"}) -- ICON
tab.HG[1] = Text({width: "auto", height: "auto", text: ""})

tab.XButton = Image({width: "100%", height: "100%", opacity: "0", imageFile: "UUID goes here?"})


