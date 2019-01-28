#!/bin/bash

function die_usage() {
	echo -e "Elasticsearch backup configuration.

			\rUsage:  $0 [-H elastic_host] [-r repo_name] [-u username] [-p password] [-n] [-h]

			\r-H elastic_host:\tthe IP/FQDN of an Elasticsearch instance.
			\r-r repo_name:\t\tthe backups repository name.
			\r-u username:\t\tthe elasticsearch username
			\r-p password:\t\tthe elasticsearch password
			\r-h:\t\t\thelp: display this message.
			\r-n:\t\t\tnoauth: no authentication needed"
	exit $1
}

function build_vars() {
	auth_needed=true
	while getopts ":hH:nr:u:p:" opt; do
		case $opt in
			h)  die_usage 0             ;;
			H)  elastic_host=$OPTARG    ;;
			n)  auth_needed=false       ;;
			r)  repo_name=$OPTARG       ;;
			u)  username=$OPTARG        ;;
			p)  password=$OPTARG        ;;
			:)  echo "Option -$OPTARG requires an argument."
				die_usage 0
				;;
			\?) echo "Invalid option: -$OPTARG"
				die_usage 0
				;;
		esac
	done

	# checking authentication
	if ${auth_needed}; then
		if [ -z ${username} ] || [ -z ${password} ]; then
			echo "Both username and password are required."
			echo "If you don't need authentication please use the -n flag."
			die_usage 0
		fi
	else
		if [ -n ${username} ] || [ -n ${password} ]; then
			echo "You can't specify username nor password while using the -n flag."
			die_usage 0
		fi
	fi

	key=`printf ${username}:${password} | base64`
	if [ -f secret.key ]; then
		mv secret.key secret.key.orig
	fi
	echo ${key} >> secret.key
}


function prompt_confirm() {
	# example usage:
	# prompt_confirm "Overwrite File?" || exit 0
	while true; do
		read -rp "${1:-Continue?} [y/n]: " REPLY
		case $REPLY in
			[yYsS]) return 0 ;;
			[nN]) return 1 ;;
			*) printf " \033[31m %s \n\033[0m" "invalid input"
		esac
	done
}


function interactive_config() {
	echo "==================================="
	echo "Elasticsearch Backups configuration"
	echo "==================================="

	read -rp "Elasticsearch IP address: " elastic_host
	read -rp "New backup repository name: " repo_name
	if prompt_confirm "Do you want to configure authentication?"; then
		auth_needed=true
		read -rp "Username: " username
		read -rp "Password: " password
		key=`printf ${username}:${password} | base64`
		if [ -f secret.key ]; then
			mv secret.key secret.key.orig
		fi
		echo ${key} >> secret.key
	else
		auth_needed=false
	fi
}


function write_config() {
	if [ $# -eq 0 ]; then
		echo -e "\n\nNo arguments supplied. Running in interactive mode.\n\n"
		interactive_config
	else
		build_vars  $@
	fi

	echo "===================="
	echo "Configuration review"
	echo "===================="
	echo "elasticsearch address: ${elastic_host}"
	echo "repository name: ${repo_name}"
	echo "authentication: ${auth_needed}"
	if ${auth_needed}; then
		echo "username: ${username}"
		echo "password: ${password}"
	fi
	echo -e "\n\n"
	if !(prompt_confirm "Is the configuration correct?"); then
		write_config $@
	else
		if [ -f shell-variables ]; then
			mv shell-variables shell-variables.orig
		fi

		tee shell-variables <<-EOF
			#!/bin/bash

			# Elasticsearch endpoint URL
			url=${elastic_host}
			# Authentication needed
			auth_needed=${auth_needed}
			# Elasticsearch snapshot repository name
			repo=${repo_name}
			# Number of snapshots to keep
			limit=30
			# Snapshot naming convention
			snapshot=${repo_name}-\`date +%Y%m%d-%H%M%S\`
		EOF


		echo -e "\n\nAll set!"
		echo -e "Check out the file shell-variables for more customization options.\n"
	fi
}

function create_repo() {
	echo -e "\nConfiguring Snapshot Repository...\n"
	query=$(cat <<-EOF
		curl --request PUT
		--url http://${elastic_host}:9200/_snapshot/${repo_name}
		--header 'content-type: application/json'
	EOF
	)
	if ${auth_needed}; then
		query="${query} --header 'authorization: Basic $(cat secret.key)' "
	fi
	query=${query}$(cat <<-EOF
		--data '{
			"type":"fs",
			"settings": {
				"location": "/var/backups/elastic"
			}
		}'
	EOF
	)
	eval ${query}
	echo -e "\n\nRepository initialized.\n"
}

write_config $@
create_repo
