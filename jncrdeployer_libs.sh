#!/usr/bin/env bash
# common functions {{{1}}}
# Gist: https://gist.github.com/pinggit/b746a7fa2b41c12a8daf32eee1521743
# GistID: b746a7fa2b41c12a8daf32eee1521743
# https://gist.githubusercontent.com/pinggit/b746a7fa2b41c12a8daf32eee1521743/raw/c5bfde0845767d3127d7ea3a0b1b1c0f0b610c6e/jcnrdeployer_libs.sh
function init_vars() {  # {{{2}}}
    declare -g version="version_known"
    declare -g box12="box12_unknown"
    declare -g nic="nic_unknown"
    declare -g core_count_str="core_count_unknown"
    declare -g l2l3="l2l3_unknown"
    declare -g otherinfo

    declare -g valid_hc_files=""
    declare -g valid_hc_files_count
    declare -g hc_folder=""
    declare -g pos_params

    declare -g debug="false"                     # debug mode
    declare -g encap="vrf"                       # l2 vrf evpn mplsoudp
    declare -g leftlink=""
    declare -g tags=""
    declare -g dry_run="false"
    declare -g taskmode="all"  # all, deploy, test
    declare -g force_scan="false"
    declare -g file_name_parse="false"
    declare -g hc_file_pattern="values-*.yaml"
    declare -g rightlink=""
    declare -g num_of_deploy_attempts=1
    declare -g fast_deploy="false"

    declare -g url=http://10.87.104.229:5000/run_test
    declare -g desired_members_default="ens785f2 ens785f3"
    declare -gA link1map=(
        ["e810"]="ens785f0"
        ["v710"]="ens801f1"
    )
    declare -g -A link2map=(
        ["e810"]="ens786f0"
        ["v710"]="ens802f1"
    )
    declare -g -A if2ip=(
        ["ens785f0"]="10.220.220.220/24 2001::1/64"
        ["ens785f1"]="10.230.230.230/24 2002::1/64"
        ["ens801f1"]="10.220.220.220/24 2001::1/64"
        ["ens802f1"]="10.230.230.230/24 2002::1/64"
    )
    declare -g -A if2nic=(
        ["ens785"]="e810"
        ["ens801"]="v710"
        ["ens785f0"]="e810"
        ["ens785f1"]="e810"
        ["ens785f2"]="e810"
        ["ens785f3"]="e810"
        ["ens786f0"]="e810"
        ["ens786f1"]="e810"
        ["ens786f2"]="e810"
        ["ens786f3"]="e810"
        ["ens801f1"]="v710"
        ["ens802f1"]="v710"
    )
    declare -g log_file="${script_basename%.*}_testlog.adoc"   # strip extension
}

function log1() { # {{{2}}}
    declare -g log_file
    # like echo, but but also write to $log_file (create if not exist)
    usage="
        log1 'hello world' # print to both stdout and log_file
        log1 'hello world' 0 # 0 means not print to stdout
        log1 'hello world' 1 # 1 means not print to log_file
        log1 'hello world' 2 # 2 means print to both stdout and log_file
        log1 'hello world' 3 # 3 means only print (to both stdout and log_file) if debug is true
        log1 'hello world' 4 or any other number # print usage and exit
    "
    [ ! -f "$log_file" ] && touch "$log_file"
    [ $# -eq 0 ] && echo "Usage: $usage" && exit 1
    [ $# -eq 1 ] && echo -e "$1" && echo -e "$1" >> "$log_file"
    if [ $# -eq 2 ]; then
        [ $2 -eq 0 ] && echo -e "$1" >> "$log_file"
        [ $2 -eq 1 ] && echo -e "$1"
        [ $2 -eq 2 ] && echo -e "$1" && echo -e "$1" >> "$log_file"
        [ $2 -eq 3 ] && [ "$debug" == "true" ] && echo -e "$1" && echo -e "$1" >> "$log_file"
        [ $2 -ge 4 ] && echo "Usage: $usage" && exit 1
    fi
}

function agent_id() {   # {{{2}}}
    crictl ps | grep agent | grep -v dpdk | awk '{print $1}'
}

function ct_id() {  # {{{2}}}
    crictl ps | grep tool | awk '{print $1}'
}

function crpd_id() { # {{{2}}}
    crictl ps | grep crpd | awk '{print $1}'
}

function ct() { # {{{2}}}
    crictl exec "$(ct_id)" "$@"
}

function cti() { # {{{2}}}
    crictl exec -it "$(ct_id)" bash
}

function vr() { # {{{2}}}
    crictl exec "$(agent_id)" "$@"
}

function vri() { # {{{2}}}
    crictl exec -it "$(agent_id)" bash
}

#function crpd() {
#    crictl exec "$(crpd_id)" "$@"
#}

#function crpd_clic() {
#    crictl exec "$(crpd_id)" cli -c "$@"
#}

function crpdi() { # {{{2}}}
    crictl exec -it "$(crpd_id)" bash
}


function crpd() { # {{{2}}}
    # Function to run a command in the CRPD pod
    local cmd="$@"
    #log1 "cmd: $cmd"
    local pod_name=$(kubectl get pod -n jcnr -o jsonpath='{.items[0].metadata.name}')
    log1 "pod_name $pod_name"
    if [ -z "$pod_name" ]; then
        log1 "No crpd pods found"
    else
        kubectl exec -n jcnr $pod_name -- sh -c "$cmd"
    fi
}

function crpd_clic() { #{{{2}}}
    # crpd_clic "show version"
    local cmd="$@"
    log1 "cmd: $cmd"
    crpd "cli -c \"$cmd\""
}

function crpd_clif() { #{{{2}}}
    # crpd_clif crpd.conf
    local cmd="$@"
    log1 "cmd: $cmd"
    crpd "cli -f \"$cmd\""
}

function crpd_cli() { #{{{2}}}
    # crpd_clic -c "show version"
    # crpd_clic -f config.txt
    local cmd="$@"
    log1 "cmd: $cmd"
    crpd "cli \"$cmd\""
}

function create_crpd_config_template() {        #{{{2}}}
    declare -g encap
    declare -g crpd_conf_template_file="$encap.template"
    declare -g template

    log1 "Creating crpd config template ..."
    template="configure"
    # vrf {{{3}}}
    if [ "$encap" == "vrf" ]; then
        template="
            $template
            set routing-instances red instance-type virtual-router
            set routing-instances red interface {{ VRFLINKS }}
        "
    fi

    # evpn {{{3}}}
    if [ "$encap" == "evpn" ]; then
        template="
            set groups pingevpn routing-options autonomous-system 64520
            set groups pingevpn routing-options router-id 10.1.1.1
            set groups pingevpn routing-options resolution rib :gribi.inet6.0 inet6-resolution-ribs :gribi.inet6.0

            # core interfaces
            set groups pingevpn interfaces lo0 unit 0 family inet address 10.1.1.1
            set groups pingevpn interfaces bond0 unit 0 family inet address 192.168.104.100/24
            set groups pingevpn interfaces ens785f0 unit 0 family inet address 10.220.220.1/24
            set groups pingevpn interfaces ens785f0 unit 0 family inet6 address 2001::1/64

            # igp
            set groups pingevpn routing-options static route 10.2.2.2/32 next-hop 192.168.104.101

            # overlay ibgp
            set groups pingevpn protocols bgp group tope type internal
            set groups pingevpn protocols bgp group tope local-address 10.1.1.1 local-as 64520
            set groups pingevpn protocols bgp group tope family evpn signaling
            set groups pingevpn protocols bgp group tope neighbor 10.2.2.2

            # vrf if/rd/rt/multipath
            set groups pingevpn routing-instances yellow instance-type vrf interface ens785f0
            set groups pingevpn routing-instances yellow route-distinguisher 10.1.1.1:11
            set groups pingevpn routing-instances yellow vrf-target target:11:11
            set routing-instances orange routing-options multipath
            set groups pingevpn routing-instances yellow vrf-table-label

            # vrf protocol evpn
            set groups pingevpn routing-instances yellow protocols evpn ip-prefix-routes advertise direct-nexthop
            set groups pingevpn routing-instances yellow protocols evpn ip-prefix-routes encapsulation vxlan
            set groups pingevpn routing-instances yellow protocols evpn ip-prefix-routes vni 10010

            # forwarding policy
            set groups pingevpn policy-options policy-statement pplb then load-balance per-packet
            set groups pingevpn routing-options forwarding-table channel vrouter export pplb
        "
    fi

    # mplsoudp {{{3}}}
    if [ "$encap" == "mplsoudp" ]; then
        template="
            # core interfaces
            set groups pingmplsoudp interfaces lo0 unit 0 family inet address 10.1.1.1
            set groups pingmplsoudp interfaces bond0 unit 0 family inet address 192.168.104.100/24
            set groups pingmplsoudp interfaces ens785f0 unit 0 family inet address 10.220.220.1/24
            set groups pingmplsoudp interfaces ens785f0 unit 0 family inet6 address 2001::1/64

            # global params
            set groups pingmplsoudp routing-options autonomous-system 64520
            # set groups pingmplsoudp routing-options route-distinguisher-id 10.1.1.1
            set groups pingmplsoudp routing-options router-id 10.1.1.1

            # igp
            set groups pingmplsoudp routing-options static route 10.2.2.2/32 next-hop 192.168.104.101

            # underlay ibgp and routing-policy
            # set groups pingmplsoudp policy-options policy-statement exp_bgp term 1 from protocol direct
            # set groups pingmplsoudp policy-options policy-statement exp_bgp term 1 from route-filter 10.1.1.1/32 exact
            # set groups pingmplsoudp policy-options policy-statement exp_bgp term 1 then accept
            set groups pingmplsoudp policy-options policy-statement udp-export then community add udp
            set groups pingmplsoudp policy-options community udp members encapsulation:0L:13

            set groups pingmplsoudp protocols bgp group tope type internal
            set groups pingmplsoudp protocols bgp group tope local-address 10.1.1.1 local-as 64520
            # set groups pingmplsoudp protocols bgp group tope family inet unicast
            set groups pingmplsoudp protocols bgp group tope family inet-vpn unicast
            set groups pingmplsoudp protocols bgp group tope family inet6-vpn unicast
            set groups pingmplsoudp protocols bgp group tope neighbor 10.2.2.2

            #set groups pingmplsoudp protocols bgp group tope export exp_bgp
            set groups pingmplsoudp protocols bgp group tope export udp-export
            set groups pingmplsoudp protocols mpls ipv6-tunneling

            # mplsoudp tunnel
            set groups pingmplsoudp routing-options dynamic-tunnels dyn-tunnels source-address 10.1.1.1
            set groups pingmplsoudp routing-options dynamic-tunnels dyn-tunnels udp
            set groups pingmplsoudp routing-options dynamic-tunnels dyn-tunnels destination-networks 10.2.2.2

            # pplb forwarding
            set groups pingmplsoudp policy-options policy-statement pplb then load-balance per-packet
            set groups pingmplsoudp routing-options forwarding-table channel vrouter export pplb

            # vrf
            set groups pingmplsoudp routing-instances yellow instance-type vrf interface ens785f0
            set groups pingmplsoudp routing-instances yellow route-distinguisher 10.1.1.1:11
            set groups pingmplsoudp routing-instances yellow vrf-target target:11:11
            set groups pingmplsoudp routing-instances yellow vrf-table-label

            # vrf ebgp
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totester type external
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totester local-address 10.220.220.1 local-as 64520
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totester neighbor 10.220.220.2 peer-as 64512
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totesterv6 type external
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totesterv6 local-address 2001::1 local-as 64520
            # set groups pingmplsoudp routing-instances yellow protocols bgp group totesterv6 neighbor 2001::2 peer-as 64512
        "
    fi
    template="
        $template
        commit
    "
    log1 "template: \n$template"
}

function create_crpd_config() {   #{{{2}}}
    # create crpd l3 config file
    declare -g fabric_interfaces_array
    declare -g encap
    declare -g crpd_conf_template_file
    declare -g crpd_conf_file="$encap.conf"
    declare -g template

    create_crpd_config_template
    # read crpd config template file and retain the newline
    # template=$(<"$crpd_conf_template_file")

    > "$crpd_conf_file"
    # customize vrf config {{{3}}}
    if [ "$encap" == "vrf" ]; then
        newlines=""
        # Read the template line by line
        while IFS= read -r line; do
            if [[ $line == *"{{ VRFLINKS }}"* ]]; then
                # Line contains the placeholder, generate config lines
                for interface in "${fabric_interfaces_array[@]}"; do
                    [[ "$interface" =~ ^bond0 ]] && continue         # skip bond0/members
                    newline="${line//\{\{ VRFLINKS \}\}/$interface}" # Replace placeholder
                    newlines="$newlines\n$newline"
                done
                echo -e "$newlines" >> "$crpd_conf_file"
            else
                # Line does not contain the placeholder, copy as is
                echo -e "$line" >> "$crpd_conf_file"
            fi
        done <<< "$template"
    fi

    # customize evpn config {{{3}}}
    # customize mplsoudp config {{{3}}}

    log1 "$crpd_conf_file file created:"
    cat "$crpd_conf_file"
}

function load_crpd_config() { # {{{2}}}
    declare -g crpd_conf_file

    # load crpd config file
    log1 "checking crpd pod..."
    crpd_pod=$(kubectl get pods -n jcnr | grep crpd | awk '{print $1}')
    if [ -z "$crpd_pod" ]; then
        log1 "crpd pod does not exist, skip loading crpd config"
    else
        log1 "crpd pod exists"
        log1 "copy $crpd_conf_file to crpd pod..."
        kubectl cp $crpd_conf_file jcnr/$crpd_pod:$crpd_conf_file
        log1 "load $crpd_conf_file in crpd..."
        crpd_clif $crpd_conf_file
    fi
}

function confirm() { # {{{2}}}
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
    # press yes or y to continue
    [yY][eE][sS] | [yY])        # if yes, return 0
        0
        ;;
    # press no or n to skip current loop
    [nN][oO] | [nN])            # if no, return 1
        1
        ;;
    # press e to exit
    [eE][xX][iI][tT] | [eE])    # if exit, return 2
        2
        ;;
    # other keys will be ignored
    *)
        3                       # invalid input
        ;;
    esac

    ## ask user to confirm before proceeding
    #if [ "$vrf_list_empty" == "1" ] || [ "$ddp_not_active" == "1" ] || [ "$vrf_wrong" == "1" ]; then
    #    log1 ">>>please confirm to proceed..."
    #    log1 ">>> Yy: proceed; Ss: skip this test; Nn: exit"
    #    read -p ">>>confirm to proceed? (y/s/n)" -n 1 -r
    #    echo
    #    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    #        log1 ">>>proceed this test..."
    #    elif [[ $REPLY =~ ^[Ss]$ ]]; then
    #        log1 ">>>skip this test..."
    #        continue
    #    elif [[ $REPLY =~ ^[Nn]$ ]]; then
    #        log1 ">>>exit..."
    #        exit 1
    #    fi
    #fi
    ## reset validation variables {{{3}}}
    # vrf_list_empty=0;ddp_not_active=0;vrf_wrong=0

}

function set_motd() { # {{{2}}}
    local progress=$1
    cat > /etc/motd << EOF
    !!!!!!TESTING IN PROGRESS ($progress DONE)!!!!!!!!
     _________________________________________
    /DANGROUS - JCNR TESTING IN PROGRESS      \
     ----------------------------------------
            \   ^__^
             \  (oo)\_______
                (__)\       )\/\
                    ||----w |
                    ||     ||
     _________________________________________
    /DANGROUS - TESTING IN PROGRESS           \
     ----------------------------------------
            \   ^__^
             \  (oo)\_______
                (__)\       )\/\
                    ||----w |
                    ||     ||
    contact ping for more info
    !!!!!!TESTING IN PROGRESS ($progress DONE)!!!!!!!!
EOF
}

function evalog() { # {{{2}}}
    usage="
        usage: evalog \"cmd\" [0|1|2]
            print cmd and output to stdout and log file
            0: don't print cmd to stdout
            1: don't print output to stdout
            2: print nothing to stdout
            3 and above: print usage
    "
    local print_cmd=true; local print_output=true
    declare -g log_file
    [ $# -eq 0 ] && echo "Usage: $usage" && return
    [ $# -eq 1 ] && print_cmd=true && print_output=true
    if [ $# -eq 2 ]; then
        [ "$2" -eq 0 ] && print_cmd=false && print_output=true
        [ "$2" -eq 1 ] && print_cmd=true && print_output=false
        [ "$2" -eq 2 ] && print_cmd=false && print_output=false
        [ "$2" -ge 3 ] && echo "Usage: $usage" && return
    fi
    $print_cmd && log1 ">>> $1" || log1 ">>> $1" 0
    $print_output && eval "$1" 2>&1 | tee -a $log_file
}

# feature specific functions {{{1}}}

function parse_file_name0() {     # {{{2}}}
    # experimental: using associative array + name reference
    # good but not portable
    # also seems more code than global variables
    local file="$1"
    local -n d_parse_file_name="$2"     # name reference
    local file_prefix="${file%.yaml}"

    d_parse_file_name["nic"]=$(echo "$file_prefix" | awk -F'-' '{print $2}')
    d_parse_file_name["core_count_str"]=$(echo "$file_prefix" | awk -F'-' '{print $3}')
    d_parse_file_name["l2l3"]=$(echo "$file_prefix" | awk -F'-' '{print $4}')
    d_parse_file_name["vermain"]=$(echo "$file_prefix" | awk -F'-' '{print $5}')
    d_parse_file_name["verminor"]=$(echo "$file_prefix" | awk -F'-' '{print $6}')
    d_parse_file_name["otherinfo"]=$(echo "$file_prefix" | awk -F'-' '{print $7}')

    # Check if vermain and verminor are both not empty
    if [ -n "${d_parse_file_name["vermain"]}" ] && [ -n "${d_parse_file_name["verminor"]}" ]; then
        d_parse_file_name["version"]="${d_parse_file_name["vermain"]}.${d_parse_file_name["verminor"]}"
    else
        d_parse_file_name["version"]=""
    fi
}

function parse_file_name() {     # {{{2}}}
    declare -g version box12 nic core_count_str l2l3 otherinfo
    declare -g version_crpd version_jcnrcni
    local file="$1"
    # values-e810-2plus2-l3-R23.3-31-bond-nc.yaml
    local file_prefix="${file%.yaml}"

    nic=$(echo "$file_prefix" | awk -F'-' '{print $2}')
    core_count_str=$(echo "$file_prefix" | awk -F'-' '{print $3}')
    l2l3=$(echo "$file_prefix" | awk -F'-' '{print $4}')
    vermain=$(echo "$file_prefix" | awk -F'-' '{print $5}')
    verminor=$(echo "$file_prefix" | awk -F'-' '{print $6}')
    otherinfo=$(echo "$file_prefix" | awk -F'-' '{print $7}')

    # Check if vermain and verminor are both not empty
    [ -n "$vermain" ] && version="$vermain"
    [ -n "$verminor" ] && version="$version-$verminor"
}

function parse_file_content() { # {{{2}}}
    local file="$1"
    declare -g nic core_count_str l2l3 version box12
    declare -g fabric_interfaces_array=()
    declare -g cpu_core_mask_list

    log1 ">>>parsing file content: $file ..."

    # fabric_interfaces_yaml {{{3}}}
    local filtered_yaml=$(grep -vE '^\s*($|#)' "$file")       #Remove empty, blank, and comment lines
    # inspect between two patterns, print lines matching the (3rd) pattern
    local fabric_interfaces_yaml=$(echo "$filtered_yaml" | awk '/fabricInterface:/,/jcnr-vrouter:/ {if (/^ *-/) print}')
    log1 ">>>fabric_interfaces_yaml: "
    log1 "\"$fabric_interfaces_yaml\""
    #- ens785f0v0:
    #- ens786f0v0:
    #- bond0:

    # slave_interfaces_yaml {{{3}}}
    # slave_interfaces_yaml=$(echo "$filtered_yaml" | awk '/bondInterfaceConfigs:/,/restoreInterfaces:/ {if (/^ *- /) print}')
    # inspect between a pattern till EOF, print lines matching another pattern
    # slave_interfaces_yaml=$(echo "$filtered_yaml" | awk '/bondInterfaceConfigs:/,0 {if (/-/) print}')
    local slave_interfaces_yaml=$(echo "$filtered_yaml" | awk '/bondInterfaceConfigs:/,/cpu_core_mask:/ {if (/^ *- /) print}')
    log1 ">>>slave_interfaces_yaml: "
    log1 "\"$slave_interfaces_yaml\""
    # - name: "bond0"
    #  - "ens785f2v0"
    #  - "ens785f3v0"

    # fabric_interfaces_array {{{3}}}
    local original_ifs="$IFS"
    # find the first non "bond0" interface
    IFS=$'\n'
        for line in $fabric_interfaces_yaml; do
            if [[ $line =~ "bond0" ]]; then
                box12="box2" #bond0 in use indicate 2box
                # continue
            fi
            local fabric_interface=$(echo "$line" | awk -F':' '{print $1}' | awk '{print $2}')
            # save it to a list
            fabric_interfaces_array+=("$fabric_interface")
        done
        echo "fabric_interfaces_array from fabric_interfaces_yaml: ${fabric_interfaces_array[@]}"

        for line in $slave_interfaces_yaml; do
            if [[ $line =~ "bond0" ]]; then
                continue
            fi
            #   - "ens785f2v0" => ens785f2v0
            fabric_interface=$(echo "$line" | awk -F'"' '{print $2}')
            # prefix with "bond0" to identify it as a slave interface
            fabric_interface="bond0-$fabric_interface"
            # save it to a list
            fabric_interfaces_array+=("$fabric_interface")
        done
        echo "final fabric_interfaces_array from yaml: ${fabric_interfaces_array[@]}"
        # ens785f0v0 ens786f0v0 bond0 bond0-ens785f2v0 bond0-ens785f3v0
    IFS="$original_ifs"

    # nic {{{3}}}
    local fabric_interface_first=${fabric_interfaces_array[0]}
    log1 "get the first fabric interface: \"$fabric_interface_first\""
    # ens785f0v0 => ens785f0 => ens785 => e810
    [[ $fabric_interface_first == *v0 ]] && fabric_interface_first="${fabric_interface_first%v0}"
    log1 "    => \"$fabric_interface_first\""
    [[ $fabric_interface_first =~ f[0-9]$ ]] && fabric_interface_first=$(echo "$fabric_interface_first" | sed 's/f.$//')
    log1 "        =>\"$fabric_interface_first\""
    nic=${if2nic["$fabric_interface_first"]}

    # core_count_str {{{3}}}
    # "10,11,42,43" => 10,11,42,43 => 2 => 2plus2
    local cpu_core_mask=$(echo "$filtered_yaml" | grep "cpu_core_mask" | awk '{print $2}')
    local cpu_core_mask="${cpu_core_mask%\"}"  # strip the ending double quote
    local cpu_core_mask="${cpu_core_mask#\"}"  # strip the leading double quote
    local core_count=$(($(echo "$cpu_core_mask" | awk -F',' '{print NF}')/2)) #Num of Fields
    core_count_str="${core_count}plus${core_count}"
    # cpu_core_mask="10,  11,12,       45"
    # normalize the cpu_core_mask string, remove extra spaces
    cpu_core_mask_list=$(echo "$cpu_core_mask" | sed 's/ //g' | sed 's/,/ /g')
    # sort it
    cpu_core_mask_list_sorted=$(echo "$cpu_core_mask_list" | tr ' ' '\n' | sort -n | tr '\n' ' ')
    cpu_core_mask_list_sorted=$(echo $cpu_core_mask_list_sorted)
    echo "cpu_core_mask_list_sorted: \"$cpu_core_mask_list_sorted\""

    # l2l3 {{{3}}}
    # if $filtered_yaml contains "interface_mode: trunk", or "vlan-id-list", then l2l3="l2"
    # otherwise, l2l3="l3"
    if [[ $filtered_yaml =~ "interface_mode: trunk" ]] || [[ $filtered_yaml =~ "vlan-id-list" ]]; then
        l2l3="l2"
    else
        l2l3="l3"
    fi

    # version {{{3}}}
    # repository: atom-docker/cn2/bazel-build/dev/
    # tag: R23.3-31
    version=$(echo "$filtered_yaml" | grep -A1 "repository: atom-docker/cn2/bazel-build/dev/" | tail -n1 | awk '{print $2}')
    version_crpd=$(echo "$filtered_yaml" | grep -A2 crpd: | grep tag: | awk '{print $2}')
    version_jcnrcni=$(echo "$filtered_yaml" | grep -A2 jcnrcni: | grep tag: | awk '{print $2}')

    log1 "nic: $nic" 3
    log1 "core_count_str: $core_count_str" 3
    log1 "l2l3: $l2l3" 3
    log1 "version: $version" 3
    log1 "version_crpd: $version_crpd" 3
    log1 "version_jcnrcni: $version_jcnrcni" 3
    log1 "box12: $box12" 3
}

function locate_valid_hc_files() { # {{{2}}}

    declare -g hc_file
    declare -g hc_file_pattern
    declare -g file_name_parse
    declare -g version box12 nic core_count_str l2l3 otherinfo
    local file

    for file in $(ls values-*.yaml | grep $hc_file_pattern); do

        # if a file name is specified stick to it {{{3}}}
        if [ -n "$hc_file" ]; then
            if [ "$hc_file" != "$file" ]; then
                continue
            fi
        fi

        # if file_name_parse is set, parse the file name {{{3}}}
        if [ "file_name_parse" == "true" ]; then
            log1 "file_name_parse set, checking file name: $file"
            parse_file_name "$file"
            log1 "  nic: $nic"
            log1 "  core_count_str: $core_count_str"
            log1 "  l2l3: $l2l3"
            log1 "  version: $version"
            log1 "  otherinfo: $otherinfo"

            # validate parsed values {{{3}}}
            if [ "$nic" != "e810" ] && [ "$nic" != "v710" ]; then
                continue
            fi
            if [ "$core_count_str" != "2plus2" ] && [ "$core_count_str" != "3plus3" ]; then
                log1 ">>>invalid core_count_str $core_count_str, skip"
                continue
            fi
            if [ "$l2l3" != "l2" ] && [ "$l2l3" != "l3" ]; then
                log1 ">>>invalid l2l3 $l2l3, skip"
                continue
            fi
            # if target_version is not specified, use all versions
            # if target_version is specified, make sure version contains target_version
            if [ -n "$target_version" ] && [[ ! "$version" =~ "$target_version" ]]; then
                log1 ">>>version $version/expected $target_version, skip"
                continue
            fi

            # dry run {{{3}}}
            if $dry_run; then
                log1 ">>>dry run: found valid helm chart file: $file..."
                continue
            else
                log1 ">>>found valid helm chart file: $file..."
            fi
        fi

        # save all valid helm chart file to a list {{{3}}}
        valid_hc_files+=("$file")
        # log1 "valid_hc_files: ${valid_hc_files[@]}"
    done

    # write list valid_hc_files content to a file {{{3}}}
    # so even if the script is killed, we can still resume from the last
    # valid_hc_files
    cd $hc_folder
    # write each item of the list in a new line
    printf "%s\n" "${valid_hc_files[@]}" >.valid_hc_files

    # this is the content of .valid_hc_files
    # values-e810-2plus2-l2-R23.3-9.yaml
    # values-e810-2plus2-l3-R23.3-9.yaml
    # values-e810-3plus3-l2-R23.3-9.yaml
    # values-e810-3plus3-l3-R23.3-9.yaml
    ## print the file in the way so that one filename per line
    #log1 "valid_hc_files:"
    #for file in "${valid_hc_files[@]}"; do
    #    log1 "  $file"
    #done
}

function config_sriov_link() {  # {{{2}}}
    # configure sriov link if needed
    # do it twice to make sure it is configured
    local link=$1
    log1 ">>>configuring sriov link: $link..."
    [[ $link == *v0 ]] && link="${link%v0}" # remove v0 from link name

    # echo 1 > /sys/bus/pci/devices/0000\:b1\:00.1/sriov_numvfs
    cat /sys/class/net/$link/device/sriov_numvfs
    echo 1 > /sys/class/net/$link/device/sriov_numvfs
    ip link set $link vf 0 spoofchk off
    ip link set $link vf 0 trust on

    sleep 2
    modprobe vfio-pci
    modprobe uio
    echo Y > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
    modprobe vfio-pci vfio_iommu_type1 allow_unsafe_interrupts=1
    sleep 2
    systemctl stop firewalld
    ip link set $link up
    ip link set "$link"v0 up
    sleep 2

    cat /sys/class/net/$link/device/sriov_numvfs

    log1 ">>>srio link $link configured"
}

function check_config_sriov() { # {{{2}}}
    # [root@node-warthog-14 ~]# ip a | grep -iE "ens785f0v0|ens786f0v0"
    # 30: ens801f1v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    # 36: ens802f1v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    # 59: ens785f0v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master __crpd-brd2 state UP group default qlen 1000
    # 60: ens786f0v0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master __crpd-brd2 state UP group default qlen 1000

    # check and configure {{{3}}}
    # if any of them is not, return 1
    declare -g -a fabric_interfaces_array
    # based on file content, check all sriov links in fabric_interface_list
    echo "fabric_interfaces_array: ${fabric_interfaces_array[@]}"
    # ens785f0v0 ens786f0v0 bond0 bond0-ens785f2v0 bond0-ens785f3v0
    log1 ">>>checking sriov link..."
    for link in ${fabric_interfaces_array[@]}; do
        log1 ">>>checking link: $link"
        [[ $link == bond0-* ]] && link="${link#bond0-}" # rm prefix "bond0-"
        [[ $link == bond0 ]] && continue                # skip bond0
        line_sriov=$(ip a | grep $link); log1 "$line_sriov"
        sriov_link_present=$(log1 "$line_sriov" | awk '{print $2}')
        sriov_link_status=$(log1 "$line_sriov" | awk -F 'state' '{print $NF}' | awk '{print $1}')
        if [ -z "$sriov_link_present" ] || [ "$sriov_link_status" != "UP" ]; then
            log1 "sriov link $link not found or not up, configuring..."
            config_sriov_link $link
            line_sriov=$(ip a | grep $link); log1 "$line_sriov"
            sriov_link_present=$(log1 "$line_sriov" | awk '{print $2}')
            sriov_link_status=$(log1 "$line_sriov" | awk -F 'state' '{print $NF}' | awk '{print $1}')
            if [ -z "$sriov_link_present" ] || [ "$sriov_link_status" != "UP" ]; then
                log1 "sriov link $link still not found or not up after configuration"
                return 1
            fi
        fi
    done
    return 0
}

function check_config_bond0() { # {{{2}}}
    desired_members=""
    declare -g desired_members_default

    echo "fabric_interfaces_array: ${fabric_interfaces_array[@]}"
    # ens785f0v0 ens786f0v0 bond0 bond0-ens785f2v0 bond0-ens785f3v0

    # collect/sort desired members from yaml {{{3}}}
    for link in ${fabric_interfaces_array[@]}; do
        if [[ $link == bond0-* ]]; then
            desired_members="$desired_members ${link#bond0-}"
        fi
    done
    desired_members=$(echo $desired_members)    # rm trailing space
    log1 "desired_members: \"$desired_members\""
    if [ -n "$desired_members" ]; then
        log1 "sorting desired_members..."
        desired_members_sorted=$(echo "$desired_members" | tr ' ' '\n' | sort | tr '\n' ' ')
        desired_members_sorted=$(echo $desired_members_sorted)  # rm trailing space
    else
        log1 ">>>no desired_members (not in hc file), use default ens785f2 ens785f3"
        desired_members_sorted=$desired_members_default
    fi

    # collect/sort current members from host {{{3}}}
    current_members_sorted=$(ip link show master bond0 | awk -F': ' '/^[0-9]+:/ {print $2}' | sort | tr '\n' ' ')
    current_members_sorted=$(echo $current_members_sorted) # rm trailing space
    log1 "current_members_sorted: \"$current_members_sorted\""

    #desired_members_sorted=$(evalog "$cmd" 0)
    log1 "desired_members_sorted: \"$desired_members_sorted\""

    # disable sriov vf if needed {{{3}}}
    for member in $desired_members_sorted; do
        # check if the member is a physical interface
        #   starting with ens and NOT ending with vN - N is a vf number)
        #   ens785f0v0
        # if the member is a physical interface, and has an sriov vf, then
        # disable the sriov vf before adding it to the bond

        # if [[ ! $member =~ v[0-9]+$ ]]; then
        if [[ $member =~ ^ens[0-9]+f[0-9]+$ ]]; then
            # if the interface has an sriov_numvfs file that contains a number > 0
            log1 "$member is a physical interface, checking sriov"
            if [ -f /sys/class/net/$member/device/sriov_numvfs ]; then
                sriov_numvfs=$(cat /sys/class/net/$member/device/sriov_numvfs)
                if [ $sriov_numvfs -gt 0 ]; then
                    log1 "$member has sriov enabled (sriov_numvfs $srio_numvfs), disabling sriov"
                    echo 0 > /sys/class/net/$member/device/sriov_numvfs
                fi
            fi
        fi
    done

    # if bond0 not present config it {{{3}}}
    if [ -z "$current_members_sorted" ]; then
        log1 "bond0 not present, configuring..."
        ip link add name bond0 type bond mode 1 miimon 100
        echo "adding desired members: $desired_members_sorted into bond0..."

        for member in $desired_members_sorted; do
            evalog "ip link set $member down"
            evalog "ip link set $member master bond0"
            evalog "ip link set $member up"
        done
    fi

    # if bond0 present, correct members if not match {{{3}}}
    if [ -n "$current_members_sorted" ]; then
        # bond0 is already configured; check if it matches the desired configuration
        if [ "$current_members_sorted" != "$desired_members_sorted" ]; then
            echo "reconfiguring bond0 with desired members: $desired_members"

            echo "removing current members: $current_members_sorted"
            for member in $current_members_sorted; do
                ip link set $member down
                ip link set $member nomaster
            done

            # Add the desired members
            echo "add desired members: $desired_members_sorted"
            for member in $desired_members_sorted; do
                ip link set $member down
                ip link set $member master bond0
                ip link set $member up
            done
        else
            echo "bond0 is already configured with the desired members: $desired_members"
        fi
    fi

    # verify after config {{{3}}}
    # if bond0 still not up or member links are not same as desired, return 1
    cmd="ip link set bond0 up; sleep 2"
    evalog "$cmd"
    current_members_sorted=$(ip link show master bond0 | awk -F': ' '/^[0-9]+:/ {print $2}' | sort | tr '\n' ' ')
    current_members_sorted=$(echo $current_members_sorted) # rm trailing space
    echo "current_members_sorted: \"$current_members_sorted\""
    echo "desired_members_sorted: \"$desired_members_sorted\""
    # check if bond0 is up
    bond0_status=$(ip link show bond0 | grep bond0 | awk -F 'state' '{print $NF}' | awk '{print $1}')
    echo "bond0_status: \"$bond0_status\""

    if [ "$bond0_status" != "UP" ] || [ "$current_members_sorted" != "$desired_members_sorted" ]; then
        log1 "bond0 is not up or member links are not same as desired after configuration"
        return 1
    fi

    return 0
}

function bind_nic_to_kernel() { # {{{2}}}
    # [root@node-warthog-14 ~]# dpdk-devbind.py -s | head
    # Network devices using DPDK-compatible driver
    # ============================================
    # 0000:b1:00.1 'Ethernet Controller XXV710 for 25GbE SFP28 158b' drv=vfio-pci unused=i40e
    # 0000:ca:00.1 'Ethernet Controller XXV710 for 25GbE SFP28 158b' drv=vfio-pci unused=i40e
    # 0000:31:00.0 'Ethernet Controller E810-C for SFP 1593' drv=vfio-pci unused=ice
    # 0000:4b:00.0 'Ethernet Controller E810-C for SFP 1593' drv=vfio-pci unused=ice
    #
    #dpdk-devbind.py -b ice     0000:31:00.0 0000:4b:00.0
    #dpdk-devbind.py -b i40e    0000:b1:00.1 0000:ca:00.1

    log1 ">>>check is there still any nic binding in dpdk..."
    nic_binding=$(dpdk-devbind.py -s | grep "drv=vfio-pci")
    log1 "$nic_binding"
    if [ -z "$nic_binding" ]; then
        log1 ">>>no nic binding left in dpdk, OK to proceed"
    else
        log1 ">>>there are still nic bindings in dpdk, unbinding them ..."
        # get the "unused=xx" column
        # log1 "$nic_binding" | awk '{print $1}' | xargs -I {} dpdk-devbind.py -b $unused_drv {}
        # loop through each line, get the "unused=xx" column
        while read -r line; do
            # get the "unused=xx" column
            unused_drv=$(echo "$line" | awk -F "unused=" '{print $2}' | awk '{print $1}')
            # if the column is not empty, then we need to bind it
            if [ -n "$unused_drv" ]; then
                nic_pci=$(echo $line | awk '{print $1}')    # get the nic_pci
                log1 ">>>binding $nic_pci to kernel($unused_drv)..."
                dpdk-devbind.py -b $unused_drv $nic_pci     # bind it
            fi
        done <<< "$nic_binding"
    fi
}

function check_config_ip_address() { # {{{2}}}
    # iterate through fabric interfaces in fabric_interfaces_array
    # if interface has no ip configured, configure it using interface ip provided in if2ip
    # if interface has ip configured, check if it matches the ip provided in if2ip
    declare -g fabric_interfaces_array
    declare -g if2ip

    for interface in "${fabric_interfaces_array[@]}"; do
        if [[ ! "$interface" =~ bond0 ]]; then
            ipv4_address=$(ip addr show $interface | grep "inet\b" | awk '{print $2}')
            ipv6_address=$(ip addr show $interface | grep "inet6\b" | grep global | awk '{print $2}')

            if [ -z "$ipv4_address" ]; then
                log1 ">>>interface $interface has no ip configured, configuring it..."
                ipv4_address=$(echo ${if2ip[$interface]} | awk '{print $1}')
                if [ -z "$ipv4_address" ]; then
                    log1 ">>> no ipv4 address given for interface $interface"
                    return 1
                else
                    log1 ">>> ipv4 address given for interface $interface: $ipv4_address"
                fi
                ip addr add $ipv4_address dev $interface || return 1
                ip link set $interface up || return 1

                ipv4_address=$(ip addr show $interface | grep "inet\b" | awk '{print $2}')
                if [ -z "$ipv4_address" ]; then
                    log1 ">>>interface $interface still has no ipv4 address after configuration ..."
                    return 1
                fi
                log1 ">>>interface $interface ip is now configured: $ipv4_address"
            else
                log1 ">>>interface $interface already has ipv4 address configured: $ipv4_address"
                # compare the current ip address configured with the one in if2ip
                # if they are different, then remove the current ip address and reconfigure it
                if [ "$ipv4_address" != "${if2ip[$interface]}" ]; then
                    log1 ">>>interface $interface ipv4 address is different from the one in if2ip, reconfiguring it..."
                    ip addr del $ipv4_address dev $interface || return 1
                    ipv4_address=${if2ip[$interface]}
                    ip addr add $ipv4_address dev $interface || return 1
                    ip link set $interface up || return 1
                    ipv4_address=$(ip addr show $interface | grep "inet\b" | awk '{print $2}')
                    if [ "$ipv4_address" != "${if2ip[$interface]}" ]; then
                        log1 ">>>interface $interface ipv4 is still different from the one in if2ip after reconfiguration..."
                        return 1
                    fi
                    log1 ">>>interface $interface ipv4 address is now configured: $ipv4_address"
                fi

            fi

            if [ -z "$ipv6_address" ]; then
                log1 ">>>interface $interface has no ip configured, configuring it..."
                ipv6_address=$(echo ${if2ip[$interface]} | awk '{print $2}')
                if [ -z "$ipv6_address" ]; then
                    log1 ">>> no ipv6 address given for interface $interface"
                    return 1
                else
                    log1 ">>> ipv6 address given for interface $interface: $ipv6_address"
                fi
                ip addr add $ipv6_address dev $interface || return 1
                ip link set $interface up || return 1

                ipv6_address=$(ip addr show $interface | grep "inet\b" | awk '{print $2}')
                if [ -z "$ipv6_address" ]; then
                    log1 ">>>interface $interface still has no ipv6 address after configuration ..."
                    return 1
                fi
                log1 ">>>interface $interface ip is now configured: $ipv6_address"
            else
                log1 ">>>interface $interface already has ipv6 address configured: $ipv6_address"
                # compare the current ip address configured with the one in if2ip
                # if they are different, then remove the current ip address and reconfigure it
                if [ "$ipv6_address" != "${if2ip[$interface]}" ]; then
                    log1 ">>>interface $interface ipv6 address is different from the one in if2ip, reconfiguring it..."
                    ip addr del $ipv6_address dev $interface || return 1
                    ipv6_address=${if2ip[$interface]}
                    ip addr add $ipv6_address dev $interface || return 1
                    ip link set $interface up || return 1
                    ipv6_address=$(ip addr show $interface | grep "inet\b" | awk '{print $2}')
                    if [ "$ipv6_address" != "${if2ip[$interface]}" ]; then
                        log1 ">>>interface $interface ipv6 is still different from the one in if2ip after reconfiguration..."
                        return 1
                    fi
                    log1 ">>>interface $interface ipv6 address is now configured: $ipv6_address"
                fi

            fi
        fi
    done



    return 0
}

function hc_deletion_validation() {  # {{{2}}}
    local counter
    declare -g version box12 nic core_count_str l2l3 otherinfo
    declare -g -a fabric_interfaces_array

    log1 "\n=== validate helm chart deletion"
    # namespace "contrail*" deletion {{{3}}}
    log1 ">>>checking namespace contrail..."
    contrail_namespace=$(kubectl get namespaces | grep contrail | awk '{print $1}')
    while [ -n "$contrail_namespace" ]; do
        log1 "namespace/expected: \"$contrail_namespace\"/None, recheck after 20 seconds..."
        sleep 20
        contrail_namespace=$(kubectl get namespaces | grep contrail | awk '{print $1}')
    done
    log1 "namespace \"$contrail_namespace\"/expected None - OK to proceed"

    # vrouter pod deletion {{{3}}}
    log1 ">>>checking vrouter pod..."
    vrouter_pod=$(kubectl get pods -n contrail | grep vrouter | awk '{print $1}')
    while [ -n "$vrouter_pod" ]; do
        log1 "vrouter pod/expected: \"$vrouter_pod\"/None, recheck after 20 seconds..."
        sleep 20
        vrouter_pod=$(kubectl get pods -n contrail | grep vrouter | awk '{print $1}')
    done
    log1 "vrouter pod \"$vrouter_pod\"/expected None - OK to proceed"

    # crpd pod deletion {{{3}}}
    local counter=0
    # wait for 60+s for crpd pod to be deleted
    while [ $counter -lt 3 ]; do
        log1 ">>>checking crpd pod..."
        crpd_pod=$(kubectl get pods -n jcnr | grep crpd | awk '{print $1}')
        if [ -n "$crpd_pod" ]; then
            msg="crpd pod/expected: \"$crpd_pod\"/None, "
            msg="$msg recheck after 20 seconds...($counter/max 3)"
            log1 $msg
            sleep 20
        else
            log1 "crpd pod \"$crpd_pod\"/expected None - OK to proceed"
            break
        fi
        counter=$((counter + 1))
    done

    # if crpd pod still exists, force delete it
    if [ $counter -eq 3 ]; then
        log1 "cprd pod force deletion..."
        cmd="kubectl delete pod $crpd_pod --namespace jcnr --grace-period=0 --force"
        evalog "$cmd"
    fi

    # if crpd pod still exists, exit
    crpd_pod=$(kubectl get pods -n jcnr | grep crpd | awk '{print $1}')
    if [ -n "$crpd_pod" ]; then
        log1 "crpd deletion failed, exit"
        exit 1
    else
        log1 "crpd pod \"$crpd_pod\"/expected None - OK to proceed"
    fi

    # delete stale vrouter info {{{3}}}
    log1 ">>>deleting stale vrouter info..."
    cmd="rm -rf /var/run/vrouter"
    evalog "$cmd"
    # check if there is any stale port info, most likely there is none
    cmd="ls /var/lib/contrail/ports/"
    evalog "$cmd"
    # rm /var/lib/contrail/ports/08643fdc-8556-5f7d-89b6-10440307031d
    # check if /var/run/vrouter exists
    if [ -d "/var/run/vrouter" ]; then
        log1 ">>>there is still stale vrouter info, please check..."
        exit 1
    else
        log1 ">>>no stale vrouter info, OK to proceed"
    fi

    # bind nic to kernel {{{3}}}
    bind_nic_to_kernel
    nic_binding=$(dpdk-devbind.py -s | grep "drv=vfio-pci")
    log1 "$nic_binding"
    if [ -z "$nic_binding" ]; then
        log1 ">>>no nic binding left in dpdk, OK to proceed"
    else
        log1 ">>>there are still nics bound in dpdk, please check..."
        exit 1
    fi

    # l2: sriov link {{{3}}}
    # for l2, we need to check if sriov link is up
    # if not, configure them
    # e810: ens785f0v0 ens786f0v0
    # v710: ens801f1v0 ens802f1v0
    if [ "$l2l3" == "l2" ]; then
        log1 ">>>l2 mode, checking sriov link..."
        if check_config_sriov; then
            log1 ">>>all sriov links are ready, OK to proceed"
        else
            log1 "sriov link configuration failed ..."
            log1 ">>>at least one sriov link is not present or down, exit"
            exit 1
        fi
    else
        log1 ">>>not l2 mode, no need to check sriov link"
    fi

    # l3: config ip address {{{3}}}
    # find all interfaces not starting with "bond0", and check if ip address is configured
    # if not, configure them
    if [ "$l2l3" == "l3" ]; then
        log1 ">>>l3 mode, checking ip address..."
        if check_config_ip_address; then
            log1 ">>>all interfaces have ip address configured, OK to proceed"
        else
            log1 ">>>at least one interface does not have ip address configured, exit"
            exit 1
        fi
    else
        log1 ">>>not l3 mode, no need to check ip address"
    fi

    # check bond0 if configured {{{3}}}
    # if fabric_interfaces_array contains any interface with:
    #    a name "bond0"
    #    a name with a prefix of "bond0-", check bond0
    # otherwise, skip
    if [[ "${fabric_interfaces_array[@]}" =~ bond0 ]]; then
        log1 ">>>bond0 is configured in fabric_interfaces_array, checking bond0..."
        if check_config_bond0; then
            log1 ">>>bond0 is ready, OK to proceed"
        else
            log1 ">>>bond0 is still not ready, exit"
            exit 1
        fi
    else
        log1 ">>>bond0 is not in fabric_interfaces_array, skip bond0 checking..."
    fi

    # crd deletion {{{3}}}
    # https://contrail-jws.atlassian.net/browse/JCNR-4338
    # these crd are not deleted by the operator, need to delete them manually
    # [root@node-warthog-14 jcnr233]# kubectl get crd | grep juniper
    # apiservers.configplane.juniper.net                    2023-08-31T22:01:08Z
    # etcds.datastore.juniper.net                           2023-08-31T22:01:10Z
    # vrouters.dataplane.juniper.net                        2023-08-31T23:04:14Z

    # get crd list
    log1 ">>>checking crd..."
    crd_list=$(kubectl get crd | grep juniper | awk '{print $1}')
    # delete them
    for crd in $crd_list; do
        # log1 ">>>deleting crd $crd..."
        kubectl delete crd $crd
    done
    crd_list=$(kubectl get crd | grep juniper | awk '{print $1}')
    if [ -z "$crd_list" ]; then
        log1 ">>>crd deleted, OK to proceed"
    else
        log1 ">>>crd not deleted, please check"
        exit 1
    fi
}

function hc_installation_verification() {       # {{{2}}}
    local counter=0
    local counter_ready_xy=0
    local vrouter_pod_status
    local crpd_pod_status
    local vrouter_pod_ready_x
    local vrouter_pod_ready_y
    local crpd_pod_ready_y
    local crpd_pod_ready_x
    local counter_ready_xy

    declare -g version box12 nic core_count_str l2l3 otherinfo
    declare -g cpu_core_mask_list_sorted

    log1 "\n=== checking installation status..."
    # vrouter/crpd pod status {{{3}}}
    # make sure vrouter pod and crpd pod are running at the same time
    # check 3 times, if anytime any of them is not running, reset the counter and repeat
    # if after 3 times, each time both of them are running, then we are good to proceed
    log1 ">>>checking vrouter pod and crpd pod status..."
    local vrouter_pod_status=$(kubectl get pods -n contrail | grep vrouter | awk '{print $3}')
    local crpd_pod_status=$(kubectl get pods -n jcnr | grep crpd | awk '{print $3}')

    while [ $counter -lt 3 ]; do
        # if vrouter pod or crpd pod is not running, reset counter and repeat
        if [ "$vrouter_pod_status" != "Running" ] || \
           [ "$crpd_pod_status" != "Running" ]; then
            msg="vrouter pod status/expected:"
            msg="$msg \"$vrouter_pod_status\"/\"Running\","
            msg="$msg crpd pod status/expected: \"$crpd_pod_status\"/Running,"
            msg="$msg recheck after 20 seconds..."
            log1 "$msg"
            sleep 20
            counter=0
        else
            # if vrouter pod and crpd pod are both running, increment counter
            msg="vrouter pod status/expected:"
            msg="$msg \"$vrouter_pod_status\"/\"Running\","
            msg="$msg \"crpd pod status/expected: \"$crpd_pod_status\"/"
            msg="$msg \"Running, counter: $counter (3 to proceed)"
            log1 "$msg"

            # also check "Ready" and make sure it is "x/y" where x == y
            vrouter_pod_ready=$(kubectl get pods -n contrail | grep vrouter | awk '{print $2}')
            crpd_pod_ready=$(kubectl get pods -n jcnr | grep crpd | awk '{print $2}')
            vrouter_pod_ready_x=$(log1 $vrouter_pod_ready | awk -F'/' '{print $1}')
            vrouter_pod_ready_y=$(log1 $vrouter_pod_ready | awk -F'/' '{print $2}')
            crpd_pod_ready_x=$(log1 $crpd_pod_ready | awk -F'/' '{print $1}')
            crpd_pod_ready_y=$(log1 $crpd_pod_ready | awk -F'/' '{print $2}')
            if [ "$vrouter_pod_ready_x" != "$vrouter_pod_ready_y" ] || \
               [ "$crpd_pod_ready_x" != "$crpd_pod_ready_y" ]; then
                log1 "vrouter pod ready/expected: \"$vrouter_pod_ready\", crpd pod ready/expected: \"$crpd_pod_ready\""
                counter=0
                counter_ready_xy=$((counter_ready_xy + 1))
            else
                if $fast_deploy; then
                    log1 "fast mode, skip checking more times, OK to proceed"
                    break
                fi
            fi
            sleep 20
            counter=$((counter + 1))
        fi
        vrouter_pod_status=$(kubectl get pods -n contrail | grep vrouter | awk '{print $3}')
        crpd_pod_status=$(kubectl get pods -n jcnr | grep crpd | awk '{print $3}')

        # if counter_ready_xy is too big, need user to confirm to proceed
        if [ $counter_ready_xy -gt 30 ]; then
            log1 "stuck at current status for too long, please check"
            return 1
        fi
    done
    msg="vrouter pod status/expected status is \"$vrouter_pod_status\"/\"Running\", crpd pod status/expected status is \"$crpd_pod_status\"/Running - OK to proceed"
    log1 "$msg"

    # vif list {{{3}}}
    sleep 5
    log1 ">>>get vif list..."
    vrf_list=$(vr vif --list);log1 "$vrf_list"
    # if vrf_list is empty, ask user to confirm before proceeding
    if [ -z "$vrf_list" ]; then
        log1 ">>>vrf list is empty"
        #vrf_list_empty=1
        return 1
    else
        log1 ">>>vrf list is not empty - OK to proceed"
    fi

    # l2: e810 ddp {{{3}}}
    if [ "$nic" == "e810" ] && [ "$l2l3" == "l2" ]; then
        log1 ">>>for e810 nic running in l2, check ddp config..."
        cmd="vr dpdkinfo --ddp list-flow"
        local ddp_list_flow=$(evalog "$cmd")
        if [[ ! "$ddp_list_flow" =~ "GTPU" ]]; then
            log1 ">>>ddp is not active..."
            #ddp_not_active=1
            return 1
        else
            log1 ">>>ddp is active - OK to proceed"
        fi
    else
        log1 ">>>for \"$nic\" nic running in $l2l3, no need to check ddp config!"
    fi

    # cpu pinning dpdk verification {{{3}}}
    log1 ">>>get dpdk cpupin..."
    dpdk_cpupin1=$(ps -eT -o psr,tid,comm,pid,ppid,cmd,pcpu,stat | grep dpdk)
    dpdk_cpupin2=$(ps -eT -o psr,tid,comm,pid,ppid,cmd,pcpu,stat | grep -iE "Rl|RLl")
    dpdk_cpu_list=$(echo "$dpdk_cpupin2" | grep -v grep | awk '{print $1}')
    dpdk_cpu_list_sorted=$(echo "$dpdk_cpu_list" | sort -n | uniq)
    dpdk_cpu_list_sorted=$(echo $dpdk_cpu_list_sorted)
    echo "dpdk_cpu_list_sorted: \"$dpdk_cpu_list_sorted\""
    # compare with cpu_core_mask_list_sorted
    # if not the same, give warning but not exit
    log1 ">>>current dpdk cpu pinning vs cpu core mask list:"
    log1 "\"$dpdk_cpu_list_sorted\":\"$cpu_core_mask_list_sorted\""
    if [ "$dpdk_cpu_list_sorted" != "$cpu_core_mask_list_sorted" ]; then
        log1 ">>>dpdk cpu pinning is not the same as cpu core mask list"
        dpdk_cpu_pinning_not_same=1
        return 1
    else
        log1 ">>>dpdk cpu pinning is the same as cpu core mask list - OK to proceed"
    fi

    # cpu power mode verification {{{3}}}
    # if any output is not "performance", configure to "performance"
    if [ -z "$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | grep -v performance)" ]; then
        log1 ">>>cpu power mode is \"performance\" - OK to proceed"
    else
        log1 ">>>cpu power mode is not \"performance\" - configure to \"performance\""
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor ; do echo performance > $f ; cat $f; done
    fi

    return 0
}

function vrf_verification() {      # {{{2}}}
    # return false if any of the below is false
    # 1. arp is resolved (ip neighbor show)
    # 2. ndp is resolved (ip -6 neigh show)
    # 3. vif is assigned with correct (not 0) vrf
    #   [root@node-warthog-14 jcnrtests]# vr vif -l
    #   vif0/3      PMD: ens801f1 NH: 10 MTU: 9000
    #               Type:Host HWaddr:40:a6:b7:9b:04:39 IPaddr:10.220.220.1
    #               IP6addr:2001::1
    #               DDP: OFF SwLB: ON
    #               Vrf:1 Mcast Vrf:65535 Flags:L3DProxyEr QOS:-1 Ref:11 TxXVif:1
    #   vif0/4      PMD: ens802f1 NH: 14 MTU: 9000
    #               Type:Host HWaddr:40:a6:b7:9a:fe:b9 IPaddr:10.230.230.1
    #               IP6addr:2002::1
    #               DDP: OFF SwLB: ON
    #               Vrf:1 Mcast Vrf:65535 Flags:L3DProxyEr QOS:-1 Ref:11 TxXVif:2
    declare -g fabric_interfaces_array

    # get PMD vif list
    cmd="vr vif -l"
    local vif_list=$(evalog "$cmd")
    # iterate through fabric_interfaces_array, check if PMD is assigned to the correct vif
    # if not, return false
    # else return true
    for fabric_interface in $fabric_interfaces_array; do
        local vif=$(echo "$vif_list" | grep -A 6 "$fabric_interface" | grep "PMD:" | awk '{print $1}')
        local vrf=$(echo "$vif_list" | grep -A 6 "$fabric_interface" | grep "Vrf:" | awk '{print $1}' | awk -F: '{print $2}')
        log1 "vif:$vif Vrf:$vrf"
        if [ $vrf -eq 0 ] || [ $vrf -eq 65535 ]; then
            log1 "vif:$vif Vrf:$vrf - vrf assignment failed!"
            exit 1
        fi
    done
}

function pretest_validation() {  # {{{2}}}
    local nic=$1
    local l2l3=$2

    # l2 validation
    if [ "$l2l3" == "l2" ]; then
        # 1. mac is learned
        # Bridging domain VLAN id : 100
        # MAC                  MAC                Logical
        # address              flags              interface
        # 00:10:94:00:00:05      D                 ens801f1v0
        # 00:10:94:00:00:07      D                 ens802f1v0
        # Bridging domain VLAN id : 101
        # MAC                  MAC                Logical
        # address              flags              interface
        # 00:10:94:00:00:06      D                 ens801f1v0
        # 00:10:94:00:00:08      D                 ens802f1v0
        crpd_mac_table=$(crpd_clic "show bridge mac-table")
        if [ $(log1 $crpd_mac_table | grep -iE "$leftlink|$rightlink" | wc -l) -lt 4 ]; then

            log1 ">>>at least one mac is not learned successfully, test is not valid"
            return 1
        fi
    fi

    # l3 name resolution validation
    if [ "$l2l3" == "l3" ]; then
        if [ $(ip neighbor show dev $nic | wc -l) -le 1 ] || \
           [ $(ip -6 neigh show dev $nic | wc -l) -le 1 ]; then
            return 1
        fi
    fi

    return 0
}

function pretest_validation2() {  # {{{2}}}
    local command=$1
    ## run pre-test in background
    ## TODO: how to cancel the ongoing test in flask server?
    ## do validations in foreground to make sure the test is valid
    ## if valid, then break the loop and run the full test in background
    ## otherwise, kill the pre-test and re-run the pre-test in background
    ## until the validation is passed
    ## if the validation is not passed after 3 times, exit
    #eval $command & pretest_pid=$!
    #log1 ">>>pre-test pid: $pretest_pid"
    #counter=0
    #while [ $counter -lt 3 ]; do
    #    log1 ">>>will validate pre-test after 60 seconds..."
    #    # if pre-test is valid, break the loop
    #    sleep 60
    #    if pretest_validation $nic $l2l3 ; then
    #        log1 ">>>pre-test is valid, go ahead to run the full test..."
    #        break
    #    # if pre-test is not valid, kill the pre-test and re-run it
    #    else
    #        log1 ">>>pre-test is not valid..."
    #        log1 ">>>killing pre-test..."
    #        kill -9 $pretest_pid
    #        log1 ">>>re-running pre-test..."
    #        pretest_pid=$(eval $command & echo $!)
    #        log1 ">>>pre-test pid: $pretest_pid"
    #    fi
    #    counter=$((counter+1))
    #done

    #if [ $counter -eq 3 ]; then
    #    log1 ">>>pre-test is not valid after 3 times..."
    #    log1 ">>>exit..."
    #    exit 1
    #else
    #    log1 ">>>running full test..."
    #    eval $command & fulltest_pid=$!
    #    log1 ">>>full-test pid: $fulltest_pid"
    #fi
}

function generate_usage() {     # {{{2}}}
    echo "Usage: $0 [options] <helm chart folder/file>"
    echo "Options:"

    for option in "${option_names[@]}"; do
        description="${option_descriptions[$option]}"
        printf "  -%s\t%s\n" "$option" "$description"
    done

    echo "Example: $0 /root/jcnr-23.3/values-e810-2plus2-l2-R23.3-9.yaml"
    echo "      deploy one specific helm chart"
    echo "Example: $0 /root/jcnr-23.3/values-e810-*.yaml"
    echo "      deploy multiple helm chart file in the folder"
    echo "Example: $0 /root/jcnr-23.3"
    echo "      deploy all values.*.yaml in the folder"
    echo "Example: $0 -s "e810 ipv6" /root/jcnr-23.3"
    echo "      deploy all values.*.yaml in the folder, for each one run e810 ipv6 test cases only"
    exit 1
}

function argsparser() {  # {{{2}}}

    # global variables and default {{{3}}}
    #echo "inside argsparser: $@"
    declare -g tags
    declare -g dry_run
    declare -g leftlink
    declare -g taskmode
    declare -g force_scan
    declare -g file_name_parse
    declare -g rightlink
    declare -g hc_file_pattern
    declare -g encap
    declare -g debug
    declare -g num_of_deploy_attempts
    declare -g fast_deploy

    declare -g options="de:fFi:l:np:r:s:t:v"
    declare -g option_names=()         # Create an array of option names
    declare -g -A option_descriptions
    declare -g OPTIND=1                # Reset in case getopts has been used previously in the shell.

    for ((i = 0; i < ${#options}; i++)); do
        char="${options:i:1}"
        if [[ "$char" == ":" ]]; then
            continue  # Skip colons used to indicate options that require arguments
        fi
        option_names+=("$char")
    done

    # option descriptions {{{3}}}
    # an associative array to store
    option_descriptions["d"]="Option d debug"
    option_descriptions["e"]="Option e encap: l2|vrf|evpn|mplsoudp"
    option_descriptions["f"]="Option f force_scan"
    option_descriptions["F"]="Option F fast_deploy"
    option_descriptions["i"]="Option h num_of_deploy_attempts (1|2|..) retry helm install if failed"
    option_descriptions["n"]="Option n dry-run"
    option_descriptions["p"]="Option p hc_file_pattern(values-*.yaml)"
    option_descriptions["s"]="Option s tags(e810|v710,ipv4|ipv6,c2|c3,148b|512b|1518b,l2|l3)"
    option_descriptions["t"]="Option t taskmode(all, deploy, test)"
    option_descriptions["v"]="Option v verbose"

    # to obsolete
    option_descriptions["F"]="Option F parse filename to get nic, core_count, l2l3, version"
    option_descriptions["l"]="Option l leftlink(ens785f0|ens801f1)"
    option_descriptions["r"]="Option r rightlink(ens786f0|ens802f1)"

    # parse options getops {{{3}}}
    while getopts "$options" opt; do
        case ${opt} in
            d ) debug="true"
                ;;
            e ) encap="$OPTARG"
                ;;
            f ) force_scan="true"
                ;;
            F ) fast_deploy="true"
                ;;
            i ) num_of_deploy_attempts="$OPTARG"
                ;;
            l ) leftlink="$OPTARG"
                ;;
            n ) dry_run="true"
                ;;
            p ) hc_file_pattern="$OPTARG"
                ;;
            r ) rightlink="$OPTARG"
                ;;
            s ) tags="$OPTARG"
                ;;
            t ) taskmode="$OPTARG"
                ;;
            v ) verbose="true"
                ;;
            \? ) echo "Invalid option: $OPTARG" 1>&2
                generate_usage
                ;;
            :) echo "Option -$OPTARG requires an argument." >&2
               generate_usage
               ;;
        esac
    done
    log1 "debug=$debug"
    log1 "encap=$encap"
    log1 "force_scan=$force_scan"
    log1 "fast_deploy=$fast_deploy"
    log1 "num_of_deploy_attempts=$num_of_deploy_attempts"
    log1 "taskmode=$taskmode"
    log1 "file_name_parse=$file_name_parse"
    log1 "leftlink=$leftlink, rightlink=$rightlink"
    log1 "dry_run=$dry_run"
    log1 "hc_file_pattern=$hc_file_pattern, "
    log1 "tags=$tags"
    log1 "verbose=$verbose"

    shift $((OPTIND -1))
    #echo "after shift inside argsparser: $@"

    # positional param {{{3}}}
    log1 "positional params: $@"
    if [ $# -eq 0 ]; then
        echo "No helm chart folder/file specified"
        generate_usage
    else
        # same all positional params to a list
        pos_params="$@"
        log1 "pos_params: $pos_params"
    fi
}

function get_hc_files() {  # {{{2}}}
    # loop through positional params
    # for each param:
    #   if it is a folder:
    #       iterate all helm chart in the folder and save them to valid_hc_files
    #   if it is a file:
    #       save it to valid_hc_files
    #   if same file already exists in valid_hc_files, then skip it
    #   also get the folder name of the hc file
    declare -g valid_hc_files
    declare -g valid_hc_files_count
    declare -g hc_folder
    declare -g pos_params

    for hc_file in $pos_params; do
        echo -n "hc_file: $hc_file ..."
        if [ -d $hc_file ]; then
            echo "is a folder..."
            hc_folder=$hc_file
            # iterate all helm chart in the folder and save them to valid_hc_files
            for file in $hc_file/$hc_file_pattern;
            do
                echo -n "  file: $file..."
                if [ -f $file ]; then
                    echo -n "is a file..."
                    # if same file already exists in valid_hc_files, then skip it
                    if [[ " ${valid_hc_files[@]} " =~ " ${file} " ]]; then
                        echo "already exists in valid_hc_files, skip it"
                    else
                        echo "not exists in valid_hc_files, add it"
                        valid_hc_files="$valid_hc_files $file"
                    fi
                else
                    echo "is not a file, skip it"
                fi
            done
        elif [ -f $hc_file ]; then
            echo -n "is a file..."
            hc_folder=$(dirname $hc_file)
            # if same file already exists in valid_hc_files, then skip it
            if [[ " ${valid_hc_files[@]} " =~ " ${hc_file} " ]]; then
                echo "already exists in valid_hc_files, skip it"
            else
                echo "not exists in valid_hc_files, add it"
                valid_hc_files="$valid_hc_files $hc_file"
            fi
        else
            echo "is not a folder nor a file, skip it"
        fi
    done
    echo "hc_folder: $hc_folder"

    cd $hc_folder
        # if .valid_hc_files exists, read the file content into valid_hc_files variable
        # else, call get_hc_files to get valid_hc_files and write it to .valid_hc_files
        if [ -f .valid_hc_files ] && [ $force_scan == "false" ]; then
            log1 ".valid_hc_files exists, reading from it..."
            valid_hc_files=$(cat .valid_hc_files)  #read file
        else
            log1 ".valid_hc_files not exists or force_scan is true, writing to it..."
            # write valid_hc_files to .valid_hc_files
            # make sure each hc_file is in a line
            > .valid_hc_files
            for hc_file in $valid_hc_files; do
                echo $hc_file >> .valid_hc_files
            done
        fi

        echo "final valid_hc_files: "
        echo "$valid_hc_files"
        echo ".valid_hc_files:"
        cat .valid_hc_files
    cd ..

    valid_hc_files_count=$(echo $valid_hc_files | wc -w | xargs) # count, rm trailing spaces
    log1 "valid_hc_files_count: $valid_hc_files_count"
}

function collect_basic_test_env_info() {  # {{{2}}}

    # collect basic test env info
    #   linux platform and kernel version
    #   cpu model
    #   hugepage and memory size
    #   ice version
    #   dpdk version
    declare -g fabric_interfaces_array

    # linux platform and kernel version {{{3}}}
    evalog "uname -a"
    evalog "cat /etc/os-release"
    evalog "lscpu"
    evalog "cat /proc/cpuinfo | grep -i huge"
    evalog "modinfo ice"
    for interface in "${fabric_interfaces_array[@]}"; do
        if [[ $interface != bond0* ]]; then
            evalog "ethtool -i $interface"
        fi
    done

    # dpdk info {{{3}}}
    evalog "ps -eT -o psr,tid,comm,pid,ppid,cmd,pcpu,stat | grep dpdk"
    evalog "vr dpdkinfo --ddp list-flow"
    evalog "vr dpdkinfo -b"
    evalog "vr dpdkinfo -c"
}

init_vars
