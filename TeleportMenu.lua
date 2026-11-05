--[[
  TeleportMenu  -  WoW 1.12 (Lua 5.0)
  Minimap button -> menu of every teleport you can use RIGHT NOW.
  Hidden automatically: unlearned spells, other classes' spells, items not in your bags.

  Slash commands: /tpm help
]]

local ROW_W, ROW_H = 220, 20
local menu, btn
local rows = {}

---------------------------------------------------------------------------
-- DATA  (edit freely!  names must match the English client)
---------------------------------------------------------------------------
local GROUPS = {
  { key = "home",     title = "Hearth & Recall" },
  { key = "mageTele", title = "Mage Teleports" },
  { key = "magePort", title = "Mage Portals" },
  { key = "druid",    title = "Druid" },
  { key = "eng",      title = "Engineering" },
  { key = "rune",     title = "Teleport Runes" },
  { key = "custom",   title = "Custom" },
}

-- Spells: only shown if found in your spellbook
local SPELLS = {
  { g = "home",     n = "Astral Recall" },            -- Shaman
  { g = "druid",    n = "Teleport: Moonglade" },      -- Druid

  { g = "mageTele", n = "Teleport: Stormwind" },
  { g = "mageTele", n = "Teleport: Ironforge" },
  { g = "mageTele", n = "Teleport: Darnassus" },
  { g = "mageTele", n = "Teleport: Alah'Thalas" },
  { g = "mageTele", n = "Teleport: Theramore" },

  { g = "mageTele", n = "Teleport: Orgrimmar" },
  { g = "mageTele", n = "Teleport: Undercity" },
  { g = "mageTele", n = "Teleport: Thunder Bluff" },
  { g = "mageTele", n = "Teleport: Stonard" },

  { g = "magePort", n = "Portal: Stormwind" },
  { g = "magePort", n = "Portal: Ironforge" },
  { g = "magePort", n = "Portal: Darnassus" },
  { g = "magePort", n = "Portal: Alah'Thalas" },
  { g = "magePort", n = "Portal: Theramore" },

  { g = "magePort", n = "Portal: Orgrimmar" },
  { g = "magePort", n = "Portal: Undercity" },
  { g = "magePort", n = "Portal: Thunder Bluff" },
  { g = "magePort", n = "Portal: Stonard" },
}

-- Items: only shown if in your bags.
--   id  = exact item id
local ITEMS = {
  { g = "home", id = 6948 },  -- Hearthstone
  { g = "eng",  id = 18986 }, -- Ultrasafe Transporter: Gadgetzan
  { g = "eng",  id = 18984 }, -- Dimensional Ripper - Everlook
  { g = "rune", id = 61000 }, -- Time-Worn Rune
  { g = "rune", id = 41915 }, -- Verdant Rune
}

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TeleportMenu:|r " .. msg)
end

local function NameMatches(def, lname)
  if def.plain then
    return string.find(lname, def.plain, 1, true) ~= nil
  end
  return false
end

local function ScanSpellbook()
  local known = {}
  local i = 1
  while true do
    local name = GetSpellName(i, BOOKTYPE_SPELL)
    if not name then break end
    known[name] = i            -- last (highest rank) wins
    i = i + 1
  end
  return known
end

local function ScanBags()
  local items = {}
  for bag = 0, 4 do
    local n = GetContainerNumSlots(bag)
    if n then
      for slot = 1, n do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, idstr = string.find(link, "item:(%d+)")
          local _, _, name = string.find(link, "%[(.-)%]")
          local tex = GetContainerItemInfo(bag, slot)
          if idstr and name then
            table.insert(items, { id = tonumber(idstr), name = name, bag = bag, slot = slot, tex = tex })
          end
        end
      end
    end
  end
  return items
end

local function Add(res, g, e)
  if not res[g] then res[g] = {} end
  table.insert(res[g], e)
end

local function SortByName(a, b) return a.name < b.name end

local function BuildList()
  local res = {}
  local known = ScanSpellbook()
  local bags = ScanBags()
  local usedSpell, usedItem = {}, {}

  -- fixed spells
  for _, s in ipairs(SPELLS) do
    local idx = known[s.n]
    if idx then
      usedSpell[s.n] = true
      Add(res, s.g, { kind = "spell", name = s.n, index = idx, tex = GetSpellTexture(idx, BOOKTYPE_SPELL) })
    end
  end

  -- helper: add matching spells + items for a pattern definition
  local function AddByDef(def)
    if def.plain then
      for name, idx in pairs(known) do
        if not usedSpell[name] and NameMatches(def, string.lower(name)) then
          usedSpell[name] = true
          Add(res, def.g, { kind = "spell", name = name, index = idx, tex = GetSpellTexture(idx, BOOKTYPE_SPELL) })
        end
      end
    end
    for _, it in ipairs(bags) do
      local ok
      if def.id then ok = (it.id == def.id) else ok = NameMatches(def, string.lower(it.name)) end
      if ok and not usedItem[it.id] then
        usedItem[it.id] = true
        Add(res, def.g, { kind = "item", name = it.name, bag = it.bag, slot = it.slot, tex = it.tex })
        if def.id then break end
      end
    end
  end

  for _, d in ipairs(ITEMS) do AddByDef(d) end

  -- user-defined entries
  if TeleportMenuDB then
    for _, n in ipairs(TeleportMenuDB.spells) do
      AddByDef({ g = "custom", plain = string.lower(n) })
    end
    for _, n in ipairs(TeleportMenuDB.items) do
      AddByDef({ g = "custom", plain = string.lower(n) })
    end
  end

  if res.rune   then table.sort(res.rune, SortByName) end
  if res.custom then table.sort(res.custom, SortByName) end
  return res
end

local function Remaining(e)
  local s, d
  if e.kind == "spell" then
    s, d = GetSpellCooldown(e.index, BOOKTYPE_SPELL)
  else
    s, d = GetContainerItemCooldown(e.bag, e.slot)
  end
  if s and d and s > 0 and d > 1.5 then
    local rem = s + d - GetTime()
    if rem > 0 then return rem end
  end
  return nil
end

local function FormatTime(rem)
  local m = math.floor(rem / 60)
  local s = math.floor(rem - m * 60)
  if m > 0 then return string.format("%d:%02d", m, s) end
  return string.format("%ds", s)
end

local function Over(f, margin)
  if not f:IsVisible() then return false end
  local x, y = GetCursorPosition()
  local sc = f:GetEffectiveScale()
  x, y = x / sc, y / sc
  local l, b = f:GetLeft(), f:GetBottom()
  if not l then return false end
  local w, h = f:GetWidth(), f:GetHeight()
  return x >= l - margin and x <= l + w + margin and y >= b - margin and y <= b + h + margin
end

---------------------------------------------------------------------------
-- menu frame
---------------------------------------------------------------------------
local function RowClick(row)
  local e = row.entry
  if not e then return end
  menu:Hide()
  if e.kind == "spell" then
    CastSpellByName(e.name)
  else
    UseContainerItem(e.bag, e.slot)
  end
end

local function GetRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, menu)
  r:SetWidth(ROW_W)
  r:SetHeight(ROW_H)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetWidth(16)
  r.icon:SetHeight(16)
  r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.text:SetJustifyH("LEFT")
  r.cd = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.cd:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.cd:SetTextColor(1, 0.2, 0.2)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  r:GetHighlightTexture():SetBlendMode("ADD")
  r:RegisterForClicks("LeftButtonUp")
  r:SetScript("OnClick", function() RowClick(this) end)
  r:SetScript("OnEnter", function()
    local e = this.entry
    if not e then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    if e.kind == "spell" then
      GameTooltip:SetSpell(e.index, BOOKTYPE_SPELL)
    else
      GameTooltip:SetBagItem(e.bag, e.slot)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function RefreshCooldowns()
  for i = 1, table.getn(rows) do
    local r = rows[i]
    if r:IsVisible() and r.entry then
      local rem = Remaining(r.entry)
      if rem then
        r.cd:SetText(FormatTime(rem))
        r.text:SetTextColor(0.6, 0.6, 0.6)
      else
        r.cd:SetText("")
        r.text:SetTextColor(1, 1, 1)
      end
    end
  end
end

local function PlaceMenu()
  menu:ClearAllPoints()
  local x, y = btn:GetCenter()
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local v = (y and y > sh / 2) and "TOP" or "BOTTOM"
  local vo = (v == "TOP") and "BOTTOM" or "TOP"
  local h = (x and x > sw / 2) and "RIGHT" or "LEFT"
  menu:SetPoint(v .. h, btn, vo .. h, 0, 0)
end

local function OpenMenu()
  local res = BuildList()
  for i = 1, table.getn(rows) do
    rows[i]:Hide()
    rows[i].entry = nil
  end

  local n, y = 0, -8
  local function Header(text)
    n = n + 1
    local r = GetRow(n)
    r.entry = nil
    r:EnableMouse(false)
    r.icon:Hide()
    r.cd:SetText("")
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.text:SetText(text)
    r.text:SetTextColor(1, 0.82, 0)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
    r:Show()
    y = y - ROW_H
  end

  local any = false
  for _, g in ipairs(GROUPS) do
    local list = res[g.key]
    if list and table.getn(list) > 0 then
      any = true
      Header(g.title)
      for _, e in ipairs(list) do
        n = n + 1
        local r = GetRow(n)
        r.entry = e
        r:EnableMouse(true)
        r.icon:SetTexture(e.tex)
        r.icon:Show()
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
        r.text:SetText(e.name)
        r.text:SetTextColor(1, 1, 1)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
        r:Show()
        y = y - ROW_H
      end
    end
  end
  if not any then Header("No teleports available") end

  menu:SetWidth(ROW_W + 16)
  menu:SetHeight(-y + 8)
  PlaceMenu()
  menu.idle, menu.tick, menu.acc = 0, 0, 0
  menu:Show()
  RefreshCooldowns()
end

local function ToggleMenu()
  if menu:IsVisible() then menu:Hide() else OpenMenu() end
end

---------------------------------------------------------------------------
-- creation
---------------------------------------------------------------------------
local function CreateMenu()
  menu = CreateFrame("Frame", "TeleportMenuFrame", UIParent)
  menu:SetFrameStrata("DIALOG")
  menu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  menu:SetBackdropColor(0, 0, 0, 0.92)
  menu:EnableMouse(true)
  menu:Hide()
  menu.idle, menu.tick, menu.acc = 0, 0, 0
  -- OnUpdate only fires while the menu is shown; throttled to ~10 Hz
  menu:SetScript("OnUpdate", function()
    this.acc = this.acc + arg1
    if this.acc < 0.1 then return end
    local dt = this.acc
    this.acc = 0
    -- auto-close when the mouse has been away for a moment
    if Over(this, 10) or Over(btn, 4) then
      this.idle = 0
    else
      this.idle = this.idle + dt
      if this.idle > 0.8 then this:Hide() return end
    end
    this.tick = this.tick + dt
    if this.tick >= 0.5 then
      this.tick = 0
      RefreshCooldowns()
    end
  end)
  table.insert(UISpecialFrames, "TeleportMenuFrame")
end

local function UpdateButtonPosition()
  local a = TeleportMenuDB.angle or 200
  local r = math.rad(a)
  btn:ClearAllPoints()
  btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - 80 * math.cos(r), 80 * math.sin(r) - 52)
end

local function DragUpdate()
  local x, y = GetCursorPosition()
  local sc = UIParent:GetScale()
  local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
  x = xmin - x / sc + 70
  y = y / sc - ymin - 70
  TeleportMenuDB.angle = math.deg(math.atan2(y, x))
  UpdateButtonPosition()
end

local function CreateButton()
  btn = CreateFrame("Button", "TeleportMenuMinimapButton", Minimap)
  btn:SetFrameStrata("MEDIUM")
  btn:SetWidth(31)
  btn:SetHeight(31)
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalOrgrimmar")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnClick", function() ToggleMenu() end)
  btn:SetScript("OnDragStart", function()
    this.dragging = true
    GameTooltip:Hide()
    this:SetScript("OnUpdate", DragUpdate)   -- per-frame work only while dragging
  end)
  btn:SetScript("OnDragStop", function()
    this.dragging = nil
    this:SetScript("OnUpdate", nil)          -- back to zero per-frame cost
  end)
  btn:SetScript("OnEnter", function()
    if menu:IsVisible() or this.dragging then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("TeleportMenu")
    GameTooltip:AddLine("Click: open menu", 1, 1, 1)
    GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- init + slash commands
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("VARIABLES_LOADED")
f:SetScript("OnEvent", function()
  if not TeleportMenuDB then TeleportMenuDB = {} end
  if not TeleportMenuDB.spells then TeleportMenuDB.spells = {} end
  if not TeleportMenuDB.items  then TeleportMenuDB.items  = {} end
  CreateMenu()
  CreateButton()
  UpdateButtonPosition()
  this:UnregisterEvent("VARIABLES_LOADED")
  this:SetScript("OnEvent", nil)
end)

local function RemoveFrom(t, name)
  local found = false
  for i = table.getn(t), 1, -1 do
    if string.lower(t[i]) == string.lower(name) then
      table.remove(t, i)
      found = true
    end
  end
  return found
end

SLASH_TELEPORTMENU1 = "/tpm"
SlashCmdList["TELEPORTMENU"] = function(msg)
  local _, _, cmd, rest = string.find(msg or "", "^(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "addspell" and rest ~= "" then
    table.insert(TeleportMenuDB.spells, rest)
    Print("Added spell: " .. rest .. " (shown under 'Custom' once it is in your spellbook)")
  elseif cmd == "additem" and rest ~= "" then
    table.insert(TeleportMenuDB.items, rest)
    Print("Added item: " .. rest .. " (shown under 'Custom' while it is in your bags)")
  elseif cmd == "del" and rest ~= "" then
    local a = RemoveFrom(TeleportMenuDB.spells, rest)
    local b = RemoveFrom(TeleportMenuDB.items, rest)
    if a or b then Print("Removed: " .. rest) else Print("Not found: " .. rest) end
  elseif cmd == "list" then
    Print("Custom spells: " .. (table.getn(TeleportMenuDB.spells) > 0 and table.concat(TeleportMenuDB.spells, ", ") or "-"))
    Print("Custom items: " .. (table.getn(TeleportMenuDB.items) > 0 and table.concat(TeleportMenuDB.items, ", ") or "-"))
  elseif cmd == "reset" then
    TeleportMenuDB.angle = 200
    UpdateButtonPosition()
    Print("Button position reset.")
  else
    Print("/tpm - show this help menu")
    Print("/tpm addspell <spell name> - add a custom spell (partial names ok)")
    Print("/tpm additem <item name> - add a custom item (partial names ok)")
    Print("/tpm del <name> - remove a custom entry")
    Print("/tpm list - show custom entries")
    Print("/tpm reset - reset button position")
  end
end
