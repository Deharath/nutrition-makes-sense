local Support = {}

function Support.assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

function Support.assertClose(actual, expected, epsilon, message)
    local a = tonumber(actual)
    local b = tonumber(expected)
    local tolerance = tonumber(epsilon) or 0.000001
    if a == nil or b == nil or math.abs(a - b) > tolerance then
        error(string.format("%s: expected %.6f, got %s", message or "values differ", b or 0, tostring(actual)), 2)
    end
end

function Support.assertTrue(value, message)
    if value ~= true then
        error(message or "expected true", 2)
    end
end

function Support.assertNil(value, message)
    if value ~= nil then
        error(string.format("%s: got %s", message or "expected nil", tostring(value)), 2)
    end
end

return Support
