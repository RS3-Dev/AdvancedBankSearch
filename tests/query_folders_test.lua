package.path = './?.lua;./?/init.lua;' .. package.path
-- Drive Bank Tags-style query rows, drag gestures, menus and name/icon editing.
-- FAKE HOST: held-pointer capture and native menu rendering still need a live check.
local Harness = require('tests/support/search_harness')
local h = Harness.new('query_folders')
h:NameObjects({{101,'Iron bar'},{102,'Iron ore'},{105,'Lobster'}})
h.bankHost:SetItems({{101,5},{102,5},{105,9}})
h:LoadCore();h:LoadRuneQL();h:LoadSearch()
local app = h:App()
local _,layout = h:OpenBank()
h:Tick(2)
local tab,controls = app.tab,app.tab.controls
assert(controls ~= nil, tostring(h:LoggedFailure()))
local parent = h:TabParent()
local function tree() return app.tab.controls.tree end
local function rows()
    local labels = {}
    for _,row in ipairs(controls.list.rows) do
        local entry = tree().entriesByID[row.entry.id]
        labels[#labels+1] = (entry.folder and '>' or '') .. row.label.content .. (entry.selected and '*' or '')
    end
    return table.concat(labels,' | ')
end
local function row(id) return assert(tree():RowFor(id),id) end
local function press(button) local action = button.root.hooks[ui.Hook.ONBUTTONPRESSED] or button.root.hooks[ui.Hook.ONCLICK]; action();h:Tick() end
local function enter(field,text)
    field.root.content = text
    field.root.hooks[ui.Hook.ONCONTENTCHANGED](field.root,'change',text)
end
local function shown() return app:ShownPage() end
local function menuOver(id,coreFirst)
    local value = row(id)
    h:PointAt(controls.list.viewport,20,value.root.y-controls.list.scrollY+10)
    return h:ContentMenu(coreFirst)
end
local function choose(menu,label) Harness.Choose(menu,label);h:Tick() end

-- Equal eight-unit padding on the left, right, and below Search; no reorder button.
local width = controls.width
assert(controls.field.options.width == width and controls.field.options.x == 8)
assert(controls.list.root.x == 8 and controls.list.root.y == 42)
assert(controls.list.root.y - controls.field.options.y - controls.field.options.height == 8)
assert(controls.sort == nil and controls.status == nil)
local top, listHeight, field = controls.list.root.y, controls.list.root.height, controls.field
enter(field,'iron');h:Tick(12)
assert(controls.list.root.y == top and controls.list.root.height == listHeight and controls.field == field)
app:ShowStatus(string.rep('error ',30),true);app:Refresh()
assert(controls.list.root.y == top and controls.list.root.height == listHeight)
enter(field,'');h:Tick(12)

local builder={match='all',rules={{field='name',operator='phrase',value='iron'}}}
for _,record in ipairs({{'Bars','name:"iron"',builder},{'Ores','ore'},{'Fish','lobster'},{'Spare','bar'}}) do
    assert(app:SaveQuery(nil,record[1],record[2],record[3]))
end
assert(app:CreateFolder('Smithing','1') and app:MoveQueryToFolder('2','1'))
assert(app.queries:CreateFolder('Empty'))
app:Refresh()
assert(rows() == 'Smithing (2) | >Bars | >Ores | Fish | Spare*',rows())
assert(row('1').label.x == 26 and row('3').label.x == 6)
assert(row('folder:1').label.x == 26)
assert(row('folder:1').root.hooks[ui.Hook.ONHOLD] ~= nil)
assert(controls.list.entryHeight == 32)
assert(h:ClickRow('1'));h:Tick(2)
assert(shown() == 'query' and app.pageQuery == '1')
assert(row('1').label.content == 'Bars' and row('folder:1').label.content == 'Smithing (2)')
assert(h:ClickRow('folder:1'));h:Tick(2)
assert(rows() == 'Smithing (2)* | Fish | Spare',rows())
assert(getmetatable(app.queries).new():GetFolder('1').collapsed)
assert(h:ClickRow('folder:1'));h:Tick(2)

-- Same drag threshold, ghost, insertion line, sibling rules, and whole-folder moves.
local Geometry = h.search.env.require('resources/search/geometry')
local function point(y,x)
    local ox,oy=Geometry.absolutePosition(controls.list.viewport)
    h.bankHost.mouse={x=ox+(x or 40),y=oy+y-controls.list.scrollY}
end
local function start(id)
    local value=row(id)
    point(value.root.y+12)
    assert(controls.list:Click(id))
    return value.root
end
local function hold(root,y,x) point(y,x);root.hooks[ui.Hook.ONHOLD]() end
local function drag(id,y)
    local root=start(id)
    hold(root,y)
    root.hooks[ui.Hook.ONRELEASE]()
    h:Tick()
end
local root=start('3')
hold(root,row('3').root.y+15,43)
assert(not tree().gesture.dragging,'a small wobble stays a click')
root.hooks[ui.Hook.ONRELEASE]()
h:Tick(2)
assert(app.pageQuery == '3' and shown() == 'query')
root=start('2')
hold(root,32+2)
local gesture=tree().gesture
assert(gesture.dragging and gesture.ghost.clickthrough and not gesture.line.hidden)
assert(gesture.target.entry.id == '1' and not gesture.target.after)
for _,part in ipairs(gesture.row.parts) do assert(part.hidden) end
local ghost,line=gesture.ghost,gesture.line
root.hooks[ui.Hook.ONRELEASE]()
assert(ghost.destroyed and line.destroyed and root.destroyed and tree().gesture == nil)
assert(app.queries:GetFolder('1').count == 2 and app.queries:Tree()[1].queries[1].id == '2')
root.hooks[ui.Hook.ONDRAGCOMPLETE]() -- second release must not save again
assert(app.pageQuery == '3','a drag never selects a query')
-- A member cannot leave its folder by dragging.
root=start('1');hold(root,3*32+15)
assert(tree().gesture.target == nil)
root.hooks[ui.Hook.ONRELEASE]()
assert(app.queries:FolderOf('1') == '1')
-- A top-level query crosses the complete folder block, preserving membership.
drag('3',4)
assert(app.queries:Tree()[1].query.id == '3' and app.queries:FolderOf('2') == '1')
drag('folder:1',5*32-4)
assert(app.queries:Tree()[2].query.id == '4' and app.queries:Tree()[3].id == '1')
-- Cancel outside, on refresh, resize, and unmount.
root=start('3');hold(root,50);ghost=tree().gesture.ghost;hold(root,50,-50)
assert(tree().gesture == nil and ghost.destroyed)
root=start('3');hold(root,50);ghost=tree().gesture.ghost;app:Refresh()
assert(tree().gesture == nil and ghost.destroyed)
local context=tab.ctx
root=start('3');hold(root,50);ghost=tree().gesture.ghost
context.height=context.height-30;tab.callbacks.resize(context)
assert(tree().gesture == nil and ghost.destroyed and controls.field == field)
context.height=context.height+30;tab.callbacks.resize(context)
-- Failed drag persistence rolls back data and row order.
local database=h.search.env.PersistentDB
local before=rows()
h.search.env.PersistentDB={GetString=database.GetString,SetString=function() return false end}
drag('3',2*32-1)
assert(rows() == before and app.statusIsError,rows())
h.search.env.PersistentDB=database

-- Menus mirror Bank Tags: Select, Edit, Rename, folder actions, Remove.
-- The first explicit row action is the default regardless of callback order.
for _,coreFirst in ipairs({false,true}) do
    local menu=menuOver('3',coreFirst)
    assert(menu.entries[menu.entryCount].verbText:find('Select',1,true),Harness.Labels(menu))
    assert(Harness.Labels(menu):find('Rename Fish',1,true))
end
app.ext:Close();h:Tick(2)
local nativeMenu=h:ContentMenu(false,h.bankHost.items[1])
assert(not Harness.Labels(nativeMenu):find('Rename',1,true),'bank item menus never get query-row actions')
-- An unopened menu is not an explicit choice; a later row press invalidates it.
local menu=menuOver('3')
for _,entry in ipairs(menu.entries) do if entry.verbText:find('Rename',1,true) then entry.action() end end
h:Tick();assert(app.appearanceEditor == nil)
menu=menuOver('3');assert(h:ClickRow('4'));choose(menu,'Rename')
assert(app.appearanceEditor == nil)
-- Rename has the same name field and 40-unit icon slot as Bank Tags.
menu=menuOver('3');choose(menu,'Rename')
local appearance=app.appearanceEditor
assert(appearance ~= nil and appearance.field:GetText() == 'Fish')
assert(appearance.spriteSlot.root.width == 40 and appearance.spriteSlot.options.tooltip == 'Click to edit')
appearance.field:SetText('FISH renamed')
appearance:SetSprite(101)
press(appearance.saveButton)
assert(app.appearanceEditor == nil and app.queries:Get('3').name == 'FISH renamed')
assert(app.queries:GetQuerySprite('3') == 101 and app.queries:Get('3').query == 'lobster')
assert(row('3').label.x == 34)
-- Rename folders and give them an icon without changing members or collapsed state.
menu=menuOver('folder:1');choose(menu,'Rename folder')
appearance=app.appearanceEditor
assert(appearance.spriteObjectID == nil, 'a folder must not inherit a same-ID query icon')
appearance.field:SetText('Metal');appearance:SetSprite(102);press(appearance.saveButton)
assert(app.queries:GetFolder('1').name == 'Metal' and app.queries:GetFolderSprite('1') == 102)
assert(app.queries:FolderOf('1') == '1' and row('folder:1').label.x == 34)
-- Duplicate names and failed writes keep the editor open and existing metadata intact.
app:OpenRenameQuery('1');appearance=app.appearanceEditor
appearance.field:SetText('Ores');press(appearance.saveButton)
assert(app.appearanceEditor == appearance and not appearance.status.hidden)
appearance.field:SetText('Bars renamed')
h.search.env.PersistentDB={GetString=database.GetString,SetString=function() return false end}
press(appearance.saveButton)
assert(app.queries:Get('1').name == 'Bars' and app.appearanceEditor == appearance)
h.search.env.PersistentDB=database
press(appearance.saveButton)
assert(app.queries:Get('1').builder.rules[1].field == 'name')

-- Use the actual item-search picker, with runtime config resolution and clean tooltips.
local engine=app:RuneQL()
local find=engine.Catalog.Find
engine.Catalog.Find=function() return {{configName='IRON_BAR',displayName='Iron bar'}},1 end
app:OpenRenameQuery('1');appearance=app.appearanceEditor
appearance.spriteSlot.root.hooks[ui.Hook.ONCLICK]()
local picker=app.iconPicker
assert(picker ~= nil and app.iconPickerOwner == appearance)
picker:RunSearch('iron bar')
assert(#picker.hitTargets == 1 and picker.grid:GetSlot(1).object.id == 101)
local tooltip=picker.tooltips[1]
local tooltipRoot=tooltip.root
picker.hitTargets[1].hooks[ui.Hook.ONMOUSEOVER]()
assert(not tooltipRoot.hidden)
picker.hitTargets[1].hooks[ui.Hook.ONCLICK]()
assert(app.iconPicker == nil and tooltipRoot.destroyed and appearance.spriteObjectID == 101)
press(appearance.saveButton)
assert(app.queries:GetQuerySprite('1') == 101)
engine.Catalog.Find=find
-- New/edit query builders use the same icon slot, with a draft committed only on Save.
app:EditQuery('1')
local editor=app.editor
assert(editor.spriteObjectID == 101)
editor:SetSprite(105)
editor:Close()
assert(app.queries:GetQuerySprite('1') == 101,'Cancel keeps the saved icon')
app:EditQuery('1');editor=app.editor;editor:SetSprite(105)
assert(app.editorExt:Refresh());h:Tick(2)
assert(app.editor.spriteObjectID == 105,'a redraw preserves the icon draft')
press(app.editor.saveButton)
assert(app.queries:GetQuerySprite('1') == 105)

-- Folder chooser remains available when this PrettyUI has no submenu helper.
menu=menuOver('3');choose(menu,'Move to folder')
assert(app.folderDialog ~= nil)
assert(app.folderDialog.list:Click('1'))
assert(app.folderDialog == nil and app.queries:FolderOf('3') == '1')
menu=menuOver('3');choose(menu,'Remove from folder')
assert(app.queries:FolderOf('3') == nil)
-- When PrettyUI exposes its submenu helper, use exactly the Bank Tags structure.
local previousMiniMenu=prettyui.MiniMenu
prettyui.MiniMenu={AddSubmenu=function(native,label,children)
    native.children=children
    native:Add(label .. ' <col=ffffff><gt></col>',function() end)
end}
menu=menuOver('3')
assert(menu.children ~= nil and menu.children[#menu.children-1].label == 'Create new folder')
menu.open()
for _,child in ipairs(menu.children) do if child.label == 'Metal' then child.action() end end
h:Tick()
assert(app.queries:FolderOf('3') == '1')
menu=menuOver('3');menu.open()
for _,child in ipairs(menu.children) do if child.label == 'Create new folder' then child.action() end end
h:Tick()
assert(app.folderDialog ~= nil)
app.folderDialog.field:SetText('Sea');press(app.folderDialog.saveButton)
assert(app.queries:GetFolder(app.queries:FolderOf('3')).name == 'Sea')
prettyui.MiniMenu=previousMiniMenu

-- Delete is confirmed separately; removing a folder leaves its queries and their icons.
menu=menuOver('4');choose(menu,'Remove')
assert(app.deleteConfirm ~= nil and app.queries:Get('4') ~= nil)
press(app.deleteConfirm.cancelButton)
assert(app.deleteConfirm == nil and app.queries:Get('4') ~= nil)
menu=menuOver('4');choose(menu,'Remove');press(app.deleteConfirm.confirmButton)
assert(app.queries:Get('4') == nil and app.deleteConfirm == nil)
menu=menuOver('folder:1');choose(menu,'Ungroup folder')
assert(app.queries:GetFolder('1') == nil and app.queries:FolderOf('1') == nil)
assert(app.queries:GetQuerySprite('1') == 105)
-- Scale calibration and edge scrolling use the same Bank Tags geometry and gesture code.
Geometry=h.search.env.require('resources/search/geometry')
local first=row('2')
local x,y=Geometry.absolutePosition(first.root)
first.root.xyGlobal={x=x,y=y}
h.bankHost.mouse={x=(x+20)*1.25,y=(y+10)*1.25}
first.root.hooks[ui.Hook.ONMOUSEREPEAT](first.root,20,10)
local px,py=Geometry.interfaceMousePosition()
assert(math.abs(px-x-20)<0.001 and math.abs(py-y-10)<0.001)
h.bankHost.mouse={x=x+20,y=y+10}
Geometry.calibratePointer(first.root,20,10)
local oldListHeight=controls.list.root.height
controls.list:SetSize(width,64)
root=start('2');hold(root,62)
assert(controls.list.scrollY>0 and tree().gesture.row.root.height==64)
point(-100);root.hooks[ui.Hook.ONRELEASE]()
assert(tree().gesture==nil)
controls.list:SetSize(width,oldListHeight)
controls.list:SetScrollPosition(0)
app:Refresh()
-- Invalid icons cannot overwrite either a query or a folder's saved metadata.
local record=app.queries:Get('1')
assert(not app.queries:Save('1','Bad icon',record.query,record.builder,-1))
assert(app.queries:Get('1').name=='Bars renamed' and app.queries:GetQuerySprite('1')==105)
local seaID=app.queries:FolderOf('3')
assert(not app.queries:RenameFolder(seaID,'Bad folder',1.5))
assert(app.queries:GetFolder(seaID).name=='Sea')
-- Reload preserves names, icons, tree order and visual query metadata.
local expected=rows()
h.host:Reload('advancedbanksearch',{freshEnvironment=true});h:Tick(2)
app=h:App();tab=app.tab;controls=tab.controls
assert(rows():gsub(" %(%d+%)", ""):gsub("%*", "") == expected:gsub(" %(%d+%)", ""):gsub("%*", ""),rows())
assert(app.queries:GetQuerySprite('1') == 105 and app.queries:Get('1').builder.rules[1].field == 'name')
-- Bank close and unload retire rename windows, pickers, drags and listeners.
app:OpenRenameQuery('1');appearance=app.appearanceEditor
appearance.spriteSlot.root.hooks[ui.Hook.ONCLICK]();picker=app.iconPicker
app:OnBankClose()
assert(app.appearanceEditor == nil and app.iconPicker == nil and picker.window == nil)
root=start('1');hold(root,50);ghost=tree().gesture and tree().gesture.ghost
local context=tab.ctx;tab.callbacks.unmount()
assert(ghost == nil or ghost.destroyed)
tab.callbacks.mount(context)
controls=tab.controls
h.host:Unload('advancedbanksearch')
assert(h.menuSubscriptions.advancedbanksearch_menu == nil and h.menuOpenedSubscriptions.advancedbanksearch_menu == nil)
assert(h.bankHost:Listener('advancedbanksearch_menu_action') == nil)
h.host:Unload('bankcore')
print('query_folders_test: ok')
