local rex = require("rex")
local tz = require("tz")
local autocomplete = require("autocomplete")

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

        local uppercaseLineTimezone = lineTimezone and autocomplete.fromLowercase[lineTimezone:lower()]
        if uppercaseLineTimezone then -- don't clobber lineTimezone if it's not in fromLowercase
            lineTimezone = uppercaseLineTimezone
        end

        if lineTimezone and (ignoreLineTimezones or not parser.validateTimezone(lineTimezone)) then
            lineTimezone = nil
            original = original:gsub(" +%S+$", "")
        end

        if ampm and (hour < 1 or hour > 12) then
            goto continue
        elseif (ampm == "a" or ampm == "A") and hour == 12 then -- if ampm is missing then it's nil, which is valid to compare
            hour = 0
        elseif (ampm == "p" or ampm == "P") and hour ~= 12 then
            hour = hour + 12
        end

        if hour < 0 or hour > 23
        or min  < 0 or min  > 59
        or sec  < 0 or sec  > 59 then
            goto continue
        end

        local date = tz.date("*t", nil, lineTimezone or timezone)
        date.hour = hour
        date.min = min
        date.sec = sec

        local timestamp = tz.time(date, lineTimezone or timezone)
        local flag = showSeconds and "T" or "t"
        table.insert(lines, string.format("%s → <t:%d:%s>", original, timestamp, flag))

        ::continue::
    end
    return lines
end

return parser
