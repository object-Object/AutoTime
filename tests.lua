local tz = require("tz")
local tzTime = tz.time
tz.time = function(date, timezone)
    date.year = 2022
    date.month = 7
    date.day = 2
    return tzTime(date, timezone)
end

local parser = require("parser")

local allPassed = true
local function testCase(content, expected, ignoreLineTimezones)
    local result = parser.parseTimes(content, "America/Toronto", ignoreLineTimezones)

    if expected ~= result then
        allPassed = false
        local info = debug.getinfo(2)
        print(string.format(
            "FAILED: %s:%d\nInput: %s\nExpected: %s\nReceived: %s\n",
            info.short_src,
            info.currentline,
            content,
            expected,
            result
        ))
    end
end

testCase("12:34:56 pm", "12:34:56 pm → <t:1656779696:T>")
testCase("2:34:56p.m.", "2:34:56p.m. → <t:1656786896:T>")
testCase("9:29   pm", "9:29   pm → <t:1656811740:t>")
testCase("12:34:56", "12:34:56 → <t:1656779696:T>")
testCase("2:34:56", "2:34:56 → <t:1656743696:T>")
testCase("22:34", "22:34 → <t:1656815640:t>")
testCase("9:29 pm", "9:29 pm → <t:1656811740:t>")
testCase("02:03", "02:03 → <t:1656741780:t>")
testCase("2 pm", "2 pm → <t:1656784800:t>")
testCase("12 pm", "12 pm → <t:1656777600:t>")
testCase("1 AM", "1 AM → <t:1656738000:t>")
testCase("1 PM", "1 PM → <t:1656781200:t>")
testCase("1 Am", "1 Am → <t:1656738000:t>")
testCase("1 Pm", "1 Pm → <t:1656781200:t>")
testCase("1 aM", "1 aM → <t:1656738000:t>")
testCase("1 pM", "1 pM → <t:1656781200:t>")
testCase("1:00 AM", "1:00 AM → <t:1656738000:t>")
testCase("1:00 PM", "1:00 PM → <t:1656781200:t>")
testCase("1:00 Am", "1:00 Am → <t:1656738000:t>")
testCase("1:00 Pm", "1:00 Pm → <t:1656781200:t>")
testCase("1:00 aM", "1:00 aM → <t:1656738000:t>")
testCase("1:00 pM", "1:00 pM → <t:1656781200:t>")
testCase("05 am", "05 am → <t:1656752400:t>")
testCase("22:34:", "22:34 → <t:1656815640:t>")
testCase("12:00 am:", "12:00 am → <t:1656734400:t>")
testCase("8am 8pm 8am", "8am → <t:1656763200:t>\n8pm → <t:1656806400:t>\n8am → <t:1656763200:t>")
testCase("12:00-14:00", "12:00 → <t:1656777600:t>\n14:00 → <t:1656784800:t>")
testCase("8:00:9:00", "8:00 → <t:1656763200:t>\n9:00 → <t:1656766800:t>")
testCase(" 12 pm America/Toronto foo ", "12 pm America/Toronto → <t:1656777600:t>")
testCase("12:00 pm US/Central", "12:00 pm US/Central → <t:1656781200:t>")
testCase("12 pm a8a", "12 pm → <t:1656777600:t>")
testCase("22:34 US/Central", "22:34 US/Central → <t:1656819240:t>")
testCase("22:34 us/central", "22:34 us/central → <t:1656819240:t>")
testCase("22:34 us/CENTRAL", "22:34 us/CENTRAL → <t:1656819240:t>")
testCase("22:34 US/Central", "22:34 → <t:1656815640:t>", true)
testCase("22:34 EST", "22:34 EST (assuming US/Eastern) → <t:1656815640:t>")
testCase("22:34 cst", "22:34 cst (assuming US/Central) → <t:1656819240:t>")
testCase("22:34 Cdt", "22:34 Cdt (assuming US/Central) → <t:1656819240:t>")
testCase("22:34 CST", "22:34 → <t:1656815640:t>", true)

testCase("22:34 a.m.", false)
testCase("23 pm", false)
testCase("2: am", false)
testCase("2 amp", false)
testCase("2:4", false)
testCase("8am8pm", false)
testCase("0am", false)
testCase("0pm", false)
testCase("13am", false)
testCase("13pm", false)
testCase("12\npm", false)

if allPassed then
    print("All tests passed.")
end