------- ShmDB Module Start -------
function shmDB.get(name, key)
    local dict = ngx.shared[name]
    if not dict then
        return
    end

    local cur = dict:get(key)
    if not cur then
        cur = "{}"
    end
    cur = json.decode(cur)

    return cur
end

function shmDB.set(name, key, cur)
    local dict = ngx.shared[name]
    if not dict then
        return
    end

    new = json.encode(cur)
    -- limit the total length of the content written into shm
    if #new > 1024 then
        ngx.log(ngx.WARN, "too large to write shm")
        return
    end
    
    ngx.log(ngx.DEBUG, tostring(new))
    dict:set(key, new)
end

------- ShmDB Module End -------
