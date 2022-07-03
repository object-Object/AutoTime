local sql = require("sqlite3")
local fs = require("fs")
local options = require("options")

local dbFilename = options.dbFilename or "bot.db";
local doInitialize = not fs.existsSync(dbFilename);

local conn = sql.open(dbFilename)
if doInitialize then
    local setup = fs.readFileSync("setup.sql")
    assert(setup and type(setup) == "string" and setup ~= "", "Failed to read setup.sql")
    conn:exec(setup)
end

local stmts = {
    getUserTimezone = conn:prepare("SELECT timezone FROM users WHERE user_id = ?"),
    setUserTimezone = conn:prepare("INSERT INTO users (user_id, timezone) VALUES (?001, ?002) ON CONFLICT (user_id) DO UPDATE SET timezone = ?002"),
    clearUserTimezone = conn:prepare("UPDATE users SET timezone = NULL WHERE user_id = ?"),
    userExists = conn:prepare("SELECT EXISTS(SELECT 1 FROM users WHERE user_id = ?)"),
    insertUser = conn:prepare("INSERT INTO users (user_id, timezone) VALUES (?, ?)"),
}

local db = {}

---@param id string
---@return string? timezone
db.getUserTimezone = function(id)
    local resultset = stmts.getUserTimezone:reset():bind(id):resultset()
    return resultset and resultset.timezone[1]
end

---@param id string
---@param timezone string
db.setUserTimezone = function(id, timezone)
    stmts.setUserTimezone:reset():bind(id, timezone):step()
end

---@param id string
db.clearUserTimezone = function(id)
    stmts.clearUserTimezone:reset():bind(id):step()
end

---@param id string
---@return boolean
db.userExists = function(id)
    return stmts.userExists:reset():bind(id):step()[1] == 1LL
end

---@param id string
---@param timezone string
db.insertUser = function(id, timezone)
    stmts.insertUser:reset():bind(id, timezone):step()
end

return db