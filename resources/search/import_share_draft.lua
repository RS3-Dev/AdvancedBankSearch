local Text = require("resources/core/text")

-- The Bank Tags import preview flow, adapted to portable query metadata.
local ItemIdentity = require("resources/search/item_identity")
local ObjectConfig = require("resources/search/object_config")
local Draft = {}
local NO_FOLDER, NEW_FOLDER, FOLDER_NAME_Y = "none", "new", 236

function Draft:RefreshImportPreview(input)
    input = tostring(input or "")
    if self.closed or not self.ready or input == self.importSource then return end
    self.importSource = input
    self:ShowImportResult(input:match("%S") and "ready" or "empty", input)
end

function Draft:ShowImportResult(state, source)
    local imported, reason
    if state == "ready" then
        imported, reason = self.options.onDecode(source)
        if imported == nil then state = "invalid" end
    end
    self.importState = state
    self.importRevision = (self.importRevision or 0) + 1
    self.importText, self.importData = imported and source or nil, imported
    local single = imported and #imported.queries == 1 and imported.queries[1] or nil
    self.importSingleQuery = single
    self.importNameField:SetText(single and single.name or "", false)
    self.importNameField:SetDisabled(single == nil)
    self.importSpriteSlot:SetDisabled(single == nil)
    self:SetImportSprite(single and ItemIdentity.ObjectID(single.icon) or nil)
    self.importFolderName:SetText("", false)
    self:RefreshImportFolders(nil, true)
    self.importButton:SetDisabled(imported == nil)
    if state == "empty" then self:SetPageStatus(self.importStatus, nil, true)
    elseif imported == nil then self:SetPageStatus(self.importStatus, reason, false)
    else
        local count = #imported.queries
        self:SetPageStatus(self.importStatus, "Preview: " .. count .. (count == 1 and " query." or " queries.")
            .. " Same-named queries will be replaced. Not saved until you import.", true)
    end
end

function Draft:RefreshImportFolders(selectedID, reset)
    if not reset then selectedID = selectedID or self.importFolder:GetSelectedID() end
    local entries = { { id = NO_FOLDER, label = "No folder", order = 1 } }
    local available, matching = { [NO_FOLDER] = true, [NEW_FOLDER] = true }, {}
    for _, folder in ipairs(self.options.onGetFolders()) do
        local key = "folder:" .. folder.id
        entries[#entries + 1] = { id = key, label = Text.plain(folder.name), order = #entries + 1 }
        available[key], matching[string.lower(folder.name)] = true, key
    end
    local single = self.importSingleQuery
    local initial = NO_FOLDER
    if single ~= nil and single.folder ~= nil then
        initial = matching[single.folder]
        if initial == nil then
            for _, folder in ipairs(self.importData.folders) do
                if folder.key == single.folder then
                    initial = "shared:" .. folder.key
                    available[initial] = true
                    entries[#entries + 1] = { id = initial, label = Text.plain(folder.name), order = #entries + 1 }
                end
            end
        end
    end
    entries[#entries + 1] = { id = NEW_FOLDER, label = "New folder...", order = #entries + 1 }
    self.importFolder:SetEntries(entries, available[selectedID] and selectedID or initial or NO_FOLDER)
    self.importFolder:SetDisabled(single == nil)
    self:UpdateImportFolderControls()
end

function Draft:UpdateImportFolderControls()
    if self.importFolderName == nil then return end
    local creating = self.importSingleQuery ~= nil and self.importFolder:GetSelectedID() == NEW_FOLDER
    self.importFolderName.root.hidden = not creating
    self.importFolderName:SetDisabled(not creating)
    local buttonY = creating and FOLDER_NAME_Y + 42 or FOLDER_NAME_Y
    self.importButton.root:SetPos(18, buttonY)
    self.importStatus:SetPos(18, buttonY + 36)
end

function Draft:SetImportSprite(objectID)
    self.importSpriteObjectID = math.tointeger(tonumber(objectID))
    self.importSpriteSlot:SetObject(ObjectConfig.FromID(self.importSpriteObjectID))
end

function Draft:ChooseImportSprite()
    if self.closed or self.importSingleQuery == nil then return end
    local revision = self.importRevision
    self.options.onChooseImportSprite(function(objectID)
        if not self.closed and self.importRevision == revision then self:SetImportSprite(objectID) end
    end)
end

function Draft:Import()
    if self.closed then return end
    self:RefreshImportPreview(self.importField:GetText())
    if self.importState ~= "ready" then return end
    local overrides
    if self.importSingleQuery ~= nil then
        overrides = { name = self.importNameField:GetText(), spriteObjectID = self.importSpriteObjectID }
        local selected = self.importFolder:GetSelectedID()
        if selected == NEW_FOLDER then overrides.newFolderName = self.importFolderName:GetText()
        elseif selected == NO_FOLDER then overrides.folderID = false
        elseif selected and selected:sub(1, 7) == "folder:" then overrides.folderID = selected:sub(8)
        elseif selected and selected:sub(1, 7) == "shared:" then overrides.sharedFolder = selected:sub(8) end
    end
    local saved, summary, reason = self.options.onImport(self.importText, overrides)
    if not saved then self:SetPageStatus(self.importStatus, reason or "Could not import the queries.", false); return end
    self:RefreshImportFolders()
    local count = summary.queries or 0
    self:SetPageStatus(self.importStatus, "Imported " .. count .. (count == 1 and " query." or " queries."), true)
end
return { methods = Draft, NO_FOLDER = NO_FOLDER, NEW_FOLDER = NEW_FOLDER, FOLDER_NAME_Y = FOLDER_NAME_Y }
