local Core = unpack(select(2, ...))
local DefaultTabs = Core:GetModule("DefaultTabs")

-- luacheck: push ignore 113
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local FCF_OpenNewWindow = FCF_OpenNewWindow
local InCombatLockdown = InCombatLockdown
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local UIParent = UIParent
-- luacheck: pop

-- The tabs offered, with the chat types each one shows
local TABS = {
  { name = "Guild", groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
  { name = "Party", groups = {
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
  } },
}

----
-- DefaultTabs Module
--
-- The first time you log in with a character, offers to create a Guild and a
-- Party tab, so the chat is organized out of the box. Asked once per
-- character (chat tabs are saved per character), and not at all if the
-- character already has both.

-- True if a chat window other than General and Combat Log already shows this
-- tab's chat (or has its name)
local function HasTab(tab)
  for i = 3, NUM_CHAT_WINDOWS do
    local chatFrame = _G["ChatFrame"..i]
    if chatFrame and (chatFrame.isDocked or chatFrame:IsShown()) then
      if chatFrame.name == tab.name then
        return true
      end
      for _, group in ipairs(chatFrame.messageTypeList or {}) do
        if group == tab.groups[1] then
          return true
        end
      end
    end
  end
  return false
end

local function MissingTabs()
  local missing = {}
  for _, tab in ipairs(TABS) do
    if not HasTab(tab) then
      table.insert(missing, tab)
    end
  end
  return missing
end

local function CreateTabs(tabs)
  for _, tab in ipairs(tabs) do
    -- No default chat types: only the ones listed for this tab
    local chatFrame = FCF_OpenNewWindow(tab.name, true)
    if chatFrame then
      local general = _G.DEFAULT_CHAT_FRAME
      for _, group in ipairs(tab.groups) do
        if chatFrame.AddMessageGroup then
          chatFrame:AddMessageGroup(group)
        elseif _G.ChatFrame_AddMessageGroup then
          _G.ChatFrame_AddMessageGroup(chatFrame, group)
        end
        -- Moved out of General, so the messages don't show twice
        if general.RemoveMessageGroup then
          general:RemoveMessageGroup(group)
        elseif _G.ChatFrame_RemoveMessageGroup then
          _G.ChatFrame_RemoveMessageGroup(general, group)
        end
      end
    end
  end
end

local function CreateDialog(tabs)
  local dialog = CreateFrame("Frame", "GlassDefaultTabsDialog", UIParent, "DefaultPanelFlatTemplate")
  dialog:SetFrameStrata("DIALOG")
  dialog:SetToplevel(true)
  dialog:SetClampedToScreen(true)
  dialog:SetSize(380, 150)
  dialog:SetPoint("TOP", 0, -120)
  if dialog.SetTitle then
    dialog:SetTitle("Glass Forever")
  end

  local bg = dialog:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 7, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local names = {}
  for _, tab in ipairs(tabs) do
    table.insert(names, tab.name)
  end

  local desc = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  desc:SetJustifyV("TOP")
  desc:SetJustifyH("LEFT")
  desc:SetPoint("TOPLEFT", 18, -34)
  desc:SetPoint("BOTTOMRIGHT", -18, 48)
  desc:SetText(
    "Create "..table.concat(names, " and ").." "..(#tabs > 1 and "tabs" or "tab")..
    " for your chat? Those messages move out of General into their own "..
    (#tabs > 1 and "tabs" or "tab")..".\n\nThe interface reloads to finish."
  )

  -- Windows made by an addon only become regular game windows after a
  -- reload; until then the game's chat code could run into errors. Addons
  -- can't reload the interface, so this is a secure button that runs /reload
  -- for the player, like a macro. The tabs are created just before, in the
  -- same click.
  local yes = Core.Components.CreateButton(dialog, "SecureActionButtonTemplate")
  yes:SetText("Create tabs")
  yes:SetPoint("BOTTOMRIGHT", -14, 14)
  yes:SetAttribute("type", "macro")
  yes:SetAttribute("macrotext", "/reload")
  yes:RegisterForClicks("AnyUp", "AnyDown")

  local created = false
  yes:SetScript("PreClick", function ()
    -- A click comes as a press and a release: create the tabs only once
    if created or InCombatLockdown() then return end
    created = true
    CreateTabs(tabs)
  end)

  local no = Core.Components.CreateButton(dialog)
  no:SetText("No thanks")
  no:SetPoint("RIGHT", yes, "LEFT", -8, 0)
  no:SetScript("OnClick", function ()
    dialog:Hide()
  end)

  dialog:SetScript("OnShow", function () PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end)
  dialog:SetScript("OnHide", function () PlaySound(SOUNDKIT.GS_TITLE_OPTION_EXIT) end)
  return dialog
end

----
-- Whispers in their own tabs: a new account shows them in General. The first
-- time Glass runs on an account, that game option (Options > Social > New
-- Whispers) is set to "New Tab", and a line in the chat says so. Only once:
-- whoever sets it back keeps it.
local function WhispersInTabs()
  if Core.db.global.whispersInTabs then return end
  Core.db.global.whispersInTabs = true
  local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
  local SetCVar = C_CVar and C_CVar.SetCVar or _G.SetCVar
  if not (GetCVar and SetCVar) then return end
  local changed = false
  for _, cvar in ipairs({ "whisperMode", "bnWhisperMode" }) do
    if GetCVar(cvar) == "inline" then
      changed = pcall(SetCVar, cvar, "popout") or changed
    end
  end
  if changed then
    print("|cffdfba69Glass Forever|r: whispers now open in their own tab. To change it: Options > Social > New Whispers.")
  end
end

function DefaultTabs:OnEnable()
  C_Timer.After(3, WhispersInTabs)

  if Core.db.char.defaultTabsOffered then return end

  -- Wait for the game to finish setting up the chat windows
  C_Timer.After(3, function ()
    if InCombatLockdown() or not FCF_OpenNewWindow then return end

    -- Asked once per character, whatever the answer
    Core.db.char.defaultTabsOffered = true

    local tabs = MissingTabs()
    if #tabs > 0 then
      CreateDialog(tabs):Show()
    end
  end)
end
