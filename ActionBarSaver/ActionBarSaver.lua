--[[ 
	Action Bar Saver, Shadowed
	Modified: Export/Import feature added + key normalization on import
	          + fixes for 3.3.5a (ScrollingEdit, RestoreAction, RestoreProfile)
	          + fix for shadowed 'type' variable
	          + safe GetMinMaxValues, slotNum in RestoreAction
	          + removed OnCursorChanged (GetValue returns nil in 3.3.5a)
	          + actionID normalized to number
	          + byte-by-byte splitByPipe (skips all 124 bytes)
	          + flexible companion format
	          + nil-safe spellRank and spellName
	          + spellID-to-name resolution via GetSpellInfo (priority)
	          + macro name from binding
	          + companion: find index by spellID
]]
ActionBarSaver = select(2, ...)

local ABS = ActionBarSaver
local L = ABS.locals

local restoreErrors, spellCache, macroCache, macroNameCache, highestRanks = {}, {}, {}, {}, {}
local iconCache, playerClass

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132


--[[ 
	Разбор строки по "|". В клиенте 3.3.5a символ "|" кодируется
	ДВУМЯ байтами (124, 124). Эта функция пропускает ВСЕ байты 124
	подряд после каждого разделителя.
]]
local function splitByPipe(str)
	local result = {}
	local current = ""
	local i = 1
	while i <= #str do
		local b = string.byte(str, i)
		if b == 124 then
			table.insert(result, current)
			current = ""
			while string.byte(str, i) == 124 do
				i = i + 1
			end
		else
			current = current .. string.char(b)
			i = i + 1
		end
	end
	table.insert(result, current)
	return unpack(result)
end


function ABS:OnInitialize()
	local defaults = {
		macro = false,
		checkCount = false,
		restoreRank = true,
		spellSubs = {},
		sets = {}
	}
	
	ActionBarSaverDB = ActionBarSaverDB or {}
		
	for key, value in pairs(defaults) do
		if( ActionBarSaverDB[key] == nil ) then
			ActionBarSaverDB[key] = value
		end
	end
	
	for classToken in pairs(RAID_CLASS_COLORS) do
		ActionBarSaverDB.sets[classToken] = ActionBarSaverDB.sets[classToken] or {}
	end
	
	self.db = ActionBarSaverDB
	
	playerClass = select(2, UnitClass("player"))
end

function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")
	
	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")
	
	return string.trim(text)
end

function ABS:SaveProfile(name)
	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
	
	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		
		local actionType, id, subType, extraID = GetActionInfo(actionID)
		if( actionType and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			if( actionType == "companion" ) then
				set[actionID] = string.format("%s|%s|%s|%s|%s|%s", actionType, id, "", "", subType, extraID)
			elseif( actionType == "equipmentset" ) then
				set[actionID] = string.format("%s|%s|%s", actionType, id, "")
			elseif( actionType == "item" ) then
				set[actionID] = string.format("%s|%d|%s|%s", actionType, id, "", (GetItemInfo(id)) or "")
			elseif( actionType == "spell" and id > 0 ) then
				local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
				if( spell ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", actionType, id, "", spell, rank or "", extraID or "")
				end
			elseif( actionType == "macro" ) then
				local name, icon, macro = GetMacroInfo(id)
				if( name and icon and macro ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", actionType, actionID, "", self:CompressText(name), icon, self:CompressText(macro))
				end
			end
		end
	end
	
	self:Print(string.format(L["Saved profile %s!"], name))
end

function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end
		
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	if( macroNameCache[name] ) then
		return macroNameCache[name]
	end
	
	return nil
end

function ABS:RestoreMacros(set)
	local perCharacter = true
	for slotID, data in pairs(set) do
		local actionType, id, binding, macroName, macroIcon, macroData = splitByPipe(data)
		if( actionType == "macro" ) then
			local macroID = self:FindMacro(id, macroName, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
					break
				elseif( charNum == MAX_CHAR_MACROS ) then
					perCharacter = false
				end

				if( not iconCache ) then
					iconCache = {}
					for i=1, GetNumMacroIcons() do
						iconCache[(GetMacroIconInfo(i))] = i
					end
				end
				
				macroName = self:UncompressText(macroName)
				
				CreateMacro(macroName == "" and " " or macroName, iconCache[macroIcon] or 1, self:UncompressText(macroData), nil, perCharacter)
			end
		end
	end
	
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
end

function ABS:RestoreProfile(name, overrideClass)
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return
	elseif( InCombatLockdown() ) then
		self:Print(String.format(L["Unable to restore profile \"%s\", you are in combat."], name))
		return
	end
	
	table.wipe(macroCache)
	table.wipe(spellCache)
	table.wipe(macroNameCache)
	
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)

		for i=1, numSpells do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			
			spellCache[spell] = index
			spellCache[string.lower(spell)] = index
			
			if( rank and rank ~= "" ) then
				spellCache[spell .. rank] = index
			end
		end
	end
		
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end
	
	ClearCursor()
	
	local soundToggle = GetCVar("Sound_EnableAllSound")
	SetCVar("Sound_EnableAllSound", 0)

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local actionType, id = GetActionInfo(i)
		
			if( id or actionType ) then
				PickupAction(i)
				ClearCursor()
			end
		
			if( set[i] and type(set[i]) == "string" ) then
				local firstField = string.match(set[i], "^([^|]+)");
				if( firstField and (firstField == "spell" or firstField == "item" or firstField == "macro" or firstField == "companion" or firstField == "equipmentset") ) then
					local parts = { splitByPipe(set[i]) };
					self:RestoreAction(i, unpack(parts))
				end
			end
		end
	end
	
	SetCVar("Sound_EnableAllSound", soundToggle)
	
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end

function ABS:RestoreAction(i, actionType, actionID, binding, ...)
	local slotNum = tonumber(i) or 0;

	if( actionType == "spell" ) then
		local spellName, spellRank = ...
		if not spellName then spellName = "" end
		if not spellRank then spellRank = "" end
		
		-- Сначала пробуем через spellID (последнее поле)
		local spellID = tonumber(spellRank)
		if not spellID then
			spellID = tonumber(spellName)
		end
		
		if spellID then
			local name, rank = GetSpellInfo(spellID)
			if name then
				spellName = name
				spellRank = rank or ""
			end
		else
			-- Если ID нет — используем binding как имя
			if binding and binding ~= "" then
				local name, rank = string.match(binding, "^(.-)ank%s*(%d+)$")
				if name then
					spellName = name
					spellRank = "Rank "..rank
				else
					spellName = binding
					spellRank = ""
				end
			end
		end
		
		if not spellName then spellName = "" end
		if not spellRank then spellRank = "" end
		
		if( ( self.db.restoreRank or spellRank == "" ) and spellCache[spellName] ) then
			PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
		elseif( spellRank ~= "" and spellCache[spellName .. spellRank] ) then
			PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
		end
		
		if( GetCursorInfo() ~= actionType ) then
			local lowerSpell = string.lower(spellName)
			for spell, linked in pairs(self.db.spellSubs) do
				if( lowerSpell == spell and spellCache[linked] ) then
					self:RestoreAction(slotNum, actionType, actionID, binding, linked, nil, arg3)
					return
				elseif( lowerSpell == linked and spellCache[spell] ) then
					self:RestoreAction(slotNum, actionType, actionID, binding, spell, nil, arg3)
					return
				end
			end
			
			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], spellName, tonumber(slotNum) or 0))
			ClearCursor()
			return
		end

		PlaceAction(slotNum)
	elseif( actionType == "equipmentset" ) then
		local slotID = -1
		for j=1, GetNumEquipmentSets() do
			if( GetEquipmentSetInfo(j) == actionID ) then
				slotID = j
				break
			end
		end
		
		PickupEquipmentSet(slotID)
		if( GetCursorInfo() ~= "equipmentset" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore equipment set \"%s\" to slot #%d, it does not appear to exist anymore."], actionID, tonumber(slotNum) or 0))
			ClearCursor()
			return
		end
		
		PlaceAction(slotNum)
			
	elseif( actionType == "companion" ) then
		-- Формат: companion||MOUNT|48778
		-- binding = "MOUNT" (тип), ... = "48778" (spellID)
		local critterType, spellID
		if binding and binding ~= "" then
			critterType = binding
			spellID = ...
		else
			critterType, spellID = ...
		end
		
		if critterType and spellID then
			-- Ищем index маунта по spellID
			local foundIndex = nil
			local numCompanions = GetNumCompanions(critterType) or 0
			for i = 1, numCompanions do
				local _, _, companionSpellID = GetCompanionInfo(critterType, i)
				if companionSpellID and tostring(companionSpellID) == tostring(spellID) then
					foundIndex = i
					break
				end
			end
			
			if foundIndex then
				PickupCompanion(critterType, foundIndex)
			else
				table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], tostring(critterType), tonumber(slotNum) or 0))
				ClearCursor()
				return
			end
		else
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], tostring(critterType), tonumber(slotNum) or 0))
			ClearCursor()
			return
		end
		
		if( GetCursorInfo() ~= "companion" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], tostring(critterType), tonumber(slotNum) or 0))
			ClearCursor()
			return
		end
		
		PlaceAction(slotNum)
	elseif( actionType == "item" ) then
		PickupItem(actionID)

		if( GetCursorInfo() ~= actionType ) then
			local itemName = ...
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], itemName and itemName ~= "" and itemName or actionID, tonumber(slotNum) or 0))
			ClearCursor()
			return
		end
		
		PlaceAction(slotNum)
	elseif( actionType == "macro" ) then
		local name, _, content = ...
		local macroName = binding
		if not macroName or macroName == "" then
			macroName = name
		end
		if not content then content = "" end
		
		PickupMacro(self:FindMacro(actionID, macroName, content or -1))
		if( GetCursorInfo() ~= actionType ) then
			table.insert(restoreErrors, string.format(L["Unable to restore macro id #%s to slot #%d, it appears to have been deleted."], tostring(actionID), tonumber(slotNum) or 0))
			ClearCursor()
			return
		end
		
		PlaceAction(slotNum)
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

function ABS:SerializeProfile(profileName)
  local set = self.db.sets[playerClass][profileName];
  if not set then
    return nil;
  end

  local function serialize(tbl)
    local str = "{"
    for k, v in pairs(tbl) do
      local key = type(k) == "number" and "["..k.."]" or "["..string.format("%q", k).."]"
      local value
      if type(v) == "table" then
        value = serialize(v)
      elseif type(v) == "string" then
        value = string.format("%q", v)
      elseif type(v) == "number" or type(v) == "boolean" then
        value = tostring(v)
      else
        value = "nil"
      end
      str = str..key.."="..value..","
    end
    return str.."}"
  end

  return serialize(set);
end

function ABS:DeserializeProfile(str)
  local func, err = loadstring("return "..str)
  if not func then
    return nil, err;
  end
  local success, data = pcall(func)
  if not success then
    return nil, data;
  end
  return data;
end

function ABS:DoExport(profileName)
  if not profileName or profileName == "" then
    self:Print(L["Usage: /abs export <profile>"]);
    return;
  end

  local data = self:SerializeProfile(profileName);
  if not data then
    self:Print(string.format(L["No profile with the name \"%s\" exists."], profileName));
    return;
  end

  ABS:ShowExportWindow(profileName, data);
end

function ABS:DoImport(profileName, data)
  if not profileName or profileName == "" then
    self:Print(L["Usage: /abs import <profile> [data]"]);
    return;
  end

  if not data or data == "" then
    self:Print(L["No data provided for import."]);
    return;
  end

  local set, err = self:DeserializeProfile(data);
  if not set then
    self:Print(L["Import failed: "]..tostring(err));
    return;
  end

  local function normalizeKeys(tbl)
    local result = {};
    for k, v in pairs(tbl) do
      local key = tonumber(k) or k;
      if type(v) == "table" then
        result[key] = normalizeKeys(v);
      else
        result[key] = v;
      end
    end
    return result;
  end

  set = normalizeKeys(set);

  local backupKey = profileName.."_backup";
  if not self.db.sets[playerClass][backupKey] then
    self.db.sets[playerClass][backupKey] = self.db.sets[playerClass][profileName];
  end

  self.db.sets[playerClass][profileName] = set;

  self:Print(string.format(L["Profile \"%s\" imported successfully!"], profileName));
end

local ABSExportFrame = nil;

function ABS:CreateExportFrame()
  if ABSExportFrame then
    return ABSExportFrame;
  end

  local frame = CreateFrame("Frame", "ABSExportFrame", UIParent);
  frame:SetSize(600, 400);
  frame:SetPoint("CENTER");
  frame:SetFrameStrata("DIALOG");
  frame:SetMovable(true);
  frame:EnableMouse(true);
  frame:RegisterForDrag("LeftButton");
  frame:SetScript("OnDragStart", frame.StartMoving);
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  });
  frame:SetBackdropColor(0, 0, 0, 0.9);
  frame:Hide();

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal");
  title:SetPoint("TOP", frame, "TOP", 0, -16);
  title:SetText("Action Bar Saver - Export / Import");
  frame.title = title;

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4);

  local instr = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
  instr:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40);
  instr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -40);
  instr:SetJustifyH("LEFT");
  instr:SetText("Profile name: |cffffffff".."<none>".."|r\nCopy the text below (Ctrl+A, Ctrl+C) to export.\nPaste text and click 'Import' to import.");
  frame.instruction = instr;

  local scrollFrame = CreateFrame("ScrollFrame", "ABSExportScrollFrame", frame, "UIPanelScrollFrameTemplate");
  scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -90);
  scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 50);

  local editBox = CreateFrame("EditBox", "ABSExportEditBox", scrollFrame);
  editBox:SetMultiLine(true);
  editBox:SetAutoFocus(false);
  editBox:SetFontObject(ChatFontNormal);
  editBox:SetWidth(scrollFrame:GetWidth());
  editBox:SetHeight(scrollFrame:GetHeight());
  editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);
  editBox:SetScript("OnTextChanged", function(self)
    local scrollBar = _G[scrollFrame:GetName().."ScrollBar"];
    if scrollBar then
      local min, max = scrollBar:GetMinMaxValues();
      if max and max > 0 then
        if not self.max or self.max ~= max then
          self.max = max;
          scrollBar:SetValue(max);
        end
      end
    end
  end);
  editBox:SetScript("OnCursorChanged", function(self)
  end);
  scrollFrame:SetScrollChild(editBox);
  frame.editBox = editBox;

  local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
  importBtn:SetSize(100, 24);
  importBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16);
  importBtn:SetText(L["Import"]);
  importBtn:SetScript("OnClick", function()
    local profileName = frame.profileName;
    if not profileName or profileName == "" then
      ABS:Print(L["No profile name specified."]);
      return;
    end
    local text = frame.editBox:GetText();
    if text and text ~= "" then
      ABS:DoImport(profileName, text);
      frame:Hide();
    else
      ABS:Print(L["Nothing to import."]);
    end
  end);

  local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
  clearBtn:SetSize(100, 24);
  clearBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0);
  clearBtn:SetText(L["Clear"]);
  clearBtn:SetScript("OnClick", function()
    frame.editBox:SetText("");
  end);

  ABSExportFrame = frame;
  return frame;
end

function ABS:ShowExportWindow(profileName, data)
  local frame = self:CreateExportFrame();
  frame.profileName = profileName;
  frame.editBox:SetText(data);
  frame.editBox:HighlightText();
  frame.editBox:SetFocus();
  frame.title:SetText("ABS Export - "..profileName);
  frame.instruction:SetText("Profile name: |cffffffff"..profileName.."|r\nCopy the text below (Ctrl+A, Ctrl+C) to export.");
  frame:Show();
end

function ABS:ShowImportWindow(profileName)
  local frame = self:CreateExportFrame();
  frame.profileName = profileName;
  frame.editBox:SetText("");
  frame.title:SetText("ABS Import - "..(profileName or "<none>"));
  frame.instruction:SetText("Profile name: |cffffffff"..(profileName or "<none>").."|r\nPaste text and click 'Import' to import.");
  frame:Show();
  frame.editBox:SetFocus();
end

SLASH_ACTIONBARSAVER1 = nil
SlashCmdList["ACTIONBARSAVER"] = nil

SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = (arg or ""):match("^%s*(.-)%s*$")
	
	local self = ABS
	
	if( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)
	elseif( cmd == "link" and arg ~= "" ) then
		local first, second = string.match(arg, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")
		
		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end
		
		self.db.spellSubs[first] = second
		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
	elseif( cmd == "restore" and arg ~= "" ) then
		for i=#(restoreErrors), 1, -1 do table.remove(restoreErrors, i) end
		local profileName = string.lower(arg)
		if( not self.db.sets[playerClass][profileName] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], profileName))
			return
		end
		self:RestoreProfile(profileName, playerClass)
	elseif( cmd == "rename" and arg ~= "" ) then
		local old, new = string.split(" ", arg, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.sets[playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
			return
		elseif( not self.db.sets[playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		self.db.sets[playerClass][new] = CopyTable(self.db.sets[playerClass][old])
		self.db.sets[playerClass][old] = nil
		self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
	elseif( cmd == "errors" ) then
		if( #(restoreErrors) == 0 ) then
			self:Print(L["No errors found!"])
			return
		end
		self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
		for _, text in pairs(restoreErrors) do
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end
	elseif( cmd == "delete" ) then
		self.db.sets[playerClass][arg] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg))
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		for class, sets in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		table.sort(classes, function(a, b) return a < b end)
		for _, class in pairs(classes) do
			for i=#(setList), 1, -1 do table.remove(setList, i) end
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro
		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	elseif( cmd == "count" ) then
		self.db.checkCount = not self.db.checkCount
		if( self.db.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
	elseif( cmd == "rank" ) then
		self.db.restoreRank = not self.db.restoreRank
		if( self.db.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
	elseif( cmd == "export" ) then
		local profileName = arg;
		if profileName == "" then
			self:Print(L["Usage: /abs export <profile>"]);
			return;
		end
		self:DoExport(profileName);
	elseif( cmd == "import" ) then
		local profileName, data = string.split(" ", arg, 2);
		if not profileName or profileName == "" then
			self:Print(L["Usage: /abs import <profile> [data]"]);
			return;
		end
		if data and data ~= "" then
			self:DoImport(profileName, data);
		else
			self:ShowImportWindow(profileName);
		end
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs export <profile> - Exports the profile to a window for copying."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs import <profile> [data] - Imports a profile from data or opens a window."])
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( addon == "ActionBarSaver" ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)