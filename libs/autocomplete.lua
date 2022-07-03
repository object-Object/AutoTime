---@type discordia
local discordia = require("discordia")
discordia.extensions()

local function inverted(tbl)
    local output = {}
    for _, v in pairs(tbl) do
        output[v] = true
    end
    return output
end

local function filtered(tbl, predicate)
    local output = {}
    for _, v in ipairs(tbl) do
        if predicate(v) then
            table.insert(output, v)
        end
    end
    return output
end

-- easily confused timezones that don't need to be in the list
local ignoreTimezones = inverted{
    "CET",
    "CST6CDT",
    "EET",
    "EST",
    "EST5EDT",
    "Factory",
    "HST",
    "MET",
    "MST",
    "MST7MDT",
    "PST8PDT",
    "WET",
}

local handle = io.popen("awk '/^Z/ { print $2 }; /^L/ { print $3 }' /usr/share/zoneinfo/tzdata.zi")
local allTimezones = assert(handle, "Failed to get list of timezones"):read("*a"):gsub("\n$", "", nil):split("\n")
allTimezones = filtered(allTimezones, function(timezone)
    return not (timezone:startswith("Etc/") or timezone:startswith("SystemV/") or ignoreTimezones[timezone])
end)
---@diagnostic disable-next-line: need-check-nil
handle:close()

local prefixesMap, noPrefixes = {}, {}
for _, timezone in pairs(allTimezones) do
    local prefix = timezone:match("(.-)/")
    if prefix then
        prefixesMap[prefix] = true
    else
        table.insert(noPrefixes, timezone)
    end
end
local prefixes = {}
for prefix in pairs(prefixesMap) do
    table.insert(prefixes, prefix)
end

table.sort(allTimezones)
table.sort(prefixes)
table.sort(noPrefixes)

---@param values string[]
---@return table
local function buildSearch(values)
    local output = {}
    for _, value in ipairs(values) do
        local lowerValue = value:lower()
        local chars = value:split()

        for i1 = 1, #chars do
            for i2 = i1, #chars do
                local acc = lowerValue:sub(i1, i2)
                if not output[acc] then
                    output[acc] = {}
                end
                table.insert(output[acc], value)
            end
        end
    end
    return output
end

local prefixSearch = buildSearch(prefixes)
local noPrefixSearch = buildSearch(noPrefixes)
local fullSearch = buildSearch(allTimezones)

---@param words string[]
---@param maxValues number
---@param values string[]
---@param isPrefix boolean
local function addValues(words, maxValues, values, isPrefix)
    for _, result in ipairs(values) do
        if #words == maxValues then break end
        table.insert(words, result..(isPrefix and "/..." or ""))
    end
end

local autocomplete = {}

autocomplete.validTimezones = inverted(allTimezones)

autocomplete.fromLowercase = {}
for _, timezone in pairs(allTimezones) do
    autocomplete.fromLowercase[timezone:lower()] = timezone
end

---@param value string
---@param maxValues number?
---@return string[]
autocomplete.search = function(value, maxValues)
    maxValues = maxValues or math.huge
    value = value:lower()
    local prefixResult = prefixSearch[value] or {}
    local noPrefixResult = noPrefixSearch[value] or {}
    local fullResult = fullSearch[value] or {}

    local words = {}

    if #value == 0 then
        addValues(words, maxValues, prefixes, true)
        addValues(words, maxValues, noPrefixes, false)
    elseif not value:match("/") and #prefixResult + #noPrefixResult >= 25 then
        addValues(words, maxValues, prefixResult, true)
        addValues(words, maxValues, noPrefixResult, false)
    end
    if value:match("/") or #words < maxValues then
        addValues(words, maxValues, fullResult, false)
    end

    return words
end

return autocomplete
