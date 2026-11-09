package.path='./?.lua;./?/init.lua;'..package.path
-- Query-code validation and atomic storage, plus the Bank Tags footer and Import/Share flow.
-- FAKE HOST: native tab rendering, clipboard shortcuts and modal input need a live check.
local Harness=require('tools/test_support/search_harness')
local h=Harness.new('query_sharing')
h:NameObjects({{101,'Iron bar'},{102,'Iron ore'},{105,'Lobster'}})
h.bankHost:SetItems({{101,5},{102,10},{105,20}})
h:LoadCore();h:LoadRuneQL();h:LoadSearch();h:OpenBank();h:Tick(2)
local app=h:App()
local function press(button)
 local action=button.root.hooks[ui.Hook.ONBUTTONPRESSED] or button.root.hooks[ui.Hook.ONCLICK]
 action();h:Tick()
end
local function enter(field,value)
 field.root.content=value
 field.root.hooks[ui.Hook.ONCONTENTCHANGED](field.root,'change',value)
end
local Code=h.search.env.require('resources/search/query_code')
local Json=h.search.env.require('resources/core/json')
local Store=h.search.env.require('resources/search/query_store')
local engine=app:RuneQL()
local controls=app.tab.controls
local wideNew=controls.new.root.width
assert(controls.share.spriteName=='EXPORT' and controls.new.root.text.content=='New Query')
assert(controls.edit.hidden and controls.edit.icon.hidden and controls.delete==nil)
assert(controls.new.root.x==44 and wideNew==controls.width-36)
local body={match='any',rules={
 {match='all',rules={{field='price',operator='atleast',value=1000},{field='slot',operator='includes',value='body'}}},
 {match='all',rules={{field='slot',operator='includes',value='head'}}}}}
local Builder=h.search.env.require('resources/search/query_builder')
local expression=assert(Builder.Build(body))
assert(app:SaveQuery(nil,'Armour',expression,body,101))
assert(app:SaveQuery(nil,'Potions','dose:[4 TO 4]',nil,102))
assert(app:CreateFolder('Combat','1'))
assert(app.queries:RenameFolder('1','Combat',102))
assert(app.queries:SetFolderCollapsed('1',true))
app:Refresh()
assert(not controls.edit.hidden and controls.new.root.width==wideNew-36)
assert(controls.edit.spriteName=='PENCIL')
Harness.Fire(controls.edit.root,ui.Hook.ONMOUSEOVER)
assert(not controls.edit.tooltip.root.hidden)
app.selectedQuery=nil;app:Refresh()
assert(controls.edit.hidden and controls.edit.tooltip.root.hidden and controls.new.root.width==wideNew)
assert(h:ClickRow('2'));h:Tick(2)
assert(not controls.edit.hidden)
local exports=app.queries:QueryExports()
assert(#exports==3 and exports[1].name=='All queries (backup)')
local backup=exports[1].value
local armourCode=Code.Encode(app.queries:Tree(),'1')
local potionsCode=Code.Encode(app.queries:Tree(),'2')
local decoded=assert(Code.Decode(armourCode,engine))
assert(#decoded.queries==1 and decoded.queries[1].folder=='combat')
assert(decoded.queries[1].builder.rules[1].rules[2].field=='slot')
assert(decoded.queries[1].icon=='IRON_BAR' and decoded.folders[1].icon=='IRON_ORE')

-- Import into another save with conflicting local IDs; portable names map to fresh IDs.
local originalDB=h.search.env.PersistentDB
local values={}
local db={GetString=function(_,key) return values[key] end,SetString=function(_,key,value) values[key]=value;return true end}
h.search.env.PersistentDB=db
local destination=Store.new()
assert(destination:Save(nil,'Unrelated','iron'))
assert(destination:CreateFolder('Local','1'))
local imported,summary=destination:ImportText(backup,nil,engine)
assert(imported and summary.queries==2)
local importedArmour=destination:FindName('Armour')
assert(importedArmour.id=='2' and destination:FolderOf(importedArmour.id)=='2')
assert(destination:GetFolder('1').name=='Local' and destination:GetFolder('2').name=='Combat')
assert(destination:GetFolder('2').collapsed and destination:GetFolderSprite('2')==102)
assert(importedArmour.query==expression and importedArmour.builder.rules[1].rules[2].value=='body')
assert(destination:GetQuerySprite(importedArmour.id)==101)
-- Same-name replacement retains the destination ID, including with a case change.
assert(destination:ImportText(armourCode,{name='ARMOUR',folderID=false},engine))
assert(destination:FindName('ARMOUR').id==importedArmour.id and destination:FolderOf(importedArmour.id)==nil)
assert(#destination:All()==3)
-- Overrides can rename, pick an icon and create a destination folder atomically.
assert(destination:ImportText(armourCode,{name='Shared armour',spriteObjectID=105,newFolderName='Imported'},engine))
local customized=destination:FindName('Shared armour')
assert(destination:GetQuerySprite(customized.id)==105)
assert(destination:GetFolder(destination:FolderOf(customized.id)).name=='Imported')
local before=Json.encode(destination.data)
local bad=Json.decode(backup)
bad.queries[2].query='iron AND ('
assert(not destination:ImportText(Json.encode(bad),nil,engine))
assert(Json.encode(destination.data)==before)
assert(not destination:ImportText(armourCode,{name='',folderID=false},engine))
assert(not destination:ImportText(armourCode,{name='Bad',folderID='999'},engine))
assert(not destination:ImportText(armourCode,{name='Bad',spriteObjectID=-1},engine))
assert(Json.encode(destination.data)==before)
-- Manifest failure may write inactive chunks, but neither active save nor live data changes.
h.search.env.PersistentDB={GetString=db.GetString,SetString=function(_,key,value)
 if key=='advancedbanksearch:queries:v1:manifest' then return false end
 values[key]=value;return true
end}
assert(not destination:ImportText(armourCode,{name='Failed import',newFolderName='Not saved'},engine))
assert(Json.encode(destination.data)==before)
assert(Store.new():FindName('Failed import')==nil)
h.search.env.PersistentDB=db
assert(Store.new():Get(customized.id).builder.rules[1].rules[2].value=='body')
-- Invalid envelopes, bad syntax and duplicate names never produce a ready preview.
for _,text in ipairs({'','not JSON','{}','{"format":"bankutilities-tags","version":4,"tags":{}}'}) do
 assert(Code.Decode(text,engine)==nil)
end
assert(Code.Decode(armourCode,nil)==nil)
bad=Json.decode(armourCode);bad.version=99;assert(Code.Decode(Json.encode(bad),engine)==nil)
bad=Json.decode(backup);bad.queries[2].name='ARMOUR';assert(Code.Decode(Json.encode(bad),engine)==nil)
bad=Json.decode(armourCode);bad.folders={17};assert(Code.Decode(Json.encode(bad),engine)==nil)
bad=Json.decode(armourCode);bad.queries[1].icon='#999999999999';assert(Code.Decode(Json.encode(bad),engine)==nil)
-- Optional malformed visual metadata cannot recurse unboundedly or alter the expression.
bad=Json.decode(armourCode)
local deep={match='all',rules={{field='qty',operator='equals',value=1}}}
for _=1,20 do deep={match='all',rules={deep}} end
bad.queries[1].builder=deep
local safe=assert(Code.Decode(Json.encode(bad),engine))
assert(safe.queries[1].builder==nil and safe.queries[1].query==expression)
h.search.env.PersistentDB=originalDB

-- The actual footer opens the copied two-tab window; preview alone writes nothing.
local manifestBefore=h.databases.advancedbanksearch['advancedbanksearch:queries:v1:manifest']
press(controls.share)
local window=app.importShare
assert(window~=nil and window.tabs:GetActiveIndex()==1)
assert(#window.shareRows==3 and window.shareRows[1].field:GetText()==backup)
window.tabs:SetActive(2);assert(window.tabs:GetActiveIndex()==2)
window.tabs:SetActive(1)
assert(window.importButton.disabled)
enter(window.importField,'bad code')
assert(window.importState=='invalid' and window.importButton.disabled)
enter(window.importField,armourCode)
assert(window.importState=='ready' and not window.importButton.disabled)
assert(window.importNameField:GetText()=='Armour')
assert(window.importSpriteObjectID==101 and window.importFolder:GetSelectedID()=='folder:1')
assert(h.databases.advancedbanksearch['advancedbanksearch:queries:v1:manifest']==manifestBefore)
local find=engine.Catalog.Find
engine.Catalog.Find=function() return {{configName='LOBSTER',displayName='Lobster'}},1 end
window.importSpriteSlot.root.hooks[ui.Hook.ONCLICK]()
local picker=app.iconPicker
picker:RunSearch('lobster')
assert(#picker.hitTargets==1)
local tip=picker.tooltips[1].root
picker.hitTargets[1].hooks[ui.Hook.ONMOUSEOVER]()
assert(not tip.hidden)
picker.hitTargets[1].hooks[ui.Hook.ONCLICK]()
assert(tip.destroyed and app.iconPicker==nil and window.importSpriteObjectID==105)
-- A picker result from an older pasted code cannot overwrite the new draft's icon.
window.importSpriteSlot.root.hooks[ui.Hook.ONCLICK]();picker=app.iconPicker;picker:RunSearch('lobster')
enter(window.importField,potionsCode)
assert(window.importSpriteObjectID==102)
picker.hitTargets[1].hooks[ui.Hook.ONCLICK]()
assert(window.importSpriteObjectID==102)
engine.Catalog.Find=find
enter(window.importField,armourCode)
window.importNameField:SetText('Shared armour')
window:SetImportSprite(105)
window.importFolder:Select('new',true)
window.importFolderName:SetText('Shared')
assert(not window.importFolderName.root.hidden and window.importButton.root.y==278)
-- One explicit import makes one storage publication and refreshes share codes.
local chunks=h.search.env.require('resources/core/chunked_string_store')
local write,writes=chunks.Write,0
chunks.Write=function(...) writes=writes+1;return write(...) end
press(window.importButton)
assert(writes==1 and app.queries:FindName('Shared armour')~=nil)
local shared=app.queries:FindName('Shared armour')
assert(app.queries:GetQuerySprite(shared.id)==105 and app.queries:GetFolder(app.queries:FolderOf(shared.id)).name=='Shared')
assert(window.importStatus.content=='Imported 1 query.' and #window.shareRows==4)
-- Rejection leaves both preview and store intact.
window.importNameField:SetText('')
press(window.importButton)
assert(writes==1 and window.importStatus.content:find('name',1,true))
chunks.Write=write
-- Bank Tags keeps Import/Share available across bank close; reload retires it and its picker.
app:OnBankClose();assert(app.importShare==window)
window.importSpriteSlot.root.hooks[ui.Hook.ONCLICK]();picker=app.iconPicker
local windowRoot=window.window.root
h.host:Unload('advancedbanksearch')
assert(windowRoot.destroyed and picker.window==nil)
h:LoadSearch();app=h:App();h:Tick(2)
shared=app.queries:FindName('Shared armour')
assert(shared~=nil and shared.builder.rules[1].rules[2].field=='slot')
-- Constructor failures release the partially built popup.
local fieldFactory=prettyui.TextField.new
local baseline=app.importShare
prettyui.TextField.new=function() error('injected import field failure') end
local ok=pcall(function() app:OpenImportShare() end)
prettyui.TextField.new=fieldFactory
assert(not ok and app.importShare==baseline)
app:OpenImportShare();window=app.importShare
window.window:Close()
assert(app.importShare==nil and window.closed and window.window==nil)
h.host:Unload('advancedbanksearch');h.host:Unload('bankcore')
print('query_sharing_test: ok')
