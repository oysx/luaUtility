
------- AGC Module Start -------
agc.variable = {
    -- runtime parameters
    count = 0,
    rate = 0,
    state = -1,
    upgrade = 0,

    -- configuration
    cfg_interval = 10,
    cfg_rate_upper = 1000,
    cfg_rate_lower = 300,

    cfg_upgrade_count = 10,
    cfg_level_default = 2,
}

local savedCount = nil
function agc.callback()
    if savedCount == nil then
        savedCount = agc.variable.count
    else
        agc.variable.rate = (agc.variable.count - savedCount) / agc.variable.cfg_interval
    end

    savedCount = agc.variable.count

    if agc.variable.rate > agc.variable.cfg_rate_upper then
        if agc.variable.state < 1 then
            agc.variable.state = 1
        end

        agc.variable.upgrade = agc.variable.upgrade + 1
        if agc.variable.upgrade > agc.variable.cfg_upgrade_count then
            agc.variable.upgrade = 0
            agc.variable.state = agc.variable.state + 1
        end
    elseif agc.variable.rate < agc.variable.cfg_rate_lower then
        agc.variable.state = -1
        agc.variable.upgrade = 0
    end

    local ok, err = ngx.timer.at(agc.variable.cfg_interval, agc.callback)
    if not ok then
        ngx_log(log_ERR, "failed to create timer: ", err)
    end

    return result
end

function agc.init()
    local ok, err = ngx.timer.at(agc.variable.cfg_interval, agc.callback)
    if not ok then
        ngx_log(log_ERR, "failed to create timer: ", err)
        return
    end
end

function agc.record()
    agc.variable.count = agc.variable.count + 1
end

local state = nil
function agc.fsm()
    if state == nil then
        state = agc.variable.state
    end

    if state == agc.variable.state then
        return 0
    end

    state = agc.variable.state
    return state
end

function agc.action(id)
    local max = agc.variable.cfg_level_default
    local handler = require(pathinfo.custom(id))
    if type(handler.get_max_level) == "function" then
        max = handler.get_max_level()
    end

    local level = configinfo.get_level(id)
    local dir = agc.fsm()
    if dir > 0 then
        level = level + 1
        ngx_log(log_ERR, "inc lvl to "..tostring(level))
    elseif dir < 0 then
        level = agc.variable.cfg_level_default
        -- level = level - 1
        ngx_log(log_ERR, "dec lvl to "..tostring(level))
    end

    if level > max then
        level = max
    elseif level < agc.variable.cfg_level_default then
        level = agc.variable.cfg_level_default
    end

    configinfo.set_level(id, level)
end
------- AGC Module End -------
