------- Stepping Module Start -------
stepping.config = {}
ngx.INFO = ngx.DEBUG
function stepping.register(key, cfg)
    if stepping.config[key] then
        return
    end

    -- cfg format: {tick:"minute/hour", level:[level1_count, level2_count, level3_count, ......]}
    stepping.config[key] = cfg
end

function stepping.tick(key, cur, data)
    -- structure {delta=60, tick=xxxx, unit={}, history=[]}

    local cfg = stepping.config[key]
    if not cfg then
        return
    end

    local time = ngx.time()
    local delimiter = cur.tick

    local delta = 0
    if type(delimiter) ~= "number" then
        delta = tonumber(os.date("%S", time))

        if cfg.tick == "minute" then
            cur.delta = 60
        elseif cfg.tick == "hour" then
            cur.delta = 3600
            delta = tonumber(os.date("%M", time)) * 60 + delta
        else
            ngx.log(log_ERR, "Invalid config for stepping")
            return
        end

        cur.tick = time - delta

        -- init container
        cur.unit = {}
        cur.history = {}
        for i=1,#cfg.level do
            cur.history[i] = {}
        end

        ngx.log(ngx.INFO, "tick: init")
    end

    delta = time - cur.tick

    ngx.log(ngx.INFO, "tick: ".."time="..tostring(time)..", tick="..tostring(cur.tick)..", date="..os.date("%Y-%m-%d %H:%M:%S", cur.tick))

    local units
    local remainder

    -- feed to stepping unit
    if delta < cur.delta then
        distribution.add(key, cur.unit, data)
        goto _EXIT
    else
        stepping.add(key, cur.history, 1, cur.unit)
        cur.unit = {}   -- clear the unit
    end

    delta = delta - cur.delta
    units = math.floor(delta / cur.delta)
    remainder = delta % cur.delta

    -- feed gap to stepping
    stepping.gap(key, cur.history, units, stepping.merge)

    -- feed remainder to stepping unit
    cur.tick = time - remainder
    distribution.add(key, cur.unit, data)

    ::_EXIT::
    return cur
end

function stepping.process(cur, data, max)
    -- structure {index=?, content={?,?,?}}

    local index = cur.index
    -- init structure if necessary
    if not index then
        index = 0
        cur.index = 0
        cur.content = {}
    end

    cur.content[index+1] = data

    index = (index + 1) % max
    cur.index = index

    ngx.log(ngx.INFO, "process: index="..tostring(index)..", data="..json.encode(data))
    if index == 0 then
        return true -- step into higher level
    end

    return false
end

function stepping.merge(result, data)
    for k,v in pairs(data) do
        if result[k] ~= nil then
            result[k] = result[k] + data[k]
        else
            result[k] = data[k]
        end
    end
end

function stepping.gap(key, cur, count, mergeCB)
    -- structure [level1_object, level2_object, level3_object,...]
    local cfg = stepping.config[key]

    ngx.log(ngx.INFO, "gap: enter="..tostring(count))

    local unit = 1
    local lvl = 1
    local data = nil
    while true do
        ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", unit="..tostring(unit))
        local max
        local container
        local quantity = math.floor(count / unit)

        if lvl > #cfg.level then
            data = nil
            count = count % unit
            goto _PREV
        elseif lvl <= 0 then
            break
        end

        max = cfg.level[lvl]
        container = cur[lvl]

        -- if there is carry data, handle it
        if data then
            stepping.add(key, cur, lvl, data, mergeCB)
            data = nil
        end

        if not container.index then
            --init structure
            container.index = 0
            container.content = {}
        end

        if quantity >= max - container.index then
            -- merge original data
            local result = {}
            local remainder = max - container.index
            for i=1,container.index do
                mergeCB(result, container.content[i])
            end

            ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", merge:"..tostring(container.index))

            -- update current level
            for i=container.index+1,max do
                container.content[i] = {}
            end
            container.index = 0

            ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", pad:"..tostring(remainder).."x"..tostring(unit))

            -- update packet counter
            count = count - remainder * unit
            ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", counter:"..tostring(count))

            -- carry data to upper level
            data = result

            --continue
            goto _NEXT
        end

        -- no need to carry
        -- update current level
        for i=container.index+1,container.index+quantity do
            container.content[i] = {}
        end
        container.index = container.index + quantity

        ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", pad:"..tostring(quantity).."x"..tostring(unit))

        -- update packet counter
        count = count - quantity * unit
        ngx.log(ngx.INFO, "gap: lvl="..tostring(lvl)..", counter:"..tostring(count))

        -- continue
        goto _PREV

        -- step into next level
        ::_NEXT::
        unit = unit * max
        lvl = lvl + 1
        goto _ROUND

        -- step into previous level
        ::_PREV::
        lvl = lvl - 1
        max = cfg.level[lvl]
        if not max then
            unit = 0
        else
            unit = unit / max
        end

        ::_ROUND::
    end

    ngx.log(ngx.INFO, "gap: return="..tostring(count))
    return count
end

function stepping.add(key, cur, level, data, mergeCB)
    -- structure [level1_object, level2_object, level3_object,...]

    local cfg = stepping.config[key]
    if not cfg then
        return
    end

    ngx.log(ngx.INFO, "add: lvl="..tostring(level))

    for lvl=level,#cfg.level do
        local max = cfg.level[lvl]
        local container = cur[lvl]
        if stepping.process(container, data, max) == false then
            break
        end

        -- merge data
        local result = {}
        if not mergeCB then
            mergeCB = stepping.merge
        end
        for _,e in pairs(container.content) do
            mergeCB(result, e)
        end

        -- step into next level
        data = result
    end
end

function stepping.evaluate(key, cur)
end

------- Stepping Module End -------
