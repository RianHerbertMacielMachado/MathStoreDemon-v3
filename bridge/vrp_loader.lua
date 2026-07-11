if GetResourceState('vrp') == 'started' or GetResourceState('vrp') == 'starting' then
    local content = LoadResourceFile('vrp', 'lib/utils.lua')
    if content then
        load(content)()
    end
end
