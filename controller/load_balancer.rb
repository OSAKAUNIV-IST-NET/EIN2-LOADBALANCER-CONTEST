class LoadBalancingSwitch < Controller
  add_timer_event :read_hp_files, 1, :periodic
  DIR_HP_FILE = "/tmp/"
  HP_FILE_PREFIX = "server"
  
  def start
    # cmd = "sudo rm " + DIR_HP_FILE + HP_FILE_PREFIX + "_*"
    # puts cmd
    # system(cmd)

    # puts "Start load balancer"
    # puts 

    # declare and initialize varibles
    @servers = []   # list of server's IP address
    @macs = {}      # hash list [<IP address>: => <MAC address>] for each server
    @hp_files = {}  # list of HP file's name for each server
    @server_hps = Hash::new
    @sum_of_hps = 0

    # try to get server list, and trial will end in failure,
    # since HP files are deleted above
    get_server_list DIR_HP_FILE, HP_FILE_PREFIX
  end


  def packet_in datapath_id, message
    # print information about incoming packet
    # if message.ipv4_daddr != nil
    #   puts message.ipv4_saddr.to_s + " -> " + message.ipv4_daddr.to_s
    # end

    #### load balance, if destination is one of servers
    if @servers.include?(message.ipv4_daddr.to_s)
      if @sum_of_hps != 0
        random_num = rand(@sum_of_hps)
        sum = 0
        for i in @servers
          sum = sum + @server_hps[i]
          if sum > random_num
            mac = @macs[i]
            packet_out datapath_id, message , OFPP_FLOOD, i, mac
            break
          end
        end
      else 
        packet_forward datapath_id, message , OFPP_FLOOD
      end
    else
      packet_forward datapath_id, message , OFPP_FLOOD
    end
  end



  ##############################################################################
  private
  ##############################################################################

  def packet_out datapath_id, message , port_no, ip_address, mac_address
    send_packet_out(
      datapath_id,
      :packet_in => message,
      :actions => [ SetIpDstAddr.new( ip_address ),
                    SetEthDstAddr.new( mac_address ),
                    ActionOutput.new( OFPP_FLOOD ) ]
    )
  end
  
  def packet_forward datapath_id, message , port_no
    send_packet_out(
      datapath_id,
      :packet_in => message,
      :actions => ActionOutput.new( OFPP_FLOOD )
    )
  end

  def read_hp_files
    # update server list
    get_server_list DIR_HP_FILE, HP_FILE_PREFIX

    # for each server, read HP file and get server's hp
    # then, calculate sum of HPs for all servers
    @sum_of_hps = 0
    for i in @servers
      begin
        f = open(@hp_files[i], "r")
        line = f.gets
        if line != nil
          @server_hps[i] = line[/[0-9]*$/].to_i
          # puts @server_hps[i]
          @sum_of_hps = @sum_of_hps + @server_hps[i]
        end
        f.close
      rescue
        STDERR.puts "Can't open file " + @hp_files[i] + "\n"
      end
    end
    # puts @sum_of_hps
  end  

  def get_server_list dir_name, file_prefix
    # initialize variables
    @servers = []   # list of server's IP address
    @macs = {}      # hash list [<IP address>: => <MAC address>] for each server
    @hp_files = {}  # list of HP file's name for each server
    
    file_name = dir_name + file_prefix + "_*"
    begin
      Dir.glob( file_name ).each do | each |
        ip, mac = each.split( "_" )[ 1, 2 ]
        @servers << ip
        @macs[ip] = mac
        @hp_files[ip] = each
      end
    rescue
      STDERR.puts "error occurred... \(^o^)/"
    end
  end

end
