local uv = require('uv')
local json = require('json')
local timer = require('timer')
local websocket = require('coro-websocket')
local Buffer = require('../utils/Buffer')

local time = os.time
local encode, decode = json.encode, json.decode
local wrap, yield = coroutine.wrap, coroutine.yield
local connect = websocket.connect
local setInterval, clearInterval = timer.setInterval, timer.clearInterval

local VoiceSocket = class('VoiceSocket')

function VoiceSocket:__init(client)
	self._client = client
end

function VoiceSocket:connect(endpoint)
	self._res, self._read, self._write = connect({
		host = endpoint:gsub(':.*', ''),
		port = 443,
		tls = true,
	})
	self._connected = self._res and self._res.code == 101
	return self._connected
end

function VoiceSocket:handlePayloads()

	for data in self._read do

		local payload = decode(data.payload)
		local op = payload.op

		if op == 2 then
			local d = payload.d
			self:startHeartbeat(d.heartbeat_interval)
			self:handshake(d.ip, d.port, d.ssrc)
		elseif op == 4 then
			self._key = payload.d.secret_key
			self._client:emit('connect')
		end

	end

	p('voice disconnect') -- debug

end

function VoiceSocket:handshake(ip, port, ssrc)

	local udp = uv.new_udp()

	udp:recv_start(function(err, msg)

		assert(not err, err)

		if msg then

			udp:recv_stop()
			local address = msg:match('%d.*%d')
			local a, b = msg:sub(-2):byte(1, 2)

			wrap(self.selectProtocol)(self, {
				address = address,
				port = a * 0x100 + b,
				mode = 'xsalsa20_poly1305',
			})

		end

	end)

	local buffer = Buffer(70)
	buffer:writeUInt32LE(0, ssrc)
	udp:send(tostring(buffer), ip, port)

end

function VoiceSocket:startHeartbeat(interval)
	if self._heartbeatInterval then clearInterval(self._heartbeatInterval) end
	self._heartbeatInterval = setInterval(interval, wrap(function()
		while true do
			yield(self:heartbeat())
		end
	end))
end

function VoiceSocket:stopHeartbeat()
	if not self._heartbeatInterval then return end
	clearInterval(self._heartbeatInterval)
	self._heartbeatInterval = nil
end

local function send(self, op, d)
	return self._write({
		opcode = 1,
		payload = encode({op = op, d = d})
	})
end


function VoiceSocket:identify(data)
	return send(self, 0, data)
end

function VoiceSocket:selectProtocol(data)
	return send(self, 1, {
		protocol = 'udp',
		data = data
	})
end

function VoiceSocket:heartbeat()
	return send(self, 3, time())
end

return VoiceSocket
