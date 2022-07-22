#!/bin/bash
# LinuxGSM update_papermc.sh function
# Author: Daniel Gibbs
# Contributors: http://linuxgsm.com/contrib
# Website: https://linuxgsm.com
# Description: Handles updating of PaperMC and Waterfall servers.

local commandname="UPDATE"
local commandaction="Update"
local function_selfname="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"

fn_update_papermc_dl(){
	# get build info

	if [ "${shortname}" == "prpr" ]; then
		remotebuildname=""
		# purpur doesn't include the full app name, but forms it when the download occurs
		# https://github.com/PurpurMC/papyrus/blob/95af671a2b3ebdd3f1544c49d21af3d6d7bcc2e8/web/builds.go#L93
		buildname="${paperproject}-${paperversion}-${remotebuild}.jar"
		buildhash=$(curl -s "${preamble}/${paperversion}/${remotebuild}" | jq '.md5')
		dl_endpoint="${preamble}/${paperversion}/${remotebuild}/download"
	else
		builddata=$(curl -s "${preamble}/versions/${paperversion}/builds/${remotebuild}" | jq '.downloads' )
		remotebuildname=""
		buildname=$(echo -e "${builddata}" | jq -r '.application.name')
		buildhash=$(echo -e "${builddata}" | jq -r '.application.sha256')
		dl_endpoint="${preamble}/versions/${paperversion}/builds/${remotebuild}/downloads/${buildname}"
	fi

	fn_fetch_file "${dl_endpoint}" "" "${remotebuildname}" "" "${tmpdir}" "${buildname}" "nochmodx" "norun" "force" "${buildhash}"

	echo -e "copying to ${serverfiles}...\c"
	cp -f "${tmpdir}/${buildname}" "${serverfiles}/${executable#./}"
	local exitcode=$?
	if [ "${exitcode}" == "0" ]; then
		fn_print_ok_eol_nl
		fn_script_log_pass "Copying to ${serverfiles}"
		chmod u+x "${serverfiles}/${executable#./}"
		echo "${remotebuild}" > "${localversionfile}"
		fn_clear_tmp
	else
		fn_print_fail_eol_nl
		fn_script_log_fatal "Copying to ${serverfiles}"
		core_exit.sh
	fi
}

fn_update_papermc_localbuild(){
	# Gets local build info.
	fn_print_dots "Checking for update: ${remotelocation}: checking local build"
	sleep 0.5

	if [ ! -f "${localversionfile}" ]; then
		fn_print_error_nl "Checking for update: ${remotelocation}: checking local build: no local build files"
		fn_script_log_error "No local build file found"
	else
		localbuild=$(head -n 1 "${localversionfile}")
	fi

	if [ -z "${localbuild}" ]; then
		localbuild="0"
		fn_print_error "Checking for update: ${remotelocation}: waiting for local build: missing local build info"
		fn_script_log_error "Missing local build info, Set localbuild to 0"
	else
		fn_print_ok "Checking for update: ${remotelocation}: checking local build"
		fn_script_log_pass "Checking local build"
	fi
	sleep 0.5
}

fn_update_papermc_remotebuild(){
	# Gets remote build info.
	if [ "${shortname}" == "prpr" ]; then
		remotebuild=$(curl -s "${preamble}/${paperversion}/latest" | jq -r '.builds')
	else
		remotebuild=$(curl -s "${preamble}/versions/${paperversion}" | jq -r '.builds[-1]')
	fi

	# Checks if remotebuild variable has been set.
	if [ -z "${remotebuild}" ]||[ "${remotebuild}" == "null" ]; then
		fn_print_failure "Unable to get remote build"
		fn_script_log_fatal "Unable to get remote build"
		core_exit.sh
	else
		fn_print_ok "Got build for version ${paperversion}"
		fn_script_log "Got build for version ${paperversion}"
	fi
}

fn_update_papermc_compare(){
	fn_print_dots "Checking for update: ${remotelocation}"
	sleep 0.5
	if [ "${localbuild}" != "${remotebuild}" ]||[ "${forceupdate}" == "1" ]; then
		fn_print_ok_nl "Checking for update: ${remotelocation}"
		echo -en "\n"
		echo -e "Update available for version ${paperversion}"
		echo -e "* Local build: ${red}${localbuild}${default}"
		echo -e "* Remote build: ${green}${remotebuild}${default}"
		fn_script_log_info "Update available for version ${paperversion}"
		fn_script_log_info "Local build: ${localbuild}"
		fn_script_log_info "Remote build: ${remotebuild}"
		fn_script_log_info "${localbuild} > ${remotebuild}"
		echo -en "\n"
		echo -en "applying update.\r"
		echo -en "\n"

		unset updateonstart

		check_status.sh
		# If server stopped.
		if [ "${status}" == "0" ]; then
			fn_update_papermc_dl
		# If server started.
		else
			exitbypass=1
			command_stop.sh
			exitbypass=1
			fn_update_papermc_dl
			exitbypass=1
			command_start.sh
		fi
		alert="update"
		alert.sh
	else
		fn_print_ok_nl "Checking for update: ${remotelocation}"
		echo -en "\n"
		echo -e "No update available for version ${paperversion}"
		echo -e "* Local build: ${green}${localbuild}${default}"
		echo -e "* Remote build: ${green}${remotebuild}${default}"
		fn_script_log_info "No update available"
		fn_script_log_info "Local build: ${localbuild}"
		fn_script_log_info "Remote build: ${remotebuild}"
	fi
}

# Set up project specific strings for checks and downloads.
if [ "${shortname}" == "pmc" ]||[ "${shortname}" == "wmc" ]; then
	remotelocation="papermc.io"
	
	if [ "${shortname}" == "pmc" ]; then
		paperproject="paper"
	else
		paperproject="waterfall"
	fi

	project="projects/${paperproject}"

elif [ "${shortname}" == "prpr" ]; then
	remotelocation="purpurmc.org"
	paperproject="purpur"
	project="${paperproject}"
fi

preamble="https://api.${remotelocation}/v2/${project}"

localversionfile="${datadir}/${paperproject}-version"

# check if datadir was created, if not create it
if [ ! -d "${datadir}" ]; then
	mkdir -p "${datadir}"
fi

# check version if the user did set one and check it
if [ "${mcversion}" == "latest" ]; then
	paperversion=$(curl -s "${preamble}" | jq -r '.versions[-1]')
else
	# check if version there for the download from the api
	paperversion=$(curl -s "${preamble}" | jq -r -e --arg mcversion "${mcversion}" '.versions[]|select(. == $mcversion)')
	if [ -z "${paperversion}" ]; then
		# user passed version does not exist
		fn_print_error_nl "Version ${mcversion} not available from ${remotelocation}"
		fn_script_log_error "Version ${mcversion} not available from ${remotelocation}"
		core_exit.sh
	fi
fi

if [ "${firstcommandname}" == "INSTALL" ]; then
	fn_update_papermc_remotebuild
	fn_update_papermc_dl
else
	fn_print_dots "Checking for update: ${remotelocation}"
	fn_script_log_info "Checking for update: ${remotelocation}"
	sleep 0.5
	fn_update_papermc_localbuild
	fn_update_papermc_remotebuild
	fn_update_papermc_compare
fi
