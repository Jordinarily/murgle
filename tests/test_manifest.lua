local H = dofile("tests/helpers.lua")

test("manifest loads only existing nonempty files without duplicates", function()
    local seen = {}
    local paths = H.addonFiles()
    eq(#paths > 0, true, "manifest must load runtime files")
    for _, path in ipairs(paths) do
        eq(seen[path], nil, "duplicate manifest file: " .. path)
        seen[path] = true
        local file = assert(io.open(path, "rb"), "missing manifest file: " .. path)
        local contents = file:read("*a")
        file:close()
        eq(contents:find("%S") ~= nil, true, "empty manifest file: " .. path)
    end
end)
