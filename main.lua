---@type discordia
local discordia = require("discordia")
discordia.extensions()
local dcmd = require("discordia-commands")
local tz = require("tz")
local options = require("options")
local db = require("db")
local autocomplete = require("autocomplete")
local parser = require("parser")

local clock = discordia.Clock()
local client = discordia.Client():useApplicationCommands()
---@diagnostic disable-next-line: undefined-field
local commandType = discordia.enums.appCommandType
---@diagnostic disable-next-line: undefined-field
local optionType = discordia.enums.appCommandOptionType

local colors = {
    success = 0x00ff00,
    failure = 0xff0000,
    info = 0x0080ff,
}

---@type table<string, string | false>
local timeMessages = {}


---@param description string
---@param color number
---@param isEphemeral boolean?
local function replyTo(interaction, description, color, isEphemeral)
    if isEphemeral == nil then
        isEphemeral = true
    end
    interaction:reply({
        embed = {
            description = description,
            color = color,
        }
    }, isEphemeral)
end

---@param timezone string
local function validateTimezoneOrReply(timezone, interaction)
    if not parser.validateTimezone(timezone) then
        replyTo(interaction, "`"..timezone.."` is not a valid timezone.", colors.failure)
        return false
    end
    return true
end

---@param message Message
local function replyWithTimestamps(message)
    local timezone = db.getUserTimezone(message.author.id)
    if not timezone then return end

    local lines = parser.parseTimes(message.content, timezone)
    if #lines == 0 then return end

    local reply = message:reply{
        content = table.concat(lines, "\n"),
        reference = message and {
            message = message,
            mention = false
        }
    }
    reply:addReaction("❌")
    timeMessages[message.id] = reply.id

    local userReacted = client:waitFor("reactionAdd", 60000, function(r, u)
        return u == message.author.id and r.message == reply and r.emojiHash == "❌"
    end)

    if userReacted then
        timeMessages[message.id] = false -- false means deleted or timed out, nil means never replied to
        reply:delete()
    else
        reply:removeReaction("❌") -- if the message was deleted during the timeout, we'll just get a 404 here, which is fine
    end
end

---@param guild Guild
---@param err string?
local function logError(guild, err)
    print("Bot crashed!\n"..err)
    ---@diagnostic disable-next-line: undefined-field
	client._api:executeWebhook(options.errorWebhook.id, options.errorWebhook.token, {
		embeds = {{
			title = "Bot crashed!",
			description = "```\n"..err.."```",
			color = colors.failure,
			timestamp = discordia.Date():toISO('T', 'Z'),
			footer = guild and {
				text = "Guild: "..guild.name.." ("..guild.id..")"
			}
		}
	}})
end

---@param timezone string
---@return string
local function getTimezoneCheckString(timezone)
    local year = os.date("*t").year

    local janDate = { year = year, month = 1, day = 10, hour = 6, min = 0, sec = 0 }
    local julDate = { year = year, month = 7, day = 10, hour = 6, min = 0, sec = 0 }

    local janTimestamp = tz.time(janDate, timezone)
    local julTimestamp = tz.time(julDate, timezone)

    local janOffset = tz.type(janTimestamp, timezone)
    local julOffset = tz.type(julTimestamp, timezone)

    local observesDSTMessage
    if janOffset ~= julOffset then
        observesDSTMessage = "This timezone **observes Daylight Savings Time** in the summer. If only one of the above timestamps is correct, you probably need to choose a different timezone that has the same UTC offset but does not observe DST in the summer."
    else
        observesDSTMessage = "This timezone **does not observe Daylight Savings Time** in the summer. If only one of the above timestamps is correct, you probably need to choose a different timezone that has the same UTC offset but observes DST in the summer."
    end

    return ([[If this timezone is correct, both of these timestamps should say **6:00 am**:
<t:%d:f> (UTC%+g)
<t:%d:f> (UTC%+g)
%s]]):format(janTimestamp, janOffset/3600, julTimestamp, julOffset/3600, observesDSTMessage)
end

local function setGame()
    client:setGame{
        name = "the clock",
        type = 3, -- watching
    }
end

---@param guild Guild
local function initializeCommands(guild)
    local command, err = client:createGuildApplicationCommand(guild.id, {
        type = commandType.chatInput,
        name = "timezone",
        description = ".",
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
                description = "Display all available timezones from the IANA database (eg. US/Eastern)",
            },
            {
                type = optionType.subCommand,
                name = "set",
                description = "Set your timezone so the bot knows how to make timestamps for you",
                options = {
                    {
                        type = optionType.string,
                        name = "timezone",
                        description = "Your IANA timezone (eg. US/Eastern) — CASE SENSITIVE!",
                        required = true,
                        autocomplete = true,
                    },
                },
            },
        },
    })
    if not command then logError(guild, err) end

    command, err = client:createGuildApplicationCommand(guild.id, {
        type = commandType.chatInput,
        name = "time",
        description = ".",
        options = {
            {
                type = optionType.subCommand,
                name = "from",
                description = "Convert a time from a specific IANA timezone",
                options = {
                    {
                        type = optionType.string,
                        name = "timezone",
                        description = "The desired IANA timezone (eg. US/Eastern) — CASE SENSITIVE!",
                        required = true,
                        autocomplete = true,
                    },
                    {
                        type = optionType.string,
                        name = "time",
                        description = "The time to convert (eg. 12:00 pm)",
                        required = true,
                    },
                },
            },
            {
                type = optionType.subCommand,
                name = "from_user",
                description = "Convert a time from another user's timezone",
                options = {
                    {
                        type = optionType.user,
                        name = "user",
                        description = "The user to use the timezone of",
                        required = true,
                    },
                    {
                        type = optionType.string,
                        name = "time",
                        description = "The time to convert (eg. 12:00 pm)",
                        required = true,
                    },
                },
            },
        },
    })
    if not command then logError(guild, err) end
end


clock:on("hour", function()
    setGame()
end)

client:on("ready", function()
    setGame()
    for guild in client.guilds:iter() do
        initializeCommands(guild)
    end
end)

client:on("guildCreate", function(guild)
    local success, err = xpcall(initializeCommands, debug.traceback, guild)
    if not success then logError(guild, err) end
end)

client:on("slashCommand", function(interaction, command, args)
    local success, err = xpcall(function()
        if command.name == "timezone" then
            if args.get then
                local timezone = db.getUserTimezone(interaction.user.id)
                if timezone then
                    replyTo(interaction, "Your timezone is `"..timezone.."`. "..getTimezoneCheckString(timezone), colors.info)
                else
                    replyTo(interaction, "Your timezone is not set.", colors.info)
                end
            elseif args.clear then
                local timezone = db.getUserTimezone(interaction.user.id)
                if timezone then
                    db.clearUserTimezone(interaction.user.id)
                    replyTo(interaction, "Cleared your timezone (it was `"..timezone.."`).", colors.success)
                else
                    replyTo(interaction, "Your timezone is not set.", colors.failure)
                end
            elseif args.list then
                replyTo(interaction, "To easily see your IANA timezone name, visit https://time.is/, click the location name in the top left, and scroll down to the box that starts with \"The IANA time zone identifier\".\n\nSee [this Wikipedia page](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) for a list of valid IANA timezones. The value in the \"TZ database name\" column is what you should use. Read the notes! Some places don't do Daylight Savings Time (eg. `US/Arizona` vs `US/Mountain`). Also, some of the more confusing timezones on this list have been removed from the bot.", colors.info)
            elseif args.set then
                local newTimezone = args.set.timezone
                local oldTimezone = db.getUserTimezone(interaction.user.id)

                if newTimezone == oldTimezone then
                    replyTo(interaction, "Your timezone is already `"..newTimezone.."`. "..getTimezoneCheckString(newTimezone), colors.failure)
                    return
                end

                if not validateTimezoneOrReply(newTimezone, interaction) then return end

                db.setUserTimezone(interaction.user.id, newTimezone)
                replyTo(interaction, "Your timezone is now `"..newTimezone.."`. "..getTimezoneCheckString(newTimezone), colors.success)
            end
        elseif command.name == "time" then
            if args.from then
                local timezone = args.from.timezone
                local time = args.from.time

                if not validateTimezoneOrReply(timezone, interaction) then return end

                local lines = parser.parseTimes(time, timezone, true)
                if #lines > 0 then
                    replyTo(interaction, "Using the timezone `"..timezone.."`:\n"..table.concat(lines, "\n"), colors.success, false)
                else
                    replyTo(interaction, "`"..args.from.time.."` does not contain a valid time.", colors.failure)
                end
            elseif args.from_user then
                local user = args.from_user.user
                local timezone = db.getUserTimezone(user.id)
                local time = args.from_user.time

                if not timezone then
                    replyTo(interaction, user.mentionString.." does not have a timezone set.", colors.failure)
                    return
                end

                if not validateTimezoneOrReply(timezone, interaction) then return end

                local lines = parser.parseTimes(time, timezone, true)
                if #lines > 0 then
                    replyTo(interaction, "Using "..user.mentionString.."'s timezone:\n"..table.concat(lines, "\n"), colors.success, false)
                else
                    replyTo(interaction, "`"..args.from_user.time.."` does not contain a valid time.", colors.failure)
                end
            end
        end
    end, debug.traceback)
    if not success then
        replyTo(interaction, "The bot encountered an error while trying to process your command. This error has been automatically reported, and we're looking into it. Sorry for the inconvenience!", colors.failure)
        logError(interaction.guild, err)
    end
end)

client:on("slashCommandAutocomplete", function(interaction, command, focusedOption, args)
    local success, err = xpcall(function()
        if focusedOption.name == "timezone" then
            local words = autocomplete.search(focusedOption.value, 25)
            local results = {}
            for _, word in ipairs(words) do
                table.insert(results, {name = word, value = word})
            end
            interaction:autocomplete(results)
        end
    end, debug.traceback)
    if not success then logError(interaction.guild, err) end
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
        if replyId == false then return end -- they hit the x, don't send a new message
        
        local reply = message.channel:getMessage(replyId)
        if not reply then -- no time message exists, send a new one as if it were a new message
            replyWithTimestamps(message)
        else
            local timezone = db.getUserTimezone(message.author.id)
            if not timezone then return end

            local lines = parser.parseTimes(message.content, timezone)
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

---@param message Message
client:on("messageDelete", function(message)
    local success, err = xpcall(function()
        local replyId = timeMessages[message.id]
        if replyId then
            timeMessages[message.id] = nil

            local reply = message.channel:getMessage(replyId)
            if reply then
                reply:delete()
            end
        end
    end, debug.traceback)
    if not success then logError(message.guild, err) end
end)


clock:start()
client:run("Bot "..options.token)
