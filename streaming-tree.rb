require "set"

class StreamingTree < Controller
	def start
		info "Iniciando módulo streaming-tree"
		@groups = Hash.new do | hash, key |
			hash[key] = Set.new
		end
	end

	def packet_in dpid, message
		if message.igmp?
			handle_igmp message
		else
			group = members message.ipv4_daddr
			if group.empty?
				flood_out dpid, message
			else
				# RPF!
			end
		end
	end

	private

	def handle_igmp message
		group = members message.igmp_group
		source = message.macsa
		if message.igmp_v2_membership_report?
			group.add(source)
		elsif message.igmp_v2_leave_group?
			group.delete(source)
		end
	end

	def flood_mod dpid, message
		send_flow_mod_add(
			dpid,
			:match => ExactMatch.from(message),
			:actions => ActionOutput.new( :port => OFPP_FLOOD )
		)
	end

	def flood_out dpid, message
		send_packet_out(
			dpid,
			:packet_in => message,
			:actions => ActionOutput.new( :port => OFPP_FLOOD )
		)
	end

	def members group
		@groups[group.to_i]
	end
end
