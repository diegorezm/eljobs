math.randomseed(os.time())

local function random_string(length)
  local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local result = {}
  for i = 1, length do
    local idx = math.random(1, #charset)
    table.insert(result, charset:sub(idx, idx))
  end
  return table.concat(result)
end

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"

request = function()
  local payload = random_string(12)
  local body = string.format('{"payload": "%s"}', payload)
  return wrk.format(wrk.method, nil, wrk.headers, body)
end
