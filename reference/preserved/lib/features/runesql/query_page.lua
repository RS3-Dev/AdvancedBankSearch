-- Describe how a saved RuneQL query page is titled, built, counted, and recovered. The
-- bank passes itself; the saved queries and their counts belong to its attached features

local QueryStore = require("lib/features/runesql/query_store")
local debugLog = require("lib/core/debug_log").Write

local INVALID_QUERY_TEXT = "__bankutils_invalid_runesql_query__"

local QueryPage = {
    -- Query results are generated, so players cannot remove their items
    isMembershipEditable = false,
    -- A vanished hovered stack keeps the query's membership and rebuilds only input
    failedRebindRecovery = "recreate_input",
}

-- Claim saved-query selection IDs, whether or not the record still exists
function QueryPage.OwnsSelection(layout, selection)
    return layout.features:IsRuneQuerySelection(selection)
end

-- Show the saved query's name, or a generic name once it is deleted
function QueryPage.Title(layout, selection)
    local record = layout.features.queryStore:GetBySelection(selection)
    return record ~= nil and record.name or "RuneQL"
end

-- Rank bank stacks against the saved query, leaving placeholders out
function QueryPage.Apply(layout, selection)
    local features = layout.features
    local record = features.queryStore:GetBySelection(selection)
    if record == nil then return layout.pageState:Apply(nil) end
    local resolveName = function(objectID) return features:BankSearchObjectName(objectID) end
    local plan, reason = runeql.Compile(record.query)
    if plan == nil then
        debugLog("BankUtils could not run RuneQL query ", record.name,
            ": ", tostring(reason))
        return layout.pageState:ApplySearch(
            INVALID_QUERY_TEXT,
            resolveName,
            function() return nil end
        )
    end
    return layout.pageState:ApplySearch(
        record.query,
        resolveName,
        features:BankQueryScorer(plan, selection),
        { excludePlaceholders = true }
    )
end

-- Remember the match count the sidebar shows beside the query
function QueryPage.RecordMatchCount(layout, selection, matchCount)
    local queryID = QueryStore.QueryIDFromSelection(selection)
    if queryID ~= nil then layout.features.runeQueryCounts[queryID] = matchCount end
end

return QueryPage
