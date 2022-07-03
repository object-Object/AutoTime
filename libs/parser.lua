local rex = require("rex")
local tz = require("tz")
local autocomplete = require("autocomplete")

local f = string.format

local parser = {}

---@param timezone string
parser.validateTimezone = function(timezone)
    return autocomplete.validTimezones[timezone] and pcall(tz.type, nil, timezone)
end

---@param content string
---@param timezone string
---@param ignoreLineTimezones boolean?
---@return string[]
parser.parseTimes = function(content, timezone, ignoreLineTimezones)
    local lines = {}
    local patt = "(?<!\\w)((?:(?:([012]?\\d):(\\d\\d)(?::(\\d\\d))? *(?:([apAP])\\.?[mM]\\.?)?)|(?:([01]?\\d) *([apAP])\\.?[mM]\\.?))(?: +([a-zA-Z\\/\\_]+))?)(?!\\w)"
    for original, hour, min, sec, ampm, hourAlt, ampmAlt, lineTimezone in rex.gmatch(content, patt, "m") do
        local showSeconds = not not sec
        
        hour = tonumber(hour) or tonumber(hourAlt) -- if hour is missing, the regex doesn't match
        min = tonumber(min) or 0
        sec = tonumber(sec) or 0
        ampm = ampm or ampmAlt
        
        local aliasTimezone
        local tzTimezone = timezone
        if lineTimezone then
            if not ignoreLineTimezones then
                local uppercaseTimezone = autocomplete.fromLowercase[lineTimezone:lower()]
                aliasTimezone = autocomplete.aliases[lineTimezone:lower()]
                tzTimezone = aliasTimezone or uppercaseTimezone or lineTimezone
            end

            if ignoreLineTimezones or not parser.validateTimezone(tzTimezone) then
                aliasTimezone = nil
                tzTimezone = timezone
                original = original:gsub(" +%S+$", "")
            end
        end

        if ampm then
            if hour < 1 or hour > 12 then
                goto continue
            elseif ampm:lower() == "a" and hour == 12 then -- if ampm is missing then it's nil, which is valid to compare
                hour = 0
            elseif ampm:lower() == "p" and hour ~= 12 then
                hour = hour + 12
            end
        end

        if hour < 0 or hour > 23
        or min  < 0 or min  > 59
        or sec  < 0 or sec  > 59 then
            goto continue
        end

        local date = tz.date("*t", nil, tzTimezone)
        date.hour = hour
        date.min = min
        date.sec = sec

        local timestamp = tz.time(date, tzTimezone)
        local flag = showSeconds and "T" or "t"
        table.insert(lines, f(
            "%s%s → <t:%d:%s>",
            original,
            aliasTimezone and f(" (assuming %s)", aliasTimezone) or "",
            timestamp,
            flag
        ))

        ::continue::
    end
    return lines
end

return parser
