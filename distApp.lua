------- DistPath Module Start -------
-- distribution for HTTP request --
distPath.shm = "captcha_distribution_path"
distPath.cache = {}

function distPath.register()
    local dict = ngx.shared[distPath.shm]
    if not dict then
        return
    end

    distribution.register("distPath", {min={0}, max={10}}, {1}, 10)
    stepping.register("distPath", {tick="minute", level={10,6,24}})
end

function distPath.add(name, data)
    local cfg = stepping.config["distPath"]
    if not cfg then
        return
    end

    if distPath.filter(data) ~= true then
        return
    end

    local cur = shmDB.get(distPath.shm, name)
    if type(cur) ~= "table" then
        return
    end

    data = distPath.classifier(data)
    cur = stepping.tick("distPath", cur, {data})
    if type(cur) ~= "table" then
        return
    end

    shmDB.set(distPath.shm, name, cur)
end

function distPath.get(name)
    local cfg = stepping.config["distPath"]
    if not cfg then
        return
    end

    local dict = ngx.shared[distPath.shm]
    if not dict then
        return
    end

    local cur = shmDB.get(distPath.shm, name)
    return cur
end

function distPath.classifier(data)
    -- TODO need lock between nginx's workers

    local saved = distPath.cache

    -- Lock

    -- get current mapping from cache (or from persistent if necessary)
    if saved[data] then
        goto _EXIT
    end

    saved = shmDB.get(distPath.shm, "classifier")
    if saved[data] then
        distPath.cache = saved
        goto _EXIT
    end

    -- add new mapping key if necessary and get map result
    saved[data] = utils.table_size(saved)
    distPath.cache = saved

    -- update persistent if necessary
    shmDB.set(distPath.shm, "classifier", saved)

    ::_EXIT::
    -- Unlock

    ngx.log(ngx.INFO, "classifier: "..data.."=>"..tostring(saved[data]))
    return saved[data]
end

function distPath.filter(data)
    if string.sub(data, -4) == ".jpg" or string.sub(data, -4) == ".png" or string.sub(data, -4) == ".css" or string.sub(data, -3) == ".js" then
        ngx.log(ngx.INFO, "filter: "..data)
        return false
    end

    return true
end

function distPath.api(info)
    distPath.add(info.id, info.path)
    local data = distPath.get(info.id
    ngx.log(ngx.ERR, json.encode(data))
end

------- DistPath Module End -------

------- distURL Module Start -------
-- distribution for URLs --
distURL.shm = "captcha_distribution_url"
distURL.cache = {}
distURL.config = {}

function distURL.register(tick, limit)
    local dict = ngx.shared[distURL.shm]
    if not dict then
        return
    end

    distribution.register("distURL", {min={0}, max={3}}, {1}, 3)
    distURL.config = {duration=tick, limit=limit}
end

function distURL.add(name, data)
    local cfg = distURL.config
    if not cfg then
        return
    end

    local cur = shmDB.get(distURL.shm, name)
    if type(cur) ~= "table" then
        return
    end

    data = distribution.classifier(distURL.cache, distURL.shm, data)

    local duration = cfg.duration
    local cur_time = ngx.time()
    if not cur.tick then
        -- first time
        cur.tick = cur_time
        cur.unit = {}
        cur.dist = {}
    end

    if cur.tick + duration <= cur_time then
        -- calculate distribution
        cur.dist = distribution.calculate(cur.unit, cur.dist, cfg.limit)
        cur.unit = {}
        cur.tick = cur_time - ((cur_time - cur.tick) % duration)
    end
    distribution.add("distURL", cur.unit, {data})

    cur.entropy = distURL.entropy(cur.dist)
    shmDB.set(distURL.shm, name, cur)
    return cur.entropy
end

function distURL.entropy(data)
    local result = {}
    for k,v in pairs(data) do
        -- don't involve "exceeding" field for calculating entropy
        local save = utils.table_del(v, "exceeding")
        result[k] = distribution.entropy(v)
        v["exceeding"] = save
    end
    return result
end

function distURL.classifier(data)
    return distribution.classifier(distURL.cache, distURL.shm, data)
end

function distURL.get(name)
    return shmDB.get(distURL.shm, name)
end

function distURL.api(info)
    local entropies = distURL.add(info.id, info.path)
    local name = distURL.classifier(info.path)
    name = distribution.map("distURL", {name})
    utils.log("urlEntropy", entropies and entropies[name], 1000)

    -- local show = distURL.get(info.id)
    -- ngx.log(ngx.INFO, json.encode(show))
end

------- distURL Module End -------

------- DistClick Module Start -------
-- distribution for mouse click --
distClick.shm = "captcha_distribution_click"

function distClick.register(key, range, step, count)
    local dict = ngx.shared[distClick.shm]
    if not dict then
        return
    end

    distribution.register("distClick:"..key, range, step, count)
end

function distClick.add(key, name, data)
    local cur = shmDB.get(distClick.shm, key..":"..name)
    if type(cur) ~= "table" then
        return
    end

    cur = distribution.add("distClick:"..key, cur, data)
    if type(cur) ~= "table" then
        return
    end

    shmDB.set(distClick.shm, key..":"..name, cur)
end

function distClick.evaluate(key, name)
    local cur = shmDB.get(distClick.shm, key..":"..name)
    if type(cur) ~= "table" then
        return
    end

    local entropy = distribution.entropy(cur)
    return entropy, distribution.evaluate("distClick:"..key, cur)
end

function distClick.get(key, name)
    return shmDB.get(distClick.shm, key..":"..name)
end

function distClick.api(info, data)
    local cfg = info.key

    distClick.add(cfg, info.id..":"..cfg, {data.x, data.y})
    local entropy, parts, total, exceeding = distClick.evaluate(cfg, info.id..":"..cfg)
    -- ngx.log(ngx.DEBUG, "distClick:"..tostring(entropy)..'/'..tostring(parts)..'/'..tostring(total)..'/'..tostring(exceeding))
    -- ngx.log(ngx.DEBUG, "distClick:"..json.encode(distClick.get(cfg, info.id..":"..cfg)))
    utils.log("clickEntropy", entropy, 1000)
    return {
        entropy = entropy,
        parts = parts,
        total = total,
        exceeding = exceeding,
    }
end

------- DistClick Module End -------

------- DistRTD Module Start -------
-- distribution for HTML page Response Time --
distRTD.shm = "captcha_distribution_rtd"
distRTD.cfg = {
    -- range unit is "second"
    quick = {
        range = {min={0.0}, max={5.0}},
        step = {0.1},
        count = 50,
    },
    slow = {
        range = {min={0}, max={50}},
        step = {1},
        count = 50,
    },
}

function distRTD.config(type)
    return distRTD.cfg[type]
end

function distRTD.register(key, cfg)
    local dict = ngx.shared[distRTD.shm]
    if not dict then
        return
    end

    distribution.register("distRTD:"..key, cfg.range, cfg.step, cfg.count)
end

function distRTD.add(key, name, data)
    local cur = shmDB.get(distRTD.shm, key..":"..name)
    if type(cur) ~= "table" then
        return
    end

    cur = distribution.add("distRTD:"..key, cur, {data})
    if type(cur) ~= "table" then
        return
    end

    shmDB.set(distRTD.shm, key..":"..name, cur)
end

function distRTD.evaluate(key, name)
    local cur = shmDB.get(distRTD.shm, key..":"..name)
    if type(cur) ~= "table" then
        return
    end

    local entropy = distribution.entropy(cur)
    return entropy, distribution.evaluate("distRTD:"..key, cur)
end

function distRTD.get(key, name)
    return shmDB.get(distRTD.shm, key..":"..name)
end

function distRTD.api(info, duration)
    local cfg = info.key
    distRTD.add(cfg, info.id, duration)
    local entropy, parts, total, exceeding = distRTD.evaluate(cfg, info.id)
    -- ngx.log(ngx.DEBUG, "distRTD:"..tostring(entropy)..'/'..tostring(parts)..'/'..tostring(total)..'/'..tostring(exceeding))
    -- local show = distRTD.get(cfg, info.id)
    -- ngx.log(ngx.ERR, "distRTD:"..json.encode(show))
    utils.log("rtdEntropy", entropy, 1000)
end

------- DistRTD Module End -------
