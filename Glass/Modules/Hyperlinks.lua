local Core, Constants = unpack(select(2, ...))
local Hyperlinks = Core:GetModule("Hyperlinks")

local OpenCopy = Constants.ACTIONS.OpenCopy
local OpenNews = Constants.ACTIONS.OpenNews

local HYPERLINK_CLICK = Constants.EVENTS.HYPERLINK_CLICK
local HYPERLINK_ENTER = Constants.EVENTS.HYPERLINK_ENTER
local HYPERLINK_LEAVE = Constants.EVENTS.HYPERLINK_LEAVE

-- luacheck: push ignore 113
local BattlePetToolTip_ShowLink = BattlePetToolTip_ShowLink
local BattlePetTooltip = BattlePetTooltip
local GameTooltip = GameTooltip
local ShowUIPanel = ShowUIPanel
local UIParent = UIParent
local strmatch = strmatch
local strsplit = strsplit
-- luacheck: pop

local linkTypes = {
  item = true,
  enchant = true,
  spell = true,
  quest = true,
  achievement = true,
  currency = true,
  battlepet = true,
}

function Hyperlinks:OnInitialize()
  self.state = {
    showingTooltip = nil
  }
end

function Hyperlinks:OnEnable()
  -- Custom hyperlink for [See what's new]
  _G.hooksecurefunc("SetItemRef", function(link)
    local linkType, addon, param1 = strsplit(":", link)
    if linkType == "garrmission" and addon == "Glass" then
      if param1 == "opennews" then
        Core:Dispatch(OpenNews())
      end
    end
  end)

  Core:Subscribe(HYPERLINK_CLICK, function (payload)
    local link, text, button, chatFrame = unpack(payload)

    -- Web links made by Glass: open the copy window, the game can't open them
    local url = strmatch(link, "^glassurl:(.+)$")
    if url then
      Core:Dispatch(OpenCopy({ title = "Glass Forever: Copy link", text = url, height = 140 }))
      return
    end

    -- Use global reference in case some addon has hooked into it for custom
    -- hyperlinks (e.g. Mythic Dungeon Tools, Prat)
    -- The game's chat window the link is in goes along (e.g. a whisper opens
    -- in its box), except for right clicks: the game would attach the menu to
    -- that window, which is hidden under Glass, and the menu didn't show.
    -- (marked while it runs: some menus opened from here are changed, below)
    self.fromGlass, self.clickLink, self.clickChatFrame = true, link, chatFrame
    local frameForGame = button ~= "RightButton" and chatFrame or nil
    local ok, problem = pcall(_G.SetItemRef, link, text, button, frameForGame)
    self.fromGlass = false
    if not ok then geterrorhandler()(problem) end
  end)

  -- "Copy Character Name" in a player's menu opened from the Glass chat: the
  -- game only lets its own menus put text on the clipboard, and blocked it
  -- with an error. Here it opens the Glass copy window instead, with the name
  -- selected (Ctrl+C). The game's own menus (e.g. on your target) are left
  -- as they are.
  local Menu, MenuUtil = _G.Menu, _G.MenuUtil
  local copyText = _G.COPY_CHARACTER_NAME
  if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.GetElementText and copyText then
    local function ChangeCopy(_, rootDescription, contextData)
      if not self.fromGlass or not rootDescription.EnumerateElementDescriptions then return end
      local name = contextData and contextData.name
      if type(name) ~= "string" then return end
      for _, description in rootDescription:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(description) == copyText and description.SetResponder then
          description:SetResponder(function ()
            Core:Dispatch(OpenCopy({ title = "Glass Forever: Copy name", text = name, height = 140 }))
          end)
        end
      end
    end
    for _, which in ipairs({ "FRIEND", "FRIEND_OFFLINE", "BN_FRIEND", "BN_FRIEND_OFFLINE", "CHAT_ROSTER",
      "PLAYER", "PARTY", "RAID_PLAYER", "GUILD", "GUILD_OFFLINE",
      "COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER" }) do
      Menu.ModifyMenu("MENU_UNIT_"..which, ChangeCopy)
    end
  end

  -- "Move to New Window" in a channel's menu opened from the Glass chat: the
  -- game needs the chat window the channel was in (it copies its settings
  -- and moves the channel out of it), which the menu doesn't have here (see
  -- above). It's given that window.
  local moveText = _G.MOVE_TO_NEW_WINDOW
  local ChatFrameUtil = _G.ChatFrameUtil
  if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.GetElementText and moveText
    and ChatFrameUtil and ChatFrameUtil.PopOutChat then
    Menu.ModifyMenu("MENU_CHAT_FRAME_CHANNEL", function (_, rootDescription)
      local chatFrame, link = self.clickChatFrame, self.clickLink
      if not self.fromGlass or not chatFrame or type(link) ~= "string"
        or not rootDescription.EnumerateElementDescriptions then
        return
      end
      -- "channel:CHANNEL:2", "channel:GUILD"...
      local _, chatType, chatTarget = strsplit(":", link)
      if not chatType then return end
      chatType = strupper(chatType) -- the link has "channel", the game wants "CHANNEL"
      for _, description in rootDescription:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(description) == moveText and description.SetResponder then
          description:SetResponder(function ()
            ChatFrameUtil.PopOutChat(chatFrame, chatType, chatTarget)
          end)
        end
      end
    end)
  end

  Core:Subscribe(HYPERLINK_ENTER, function (payload)
    local link, text = unpack(payload)
    local t = string.match(link, "^(.-):")

    if linkTypes[t] then
      if t == "battlepet" then
        self.state.showingTooltip = BattlePetTooltip
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        BattlePetToolTip_ShowLink(text)
      else
        self.state.showingTooltip = GameTooltip
        ShowUIPanel(GameTooltip)
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
      end
    end
  end)

  Core:Subscribe(HYPERLINK_LEAVE, function (link)
    if self.state.showingTooltip then
      self.state.showingTooltip:Hide()
      self.state.showingTooltip = false
    end
  end)
end
