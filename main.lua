---@type discordia
local discordia = require("discordia")
local dcmd = require("discordia-commands")
local rex = require("rex")
local tz = require("tz")
local options = require("options")
local db = require("db")
local autocomplete = require("autocomplete")

local client = discordia.Client():useApplicationCommands()
---@diagnostic disable-next-line: undefined-field
local commandType = discordia.enums.appCommandType
---@diagnostic disable-next-line: undefined-field
local optionType = discordia.enums.appCommandOptionType

---@type table<string, string>
local timeMessages = {}


---@param content string
---@param timezone string
---@return string[]
local function parseTimes(content, timezone)
    local lines = {}
    local patt = "(?:\\W|^)((?:([012]?\\d):(\\d\\d)(?::(\\d\\d))?\\s*(?:([ap])\\.?m\\.?)?)|(?:([01]?\\d)\\s*([ap])\\.?m\\.?))(?:\\W|$)"
    for original, hour, min, sec, ampm, hourAlt, ampmAlt in rex.gmatch(content, patt, "m") do
        local showSeconds = not not sec

        hour = tonumber(hour) or tonumber(hourAlt)
        min = tonumber(min) or 0
        sec = tonumber(sec) or 0
        ampm = ampm or ampmAlt

        if ampm then
            if ampm == "a" and hour == 12 then
                hour = 0
            elseif ampm == "p" and hour ~= 12 then
                hour = hour + 12
            end
        end

        if hour < 0 or hour > 23
        or min  < 0 or min  > 59
        or sec  < 0 or sec  > 59 then
            goto continue
        end

        local date = tz.date("*t", nil, timezone)
        date.hour = hour
        date.min = min
        date.sec = sec

        local timestamp = tz.time(date, timezone)
        local flag = showSeconds and "T" or "t"
        table.insert(lines, string.format("%s → <t:%d:%s>", original, timestamp, flag))

        ::continue::
    end
    return lines
end

---@param message Message
local function replyWithTimestamps(message)
    local timezone = db.getUserTimezone(message.author.id)
    if not timezone then return end

    local lines = parseTimes(message.content:lower(), timezone)
    if #lines == 0 then return end

    local reply = message:reply{
        content = table.concat(lines, "\n"),
        reference = {
            message = message,
            mention = false
        }
    }
    reply:addReaction("❌")
    timeMessages[message.id] = reply.id

    local userReacted = message.client:waitFor("reactionAdd", 60000, function(r, u)
        return u == message.author.id and r.message == reply and r.emojiHash == "❌"
    end)

    if userReacted then
        timeMessages[message.id] = false -- false means deleted or timed out, nil means never replied to
        reply:delete()
    else
        reply:removeReaction("❌")
    end
end

---@param guild Guild
---@param err string
local function logError(guild, err)
    print("Bot crashed!\n"..err)
    ---@diagnostic disable-next-line: undefined-field
	client._api:executeWebhook(options.errorWebhook.id, options.errorWebhook.token, {
		embeds = {{
			title = "Bot crashed!",
			description = "```\n"..err.."```",
			color = discordia.Color.fromHex("ff0000").value,
			timestamp = discordia.Date():toISO('T', 'Z'),
			footer = {
				text = "Guild: "..guild.name.." ("..guild.id..")"
			}
		}
	}})
end

local function getTimezoneCheckString(timezone)
    local date = tz.date("*t", nil, timezone)
    date.hour = 6
    date.min = 0
    date.sec = 0
    local timestamp = tz.time(date, timezone)
    return "If this is the right timezone, this should say 6:00 am: <t:"..timestamp..":t>"
end


client:on("ready", function()
    for guild in client.guilds:iter() do
        local command, err = client:createGuildApplicationCommand(guild.id, {
            type = commandType.chatInput,
            name = "timezone",
            description = "Get, set, or clear your timezone, or see a list of choices",
            options = {
                {
                    type = optionType.subCommand,
                    name = "get",
                    description = "Display your current timezone",
                },
                {
                    type = optionType.subCommand,
                    name = "clear",
                    description = "Clear your timezone so the bot stops sending timestamps for you",
                },
                {
                    type = optionType.subCommand,
                    name = "list",
                    description = "Display all available timezones from the IANA / tzdata / zoneinfo database (eg. America/Toronto)",
                },
                {
                    type = optionType.subCommand,
                    name = "set",
                    description = "Set your timezone so the bot knows how to make timestamps for you",
                    options = {
                        {
                            type = optionType.string,
                            name = "timezone",
                            description = "Your IANA / tzdata / zoneinfo timezone (eg. America/Toronto) — CASE SENSITIVE!",
                            required = true,
                            autocomplete = true,
                        },
                    },
                },
            },
        })
        if not command then print(err) end
    end
end)

client:on("slashCommand", function(interaction, command, args)
    if command.name == "timezone" then
        if args.get then
            local timezone = db.getUserTimezone(interaction.user.id)
            if timezone then
                interaction:reply("Your timezone is `"..timezone.."`."..getTimezoneCheckString(timezone), true)
            else
                interaction:reply("Your timezone is not set.", true)
            end
        elseif args.clear then
            local timezone = db.getUserTimezone(interaction.user.id)
            if timezone then
                db.clearUserTimezone(interaction.user.id)
                interaction:reply("Cleared your timezone (it was `"..timezone.."`).", true)
            else
                interaction:reply("Your timezone is not set.", true)
            end
        elseif args.list then
            interaction:reply("See <https://en.wikipedia.org/wiki/List_of_tz_database_time_zones> for a list of valid IANA time zones. The value in the `TZ database name` column is what you should use.", true)
        elseif args.set then
            local timezone = args.set.iana.timezone
            local isValid = pcall(tz.type, nil, timezone)
            if isValid then
                db.setUserTimezone(interaction.user.id, timezone)
                interaction:reply("Your timezone is now `"..timezone.."`."..getTimezoneCheckString(timezone), true)
            else
                interaction:reply("`"..timezone.."` is not a valid timezone.", true)
            end
        end
    end
end)

client:on("slashCommandAutocomplete", function(interaction, command, focusedOption, args)
    if command.name == "timezone" and args.set then
        local words = autocomplete.search(focusedOption.value, 25)
        local results = {}
        for _, word in ipairs(words) do
            table.insert(results, {name = word, value = word})
        end
        interaction:autocomplete(results)
    end
end)

---@param message Message
client:on("messageCreate", function(message)
    local success, err = xpcall(replyWithTimestamps, debug.traceback, message)
    if not success then logError(message.guild, err) end
end)

---@param message Message
client:on("messageUpdate", function(message)
    local success, err = xpcall(function()
        local replyId = timeMessages[message.id]
        local reply = replyId and message.channel:getMessage(replyId)
    
        if reply == false then -- user deleted with x, don't send another time message
            return
        elseif reply == nil then -- no time message exists, send a new one as if it were a new message
            replyWithTimestamps(message)
        else
            local timezone = db.getUserTimezone(message.author.id)
            if not timezone then return end
    
            local lines = parseTimes(message.content:lower(), timezone)
            if #lines == 0 then
                timeMessages[message.id] = nil -- allow sending a new message in the future
                reply:delete()
            else
                reply:setContent(table.concat(lines, "\n"))
            end
        end
    end, debug.traceback)
    if not success then logError(message.guild, err) end
end)


client:run("Bot "..options.token)