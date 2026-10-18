-- Describe how the replacement bank search page is titled and built. The bank passes
-- itself; the search field and its text belong to its attached features

local titleCase = require("lib/core/text").titleCase

local NameSearchPage = {
    -- Search results are generated, so players cannot remove their items
    isMembershipEditable = false,
}

-- Claim the replacement search's transient selection
function NameSearchPage.OwnsSelection(layout, selection)
    return layout.features:IsNameSearchSelection(selection)
end

-- Show the selection name as before; no screen displays it yet
function NameSearchPage.Title(_, selection)
    return titleCase(selection)
end

-- Rank bank items against the search field's current text
function NameSearchPage.Apply(layout, selection)
    local features = layout.features
    local plan = runeql.Compile(features.bankSearchQuery)
    -- Text RuneQL cannot compile matches nothing rather than every item
    local score = plan ~= nil and features:BankQueryScorer(plan, selection)
        or function() return nil end
    return layout.pageState:ApplySearch(
        features.bankSearchQuery,
        function(objectID) return features:BankSearchObjectName(objectID) end,
        score
    )
end

return NameSearchPage
