#!/bin/bash
#
# This is a sample bash script that uses APM Command Center API to manage
# of log level of APM Agents.
#

SERVER_URL="https://accdemowin01:8443"
SECURITY_TOKEN="e4f73a7b-3df5-43b4-8933-55c7663ce1ec"

# Echos list of interger values for the property name provided from a json response.
#
# args: [1]json(required), [2]name(required)
getJsonIntValues() {
	local values=$(echo "$1" | grep "\"$2\"[\t ]*:[\t ]*[0-9]*" | cut -f 2 -d':'| cut -f 1 -d',' | sed -e 's/^[/t ]*//g' -e 's/[/t ]*$//g')
	echo "$values"
}

# Echos list of string values for the property name provided from a json response.
#
# args: [1]json(required), [2]name(required)
getJsonStringValues() {
	local values=$(echo "$1" | grep "\"$2\"[\t ]*:[\t ]*\".*\"" | cut -f 2 -d':'| cut -f 1 -d',' | sed -e 's/^[/t ]*\"//g' -e 's/\"[/t ]*$//g')
	echo "$values"
}

# Echos agent parts of json response to request for getting agents based on a query.
# All agents are returned (paging is handled).
#
# args: [1]query(required - use '*' for all), [2]projection(optional - use 'list')
getAgents() {
	local pageSize=1000
	local agents=$(curl -G -s 0 -k -H "$CONTENT_TYPE" -H "$AUTHORIZATION" "$API_URL/agent" --data-urlencode "q=$1" --data "size=$pageSize" --data "projection=${2:-"full"}")
	local totalPages=$(getJsonIntValues "$agents" "totalPages")
	if [ "$totalPages" != "" ] && [ $totalPages -gt 0 ]; then
		# Keep just agent : [...] part of the response
		local startLine=`echo "$agents" | grep -n "\"agent\"[\t ]*:[\t ]*\[[\t ]*{" | cut -d: -f1`
		local stopLine=`echo "$agents" | grep -n "}[\t ]*\]" | cut -d: -f1`
		agents=`echo "$agents" | sed "$startLine,$stopLine!d"`
		if [ $totalPages -gt 1 ]; then
			for pageNo in `seq 1 $((totalPages-1))`; do
				local pageAgents=$(curl -s 0 -k -H "$CONTENT_TYPE" -H "$AUTHORIZATION" "$API_URL/agent?$projection&size=$pageSize&page=$pageNo&q=$1")
				startLine=`echo "$pageAgents" | grep -n "\"agent\"[\t ]*:[\t ]*\[[\t ]*{" | cut -d: -f1`
				stopLine=`echo "$pageAgents" | grep -n "}[\t ]*\]" | cut -d: -f1`
				pageAgents=`echo "$pageAgents" | sed "$startLine,$stopLine!d"`
				agents=$agents$'\n'$pageAgents
			done
		fi
		echo "$agents"
	else
		echo
	fi
}

authorize() {
	echo "$(curl -I -s -k -H "$AUTHORIZATION" "$API_URL")"
}

list() {
	local agents=$(getAgents "$QUERY")
	#echo "Agents=$agents"
	local id=($(getJsonIntValues "$agents" "id"))
	#echo "id=${id[@]}"
	if [ ${#id[@]} -eq 0 ]; then
		echo "No agent(s) found matching the criteria"
	else
		local agentName=($(getJsonStringValues "$agents" "agentName"))
		local processName=($(getJsonStringValues "$agents" "processName"))
		local status=($(getJsonStringValues "$agents" "status"))
		local serverName=($(getJsonStringValues "$agents" "serverName"))
		local logLevel=($(getJsonStringValues "$agents" "logLevel"))
		echo "ID:    Agent name:     Process name:   Status:  Server name:    Log level:"
		echo "------ --------------- --------------- -------- --------------- ----------"
		for ((i=0;i<${#id[@]};++i)); do
			printf "%-6s %-15s %-15s %-8s %-15s %-10s\n" "${id[i]}" "${agentName[i]}" "${processName[i]}" "${status[i]}" "${serverName[i]}" "${logLevel[i]}"
		done
	fi
}

set() {
	local agents=$(getAgents "$QUERY")
	local id=($(getJsonIntValues "$agents" "id"))
	if [ ${#id[@]} -eq 0 ]; then
		echo "No agent(s) found matching the criteria"
	else
		local agentName=($(getJsonStringValues "$agents" "agentName"))
		local processName=($(getJsonStringValues "$agents" "processName"))
		local status=($(getJsonStringValues "$agents" "status"))
		local serverName=($(getJsonStringValues "$agents" "serverName"))
		local logLevel=($(getJsonStringValues "$agents" "logLevel"))
		echo "Setting Log Level on matching APM Agents..."
		for ((i=0;i<${#id[@]};++i)); do
			if [ ${status[i]} == "ACTIVE" -a "${logLevel[i]}" != "$LOG_LEVEL" ]; then
				echo "Requesting Log Level change from ${logLevel[i]} to $LOG_LEVEL on APM Agent ${serverName[i]}/${agentName[i]}/${processName[i]}"
				local response=$(curl -s 0 -k -H "$CONTENT_TYPE" -H "$AUTHORIZATION" "$API_URL/agentUpdateTask" -d "{\"agent\":\"agent/${id[i]}\",\"property\":\"log4j.logger.IntroscopeAgent\",\"value\":\"$LOG_LEVEL\"}")
				if [ $? -eq 0 ]; then
					# Get Agent Update Task href from the response
					local selfHref=$(echo "$response" | awk '/\"self\"[\t ]*:[\t ]*{/{flag=1;next}/\}/{flag=0}flag' | sed 's/.*\"href\"[\t ]*:[\t ]*//g')
					echo " -> Created $selfHref"
				else
					echo " -> Request failed: $response"
				fi
			else
				echo "Skipping ${status[i]} APM Agent ${serverName[i]}/${agentName[i]}/${processName[i]} with current Log Level ${logLevel[i]}"
			fi
		done
	fi
}

help() {
	echo "Uses APM Command Center API to automate handling of log levels of APM Agents"
	echo "matching query criteria"
	echo
	echo "Usage: $0 <COMMAND> [OPTIONS]"
	echo
	echo "Commands:"
	echo "-l, --list             Lists log levels for APM Agents matching query"
	echo "    --set=<LOG_LEVEL>  Sets log level for APM Agents matching query" 
	echo "-r, --reset            Resets log level to default INFO for APM Agents matching"
	echo "                       query"
	echo "Options:"
	echo "-h, --help             This help screen"
	echo "-q, --query=<QUERY>    Query to match APM Agents. If not specified, all agents"
	echo "                       are included in the result."
	echo "-s, --server-url=<URL> URL to APM Command Center Server."
	echo "                       Uses ${SERVER_URL} by default."
	echo "-t, --security-token <TOKEN>"
	echo "                       Security token to use for authorization"
	echo "Sample queries:"
	echo "--query='osName:\"Windows Server 2008\" OR serverName:ACCDemoLinux01'"
}

ACTION="help"
QUERY="*"
LOG_LEVEL="INFO"
CONTENT_TYPE="Content-Type:Application/json"
IFS=$'\n' # Make sure array elements are created from strings separated by new line rather than space

for PARAM in "$@"
do
	case $PARAM in
		-h|--help )
			ACTION="help"
			;;
		-l|--list )
			ACTION="list"
			;;
		--set=* )
			LOG_LEVEL=`echo $PARAM | sed -e 's/--set=//' | tr '[:lower:]' '[:upper:]'`
			ACTION="set"
			;;
		-r|--reset )
			LOG_LEVEL="INFO"
			ACTION="set"
			;;
		-q=*|--query=* )
			QUERY=`echo $PARAM | sed -e 's/--query=//' -e 's/-q=//'`
			;;
		-s=*|--server-url=* )
			SERVER_URL=`echo $PARAM | sed -e 's/--server-url=//' -e 's/-s=//'`
			;;
		-t=*|--security-token=* )
			SECURITY_TOKEN=`echo $PARAM | sed -e 's/--security-token=//' -e 's/-t=//'`
			;;
		*)
			echo "Error: Unknown parameter '$PARAM'"
			help
			exit 1
	esac
done

API_URL="$SERVER_URL/apm/acc"
AUTHORIZATION="Authorization:Bearer $SECURITY_TOKEN"

case $ACTION in
	list|set )
		authorizeResponse=$(authorize)
		if [ "$(echo "$authorizeResponse" | grep '204 No Content')" != "" ]; then
			if [ "$ACTION" == "list" ]; then
				list
			else
				set
			fi
		else
			echo "$authorizeResponse"
		fi
		;;
	*)
		help
esac
