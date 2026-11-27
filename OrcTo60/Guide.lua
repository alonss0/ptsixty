local _, addon = ...

function addon.newGuide()
    local guide = { steps = {} }
    local section, entry

    local function add(text, location, kind, quest)
        local step = { section = section, entry = entry, text = text, kind = kind, quest = quest }
        entry = nil
        if location then
            step.zone, step.map, step.x, step.y = location[1], location[2], location[3], location[4]
        end
        guide.steps[#guide.steps + 1] = step
        return step
    end

    guide.add = add

    function guide.chapter(level, title)
        section, entry = title, level
    end

    function guide.travel(text, zone, map, x, y)
        add(text, { zone, map, x, y })
    end

    function guide.gate(level, text)
        add(("Reach %d. %s"):format(level, text)).level = level
    end

    function guide.accept(id, note)
        local quest = assert(addon.quests[id], "Missing quest " .. id)
        add("Accept " .. quest[1] .. " from " .. quest[2] .. "." .. (note and (" " .. note) or ""),
            quest[4], "accept", id)
    end

    function guide.turn(id)
        local quest = assert(addon.quests[id], "Missing quest " .. id)
        add("Turn in " .. quest[1] .. " to " .. quest[3] .. ".", quest[5], "turn", id)
    end

    function guide.delivery(id, note)
        guide.accept(id, note)
        guide.turn(id)
    end

    function guide.circuit(ids, text, zone, map, x, y)
        for _, id in ipairs(ids) do guide.accept(id) end
        add(text, map and { zone, map, x, y }, "objectives", ids)
        for _, id in ipairs(ids) do guide.turn(id) end
    end

    return guide
end
