class StreamingTree < Controller
	def start
		info "Iniciando módulo streaming-tree"
		@urls = {
			"rtsp://127.0.0.1/stream.sdp" => "example"
		}
		@groups = Hash.new
	end

	def packet_in dpid, message
		if message.udp?
			lines = message.udp_payload.lines('\r\n')
			if lines[0] =~ /^([A-Z]+) (.*) RTSP\/1\.0\r\n$/
				method = $1
				uri = $2
				info method
				info uri
				if @urls.member?(uri)
					new_payload = [lines[0]]
					lines[1..-1].each do |line|
						info line
					end
				else
					flood dpid, message
				end
			else
				flood dpid, message
			end
		else
			flood dpid, message
		end
	end

	private

	def flood dpid, message
		send_packet_out(
			dpid,
			:packet_in => message,
			:actions => ActionOutput.new( :port => OFPP_FLOOD )
		)
	end
end
