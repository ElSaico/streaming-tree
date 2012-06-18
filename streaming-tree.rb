require "set"

class StreamingTree < Controller
	def start
		info "Iniciando módulo streaming-tree"
		# portas de um switch
		@ports = Hash.new
		# switches de última milha pra cada grupo
		@groups = Hash.new do | hash, key |
			hash[key] = Set.new
		end
		# switches que já possuem fluxo para um determinado grupo
		@datapath_in = Hash.new do | hash, key |
			hash[key] = Set.new
		end
		# fluxos de saída de um switch em um determinado grupo
		@datapath_out = Hash.new do | hash, key |
			hash[key] = Hash.new do | h2, k2 |
				h2[k2] = Set.new
			end
		end
	end

	def switch_ready dpid
		send_message dpid, FeaturesRequest.new
	end

	def features_reply message
		@ports[message.datapath_id] = message.ports.collect{|each| each.number}
	end

	def packet_in dpid, message
		if message.igmp?
			handle_igmp dpid, message
		elsif !message.ipv4?
			flood_out dpid, message
		else
			group = message.ipv4_daddr
			if members(group).empty?
				flood_out dpid, message
			else
				if @datapath_in.member? dpid
					delete_flow dpid, group, message
				else
					@datapath_in[dpid] = true
					flood_mod dpid, group, message
				end
			end
		end
	end

	def flow_removed dpid, message
		if message.reason != OFPRR_DELETE
			@datapath_in[dpid] = false
		end
	end

	private

	def handle_igmp dpid, message
		group = members message.igmp_group
		if message.igmp_v2_membership_report?
			group.add(dpid)
		elsif message.igmp_v2_leave_group?
			group.delete(dpid)
		end
	end

	# TODO: se porta aponta para host final que não é membro do grupo (como descobrir?), apaga/não adiciona fluxo
	def flood_mod dpid, group, message
		@ports[dpid].each{ |port|
			if port != message.in_port
				send_flow_mod_add(
					dpid,
					:match => ExactMatch.from(message),
					:actions => ActionOutput.new( :port => port )
				)
				@datapath_out[dpid][group].add(port)
			end
		}
		flood_out dpid, message
	end

	def flood_out dpid, message
		send_packet_out(
			dpid,
			:packet_in => message,
			:actions => ActionOutput.new( :port => OFPP_FLOOD )
		)
	end

	def delete_flow dpid, group, message
		if @datapath_out[dpid][group].empty?
			# apaga fluxo de chegada (recursivamente)
		end
	end

	def members group
		@groups[group.to_i]
	end
end
