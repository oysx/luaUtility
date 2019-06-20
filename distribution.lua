------- Distribution Module Start -------
distribution.config = {}

function distribution.register(key, range, step, count)
    -- format: range={min=[x,y,z,...], max=[x,y,z,...]}
    -- format: step=[x,y,z,...]
    if distribution.config[key] then
        return
    end

    distribution.config[key] = {
        range= range,
        step= step,
        count= count,
    }
end

function distribution.map(key, data)
    local cfg = distribution.config[key]
    if not cfg then
        return nil
    end

    if #data ~= #cfg.step then
        return nil
    end

    -- find the grid this data belong to
    local result = {}
    for k,v in pairs(data) do
        if v < cfg.range.min[k] then
            v = cfg.range.min[k]
        elseif v > cfg.range.max[k] then
            v = cfg.range.max[k]
        end
        result[k] = math.floor((v - cfg.range.min[k]) / cfg.step[k])
    end

    -- convert list to string for dictionary operation
    local new = ""
    for k,v in pairs(result) do
        new = new .. tostring(v) .. ':'
    end

    return new
end

function distribution.add(key, cur, data)
    -- ngx.log(ngx.info, "distribution.add: "..json.encode(data))

    local new = distribution.map(key, data)
    if not new then
        return
    end

    local cfg = distribution.config[key]
    -- limit total count if required
    if not cur[new] and cfg.count then
        local segs = 0
        for k,v in pairs(cur) do
            segs = segs + 1
        end
        if segs >= cfg.count then
            new = "exceeding"
        end
    end

    if not cur[new] then
        cur[new] = 0
    end
    cur[new] = cur[new] + 1

    return cur
end

function distribution.evaluate(key, cur)
    local cfg = distribution.config[key]
    if not cfg then
        return
    end

    local count = 0
    local segments = 0
    for k,v in pairs(cur) do
        count = count + v
        segments = segments + 1
    end

    return segments, count, cur["exceeding"]
end

function distribution.classifier(cache_obj, db_obj, data)
    local saved = cache_obj['content']
    if saved and saved[data] then
        goto _EXIT
    end

    saved = shmDB.get(db_obj, "classifier")
    if saved[data] then
        cache_obj['content'] = saved
        goto _EXIT
    end

    saved[data] = cutils.table_size(saved)
    cache_obj['content'] = saved

    shmDB.set(db_obj, "classifier", saved)

    ::_EXIT::

    ngx.log(ngx.INFO, "classifier: "..data.."=>"..tostring(saved[data]))
    return saved[data]
end

function distribution.calculate(data, cur, limit)
    for k,v in pairs(data) do
        v = tostring(v)
        local category = cur[k]
        if not category then
            cur[k] = {}
            category = cur[k]
        end
        if not category[v] and cutils.table_size(category) >= limit then
            -- all remainder go into "exceeding"
            v = "exceeding"
        end
        if not category[v] then
            category[v] = 0
        end

        category[v] = category[v] + 1
    end
    return cur
end

function distribution.entropy(data)
    local total = 0
    for k,v in pairs(data) do
        total = total + v
    end

    local result = 0
    for k,v in pairs(data) do
        local p = v / total
        result = result - p * math.log(p)   --TODO: this is log<e> not log<2>
    end

    return result
end

------- Distribution Module End -------
