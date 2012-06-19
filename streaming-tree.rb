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
			info "DEBUG #{dpid.to_hex} via #{message.macsa} - #{message.ipv4_saddr} -> #{message.ipv4_daddr}"
			if members(group).empty?
				info "DEBUG #{dpid.to_hex} via #{message.macsa} - not a registered group; flood!"
				flood_out dpid, message
			else
				if @datapath_in[dpid].member? group
					info "DEBUG #{dpid.to_hex} via #{message.macsa} - message already received; prune!"
					match = ExactMatch.from(message)
					prune_flow dpid, group, match
				else
					@datapath_in[dpid].add(group)
					flood_mod dpid, group, message
				end
			end
		end
	end

	def flow_removed dpid, message
		if message.reason != 2
			group = message.match.nw_dst
			@datapath_in[dpid].delete(group)
		end
	end

	private

	def handle_igmp dpid, message
		if message.igmp_v3_membership_report?
			# o framework NÃO tem suporte decente a IGMPv3. e não avisa.
			igmp_group = message.data[46..-1].unpack("CCnN") # iterar?
			group = members igmp_group[3]
			if igmp_group[0] == 4 # join
				group.add(dpid)
				info "DEBUG #{dpid.to_hex} via #{message.macsa} - #{message.ipv4_saddr} joined group #{igmp_group[3].to_hex}"
			elsif igmp_group[0] == 3 # leave
				group.delete(dpid)
				info "DEBUG #{dpid.to_hex} via #{message.macsa} - #{message.ipv4_saddr} left group #{igmp_group[3].to_hex}"
			end
		elsif message.igmp_v2_membership_report?
			group = members message.igmp_group
			group.add(dpid)
			info "DEBUG #{dpid.to_hex} via #{message.macsa} - #{message.ipv4_saddr} joined group #{message.igmp_group}"
		elsif message.igmp_v2_leave_group?
			group = members message.igmp_group
			group.delete(dpid)
			info "DEBUG #{dpid.to_hex} via #{message.macsa} - #{message.ipv4_saddr} left group #{message.igmp_group}"
		end
	end

	# TODO: se porta aponta para host final que não é membro do grupo (como descobrir?), apaga/não adiciona fluxo
	def flood_mod dpid, group, message
		group_ports = @datapath_out[dpid][group]
		group_ports.merge(@ports[dpid])
		group_ports.delete(message.in_port)
		info "DEBUG #{dpid.to_hex}: added flows (#{group_ports.to_a.join(', ')})"
		send_flow_mod_add(
			dpid,
			:match => ExactMatch.from(message),
			:hard_timeout => 10,
			:actions => group_output(group_ports)
		)
		flood_out dpid, message
	end

	def group_output group_ports
		group_ports.collect do |port|
			ActionOutput.new(:port => port)
		end
	end

	def flood_out dpid, message
		send_packet_out(
			dpid,
			:packet_in => message,
			:actions => ActionOutput.new( :port => OFPP_FLOOD )
		)
	end

	def prune_flow dpid, group, match
		#parent_dpid = ???
		#parent_port = ???
		#parent_match = ???
		group_ports = @datapath_out[parent_dpid][group]
		group_ports.remove(parent_port)
		if group_ports.empty?
			prune_flow parent_dpid, group, parent_match
		end
	end

	def members group
		@groups[group.to_i]
	end
end
