if GetResourceState('ox_lib') == 'started' or GetResourceState('ox_lib') == 'starting' then
    local content = LoadResourceFile('ox_lib', 'init.lua')
    if content then
        load(content)()
    end
end
