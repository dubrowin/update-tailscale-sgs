#!/bin/bash

################################
## Figure out public IPs
## for tailscale devices
## and update Security Groups
## to allow the proper
## NAT Traversal IP
##
## By: Shlomo Dubrowin
## On: Sept 10, 2023
################################

################################
## Variables
################################
TMPTARGET="/tmp/"
LOGTARGET="/tmp/"
LOG="$LOGTARGET/$( basename "$0" )_$( date +%d%m%Y ).log"
TMP1="${TMPTARGET}$( basename "$0" ).1.tmp"
TMP2="${TMPTARGET}$( basename "$0" ).2.tmp"
DEBUG="Y"
REGIONS="il-central-1 us-west-2"
ILSECGRP="sg-01111111111111111"
PDXSECGRP="sg-02222222222222222"

################################
## Functions
################################
function Debug {
        if [ "$DEBUG" == "Y" ]; then
                if [ ! -z "$CRON" ]; then
                        # Cron, output only to log
                        #echo -e "$( date +"%b %d %H:%M:%S" ) $1" 
			logger -t $( basename "$0") "$$ $1"
                else
                        # Not Cron, output to CLI and log
                        echo -e "$( date +"%b %d %H:%M:%S" )$$ $1" 
			logger -t $( basename "$0") "$$ $1"
                fi
        fi
}

function Success {
        Debug "Success"
}

function Failed {
        local lc="$BASH_COMMAND" rc=$?
        if [ "$rc" != "0" ]; then
                Debug "Failure, [$lc] exited with code [$rc], exiting"
                exit 1
        else
                Debug "[$lc] exited with code [$rc]"
        fi
}

function RemovePerm {
        Debug "Revoke any previous access group records"
        for REM in $( aws ec2 describe-security-groups --group-id $SECGRP --region $REGION --output text | grep $HOST | grep "/32" | awk '{print $2}' ); do
                Debug "\t Revoking access to $REM: aws ec2 revoke-security-group-ingress --protocol udp --port 41641 --cidr $REM --group-id $SECGRP --region $REGION"
                aws ec2 revoke-security-group-ingress --protocol udp --port 41641 --cidr $REM --group-id $SECGRP --region $REGION  || exit 1
        done
}

function Help {
	echo -e "\n\tusage: $0 [ -s | --status ] [ -h | --help ]\n"
}

function FindRegion {
	if [ -z $REGION ]; then
		Debug "FindRegion: REGION ($REGION) must be set"
	else
		case $REGION in
               		il-central-1 )
                                SECGRP="$ILSECGRP"
                                ;;
                        us-west-2 )
                                SECGRP="$PDXSECGRP"
                                ;;
                        * )
                                Debug "Error, unknown REGION $REGION"
                                ;;
		esac
	fi
}

function Status {
	echo -e "\n\t $TMP1 \n"
	cat $TMP1
	echo ""
	for REGION in $REGIONS; do

		FindRegion
		
		echo "Region: $REGION"
		aws ec2 describe-security-groups --group-ids $SECGRP --region $REGION --output text	
		echo ""
	done
}

################################
## CLI Options
################################

if [ -z != "$1" ]; then
        while [ "$1" != "" ]; do
        case $1 in
        -s | --status )
                Status
		exit
                ;;
        *)
                Help
		exit
                ;;
        esac
        shift
        done
fi

################################
## Main Code
################################
Debug "Writing output to TMP1 ($TMP1)"
tailscale status --json --peers --active | grep -i "dnsname\|curaddr" | tail -n +3 > $TMP1

Debug "$TMP1 \n\n $( cat $TMP1 )\n"

Debug "Prepare IP List"
for IP in $( cat $TMP1 | grep CurAddr | cut -d : -f 2 | cut -d \" -f 2 | grep -v ^$ | sort -u ); do
	HOST=`cat $TMP1 | grep $IP -B 1 | grep -i dnsname | cut -d \" -f 4 | sed 's/.taila1e00.ts.net.//'`
	HOSTCOUNT=`echo $HOST | wc -w`
	if [ $HOSTCOUNT -gt 1 ]; then
		# Look for snoopy
		SNOOPY=`echo $HOST | grep -ci snoopy`
		if [ $SNOOPY -gt 0 ]; then
			Debug "Snoopy found"
			HOST=snoopy
		else
			Debug "Snoopy not found, grab the first one"
			HOST=`echo $HOST | tr ' ' '\n' | head -n 1`
		fi
	fi
	Debug "IP $IP HOST $HOST HOSTCOUNT $HOSTCOUNT SNOOPY $SNOOPY"
	
	CHANGE=`grep $IP $TMP2 -c`
	if [ $CHANGE -eq 0 ]; then
		Debug "Update for $IP Required, using HOST $HOST"
	
		# Find the line for the HOST
		LINENUM=`grep -n $HOST $TMP2 | cut -d : -f 1`

		Debug "LINENUM |$LINENUM|"

		if [ "$LINENUM" != "" ]; then
			# Delete the line for the HOST
			OLDIP=`grep $HOST $TMP2 | awk '{print $2}'`
			Debug "OLDIP $OLDIP found"
			Debug "Deleting $LINENUM: sed -i \"${LINENUM}d\" $TMP2"
			sed -i "${LINENUM}d" $TMP2
		else
			OLDIP=""
		fi

		# Update the SG(s)
		Debug "Updating the regions"

		for REGION in $REGIONS; do

			FindRegion
			
			#case $REGION in
                	#il-central-1 )
                        #	SECGRP="$ILSECGRP"
                        #	;;
                	#us-west-2 )
                        #	SECGRP="$PDXSECGRP"
                        #	;;
                	#* )
                        #	Debug "Error, unknown REGION $REGION"
                        #	;;
        		#esac

        		Debug "delete the rule for the old IP ($OLDIP)"
        		RemovePerm && Success || Fail

        		Debug "add rule for the new IP (${IP}) for HOST ($HOST) in SECGRP $SECGRP in REGION $REGION: aws ec2 authorize-security-group-ingress --group-id $SECGRP --region $REGION --ip-permissions IpProtocol=udp,FromPort=41641,ToPort=41641,IpRanges=\"[{CidrIp=${IP}/32,Description=\"${HOST}\"}]\""
        		aws ec2 authorize-security-group-ingress --group-id $SECGRP --region $REGION --ip-permissions IpProtocol=udp,FromPort=41641,ToPort=41641,IpRanges="[{CidrIp=${IP}/32,Description="${HOST}"}]" && Success || Fail
		done

		# Update TMP2	
		echo -e "$HOST\t$IP" >> $TMP2
	else	
		Debug "$IP found in $TMP2, no update required"
	fi	
done
