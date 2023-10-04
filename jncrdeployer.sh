#!/usr/bin/env bash

# Description: Run all test cases for jcnr
# Author: Ping
# Note: This script is used to run all test cases for jcnr
#      It will switch helm chart, load crpd config, and run perf test
#      It will run test for all combinations of nic, core_count, l2/l3
#      better run it in screen or tmux session during the night
#
# TODO history: {{{1}}}
#
#   add auto download of latest hc tar ball (2023-08-31)
#   added sriov check (2023-08-31)
#   deploy one specific helm chart and test (2023-08-31)
#   add check after delete - before install (2023-08-31)
#   setup a motd to show the progress, (2023-09-02)
#   added logs, (2023-09-02)
#   modularize the code (2023-09-05)
#   add CLI options (2023-09-06)
#       include dry-run
#       add deploy-only/test-only option
#       proceed/skip/exit/wait_user on error
#   add precheck before run full test?  #---<not able to do>
#       workarounded by running same test at least twice
#       often result is very bad, not complete, or even empty, make it useless
#       start test,
#       prechecking,
#       stop test,
#       cleanup, run full test
#   remove global variables from functions              #<---won't do>
#   move CLI options behind positional arguments        #<---won't do>
#   parse yaml file to get nic, core_count, l2/l3, version      #<---done>
#       remove requirement of filename format
#       use these info as internal tags
#       extract interface name, if v0, configure sriov
#   for l3 mode, add bond0 config before deploy         done 2023-09-22
#   in yaml, add control over which test to run with which hc file      #---<won't do>
#       better do it in main python script from remote
#   added cpu power mode check (2023-09-23)
#   added num_of_deploy_attempts (2023-09-23)
#   added basic test env info collection (2023-09-23)
#   generate hc yaml based on template?                 #---<won't do>

source jcnrdeployer_libs.sh
function download_hc() {        #{{{1}}}
    helm_url=https://svl-artifactory.juniper.net/artifactory/contrail/jcnr/helm/internal/
    hc_tarball_folder=/var/tmp/
    hc_working_folder=/root/ping-jcnr-test-helm-charts/ping-jcnr2
    # current_date=27-Sep-2023
    current_date=$(date +%d-%b-%Y)
    log1 $current_date
    cmd="curl -s $helm_url |  grep -i $current_date | grep -o 'jcnr-2[^ \"]*\.tgz' | sort -u"
    evalog "$cmd"
    # jcnr-23.3.0-186.tgz
    while true; do
        log1 "Checking for releases on $current_date"
        # cmd1="curl -s $helm_url | grep -i $current_date"
        # cmd1_op=$(evalog "$cmd1" 0)
        # cmd2="echo \"$cmd1_op\" | grep -o 'jcnr-2[^ >\"]*\.tgz' | sort -u"
        cmd="curl -s $helm_url |  grep -i $current_date | grep -o 'jcnr-2[^ \"]*\.tgz' | sort -u"
        releases=$(evalog "$cmd" 0)
        log1 "releases: $releases"

        if [ -n "$releases" ]; then
            echo "New releases found on $current_date:"
            echo "$releases"
            break
        fi
        # Decrement the date by 1 day
        current_date=$(date -d "$current_date - 1 day" +%d-%b-%Y)
    done

    # download the latest hc tar ball with wget
    cmd="wget -q -O $hc_tarball_folder/$releases $helm_url/$releases"
    evalog "$cmd"
    # extract hc tar ball into a hc_working_folder and
    cmd="tar -xzf $hc_tarball_folder/$releases -C $hc_working_folder"
    evalog "$cmd"
    # rename the folder to the same as hc tar ball without the .tgz extension
    mv $hc_working_folder/jcnr $hc_working_folder/${releases%.tgz}
}

function update_hc() {       #{{{1}}}
    # update helm chart files based on downloaded hc tar ball
    # extract hc tar ball to a folder
    # rename the folder to jcnr
    pass
}

get_hc_files
cd $hc_folder
for hc_file in $valid_hc_files; do

# main {{{1}}}

script_basename=$(basename "$0")                # get basename of current script

# parse args {{{2}}}
log1 "= test start @ $(date +%Y-%m-%d-%H:%M:%S) ="
argsparser "$@"

# loop: get hc files and iterate {{{2}}}

# download latest hc tar ball {{{3}}}
    # calculate testing progress {{{3}}}
    # showing x out of y hc files is being processed
    ((hc_file_count++))
    progress_div=$hc_file_count/${valid_hc_files_count}_hc_files
    progress_perc=$(log1 "scale=2; $hc_file_count/$valid_hc_files_count*100" | bc)
    progress_perc=$(printf "%.0f" $progress_perc)
    progress_perc="$progress_perc%"
    progress="$progress_div/$progress_perc"
    log1 "\n== working on hc file: $hc_file ($progress)..." && sleep 2

    # get nic/l2l3/core_count_str/version {{{3}}}
    parse_file_content "$hc_file"
    # <<< $( [ "$file_name_parse" == "false" ] && parse_file_content "$hc_file" || parse_file_name "$hc_file" )

    log1 "parsed info from $hc_file:"
    log1 "  nic: $nic"
    log1 "  core_count_str: $core_count_str"
    log1 "  l2l3: $l2l3"
    log1 "  version: $version"
    log1 "  box12: $box12"

    # taskmode deploy {{{3}}}
    if [ "$taskmode" == "all" ] || [ "$taskmode" == "deploy" ]; then

        for ((i=1; i<=$num_of_deploy_attempts; i++)); do
            if [ "$num_of_deploy_attempts" -ge 1 ]; then
                log1 "num_of_deploy_attempts: $i/$num_of_deploy_attempts"
            fi

            progress="$progress/$i/${num_of_deploy_attempts}_deploy_attempts"


            # delete hc&verify {{{4}}}
            log1 "\n=== deleting helm chart ($progress)..." && sleep 2
            cmd="helm ls --all-namespaces | grep jcnr | awk '{print \$1}' | xargs"
            hc_jcnr=$(evalog "$cmd" 0)
            cmd="helm delete $hc_jcnr --no-hooks"
            [ -n "$hc_jcnr" ] && evalog "$cmd" && sleep 10 || log1 "no helm chart to delete"
            hc_deletion_validation

            # install hc$verify {{{4}}}
            log1 "\n=== installing helm chart with $hc_file ($progress)..." && sleep 2
            cmd="helm install -f $hc_file jcnr . ; sleep 10"
            evalog "$cmd"

            if hc_installation_verification; then
                log1 "helm chart installed successfully"
                break
            else
                log1 "helm chart installation failed ..."
                if [ "$i" == "$num_of_deploy_attempts" ]; then
                    log1 "deploy failed, exiting..."
                    exit 1
                else
                    log1 "trying to delete and deploy helm chart again..."
                fi
            fi
        done

        # l3: load crpd config&verify vrf {{{4}}}
        if [ "$l2l3" == "l3" ]; then
            log1 ">>>creating crpd l3 config file..."
            create_crpd_config
            log1 ">>>loading crpd l3 config..."
            load_crpd_config
            log1 ">>>crpd l3 config loaded:"
            crpd_clic "show config | compare rollback 1"
            vrf_verification
        fi

        # basic test env info collection {{{4}}}
        log1 "\n=== collecting basic test env info..."
        log_file_ori=$log_file
        log_file=$hc_file-$version-$nic-$l2l3-$core_count_str-$box12-env_info.log
        collect_basic_test_env_info
        log_file=$log_file_ori
    fi

    # taskmode test {{{3}}}
    if [ "$taskmode" == "all" ] || [ "$taskmode" == "test" ]; then
        # broadcast test progress {{{4}}}
        log1 ">>>running test...$hc_file ($progress)"
        set_motd $progress
        # broadcast a message to all users
        wall ">>>running test...$hc_file ($progress)"

        # run test {{{4}}}
        note="$version-$l2l3-$nic-$core_count_str"

        command="python3 jcnrtests.py \
                -s $l2l3 $nic $box12 seperated \
                -n $note -u $url -r"

        cd ~/jcnrtests
            log1 $command
            eval $command
            #pretest_validation $command
        cd -
    fi

    # post-test cleaning {{{4}}}
    # delete helm chart filename from .valid_helm_charts file
    # so that it will not be used for next test if script is run again
    log1 ">>>deleting helm chart filename from .valid_helm_charts file..."
    # $ cat .valid_hc_files
    # /Users/pings/Downloads/jcnr233/values-e810-2plus2-l2-R23.3-31-bond-nc.yaml
    # /Users/pings/Downloads/jcnr233/values-e810-2plus2-l2-R23.3-31-nc.yaml

    #sed -i "s/$hc_file//" .valid_hc_files
    sed -i "\|^$hc_file$|d" .valid_hc_files

    # clear motd by emptying /etc/motd file
    wall ">>>test done: $hc_file ($progress)"
    log1 ">>>clearing motd..."
    log1 "" > /etc/motd
done

# after all tests {{{2}}}
# delete .valid_hc_files file
log1 ">>>deleting .valid_hc_files file..."
rm -f .valid_hc_files
