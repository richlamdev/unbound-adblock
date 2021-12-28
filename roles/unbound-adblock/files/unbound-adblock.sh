#!/usr/bin/env ksh
#
# Copyright (c) 2018-2021 Jordan Geoghegan <jordan@geoghegan.ca>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
# OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

# Version 0.5 "Gaslight Republic" -- Released January 10, 2021

# In loving memory of Ron Sather

# Fighting for freedom and fighting terror - but what's reality?

# Fetch, parse and generate domain blocklists data into format suitable 
# for ingestion by RPZ compatible DNS servers and/or unbound/unwind.

version='0.5p4'
release_date='2021-01-10'
release_name='Gaslight Republic'

set -ef #-o pipefail

# ###########################################################################
# ------------------------------------------------------------------------------
# User Configuration Area -- BEGIN
# ------------------------------------------------------------------------------

# Set to '1' to enable
# Set to '0' to disable

# unbound-adblock requires a modern shell that has support for
# the non-POSIX 'typeset' feature and ksh array syntax.
# ---
# By default unbound-adblock looks for 'ksh' in the users $PATH
# unbound-adblock also supports the following shells:
#     pdksh (and variants), ksh93, mksh, bash, or zsh
#
# To use a shell other than ksh:
#    * Update the shebang line (line 1) of this script to that of the new shell you've installed

# HTTP user agent override (Pretend to be Firefox on Win10 by default)
# Note: The "fetch" utility on FreeBSD and Dragonfly doesnt support user agent override. Use 'curl' instead
_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0"

# Enable Logging to /var/log/unbound-adblock/
_LOG=1

# Enable Strict Mode
# (This option will cause unbound-adblock to abort if it exceeds maximum retrys)
_STRICT=1

# Max Retry Count (How many times we'll attempt to download a file before giving up)
_RETRY=3

# NOTE: DO NOT put quotes in here, as there is a bug in most pdksh
# (including default shells of NetBSD and OpenBSD) that makes the
# shell puke when quotes are used within a HEREDOC statement as below
# See: https://marc.info/?l=openbsd-misc&m=160560808529209&w=2
###################################################################
# Hosts File Blacklist
# Add blocklists below, one URL per line
# Blocklists MUST be in /etc/hosts format
# Lines below starting with '#' or ';' will be ignored
# Lists may optionally be gzip compressed
_HOSTS_FMT_BLOCKLISTS=$(cat <<'__EOT'

### Local File Example
# file:/path/to/local/file

### Steven Black Hosts List
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts

__EOT
)
###################################################################

###################################################################
# Domain Blacklist
# Add blocklists below, one URL per line
# This is for parsing lists that are domains only (NOT /etc/hosts format)
# Lines starting with '#' or ';' will be ignored
# Lists may optionally be gzip compressed
_DOMAIN_FMT_BLOCKLISTS=$(cat <<'__EOT'

### Local File Example
# file:/path/to/local/file

### StopForumSpam.com Toxic Domains List
https://www.stopforumspam.com/downloads/toxic_domains_whole.txt


__EOT
)
###################################################################

###################################################################
# Global Whitelist and Input Filtering
#
# NOTE: Use of '-r' or '-w' to whitelist URLs is prefered.
#
# This whitelist function can be used to perform arbitrary filtering
# Use at your own risk.
#
 _WHITELIST=0	# Set to '1' to enable
WHITELIST() {
	# Add as many entries to the whitelist as you like
	mygrep -v -e 'example\.com' -e 'example\.org'
}
# ------------------------------------------------------------------------------
# User Configuration Area -- END
# ------------------------------------------------------------------------------
# ###########################################################################

# (Do not edit below this line unless you know what you're doing)

# ------------------------------------------------------------------------------
# Abort Sequences and Housekeeping
# ------------------------------------------------------------------------------

ABORT() {
	WARN_ERR "ERROR: '${confpath}' contains invalid data! Reverting changes and bailing out..."
	OLD_CONF_RESET
	TRAPPER
}

CLEANUP() {
	rm -rf -- "${tmpdir_domain}" "${tmpdir_hosts}" "${scratchdir}" "${workdir}" || WARN_ERR 'ERROR: Failed to delete temporary files!'
}

ERR() {
	echo '' 1>&2 ; printf 'ERROR: %s\nBailing out without making changes...\n' "$*" | logger -t 'unbound-adblock' -s
	TRAPPER
}

HELP_MESSAGE() {
	printf '\n###################################################################\n'
	printf '# unbound-adblock %s (%s)  Released on: %s\n' "${version}" "${release_name}" "${release_date}"
	printf '# Copyright 2018-2021 Jordan Geoghegan <jordan@geoghegan.ca>\n#\n'
	printf '# unbound-adblock blocks malicious domains via Unbound DNS Server\n#\n'
	printf '# Supported Operating Systems:\n#\n# * OpenBSD\n# * FreeBSD\n# * NetBSD\n# * DragonflyBSD\n# * Linux\n# * Alpine\n#\n'
	printf '# OS Type Can Be Specified As An Argument:\n'
	printf '# Example: "unbound-adblock -O DragonflyBSD"\n#\n'
	printf '# NOTE: OS arguments are case insensitive\n#\n'
	printf '# The man page can be found at:\n'
	printf '#    https://geoghegan.ca/pub/unbound-adblock/0.5/man/man.txt\n'
	printf '###################################################################\n\n'
}

OLD_CONF_RESET() {
	cp -- "${oldconf}" "${confpath}" || WARN_ERR 'ERROR: Failed to to restore previous blocklist!'
	if [ "${_ALT_UNWIND}" -eq 1 ]; then
		# Unwind config restore
		if ! unwind -n >/dev/null 2>&1; then
			WARN_ERR 'ERROR: old unwind-adblock.db also has bad data!'
			WARN_ERR "Clearing ${confpath} and bailing out..."
			cp -- /dev/null "${confpath}" || WARN_ERR "ERROR: Failed to clear '${confpath}'"
		fi
	else
		# Unbound config restore
		if ! nice unbound-checkconf ; then
			WARN_ERR 'ERROR: old adblock.conf also has bad data!'
			WARN_ERR "Clearing ${confpath} and bailing out..."
			cp -- /dev/null "${confpath}" || WARN_ERR "ERROR: Failed to clear ${confpath}"
		fi
	fi
}

TMP_FILE_ABORT() {
	ERR 'Failed to create and/or write to a temporary file! Please ensure that "/tmp" has free space!'
}

TRAP_ABORT() {
	ERR "Interupt or uncaught error detected.."
}

TRAPPER() {
	CLEANUP ; exit 1
}

WARNING() {
	if [ "${_VERBOSE}" -eq 0 ] && [ "${_LOG}" -eq 1 ]; then
		WARN_ERR "$*" >/dev/null 2>&1
	elif [ "${_VERBOSE}" -eq 1 ] && [ "${_LOG}" -eq 0 ]; then
		printf '\n%s\n\n' "$*" 1>&2
	elif [ "${_VERBOSE}" -eq 0 ] && [ "${_LOG}" -eq 0 ]; then
		true
	else
		WARN_ERR "$*"
	fi
}

WARN_ERR() {
	# Force printing and logging of error messages
	echo '' 1>&2
	logger -t 'unbound-adblock' -s -- "$*"
	echo '' 1>&2
}

# ------------------------------------------------------------------------------
# Alias functions
# ------------------------------------------------------------------------------

# Opportunistically use mawk or GNU awk if they're available
myawk() {
	if command -v mawk >/dev/null 2>&1 ; then
		nice mawk "$@" -
	elif command -v gawk >/dev/null 2>&1 ; then
		nice gawk "$@" -
	else
		nice awk "$@" -
	fi
}

# Users must expicitely set the "netget" var to overide platform default fetch util
# Use '-F' to set fetch util preference from commandline
myfetch() {
	typeset _cmd="$(CHECK_CMD "${netget}")"
	case "${netget}" in
	    curl)  nice "${_cmd}" -o - -s -A "${_AGENT}" -m 900 -- "$@" ;;
	    fetch) nice "${_cmd}" -o - -q -- "$@" ;;
	    ftp)   nice "${_cmd}" -o - -V -U "${_AGENT}" -w 30 -- "$@" ;;
	    wget)  nice "${_cmd}" -O - -q -U "${_AGENT}" --timeout=900 -- "$@" ;;
	    *)     ERR "${_cmd} not found!"
	esac
}

# Opportunistically use RipGrep or GNU grep if they're available
mygrep() {
	if command -v rg >/dev/null 2>&1 ; then
		nice rg "$@" - || true
	elif command -v ggrep >/dev/null 2>&1 ; then
		nice ggrep -E "$@" - || true
	else
		nice grep -E "$@" - || true
	fi
}

# Opportunistically use GNU sort if available (needed for NetBSD support)
mysort() {
	if command -v gsort >/dev/null 2>&1 ; then
		nice gsort "$@" -
	else
		nice sort "$@" -
	fi
}

# ------------------------------------------------------------------------------
# List Generation and Installation Functions
# ------------------------------------------------------------------------------

FORMAT_DOMAIN() {
	myawk -- 'BEGIN { OFS = "" } (length($1) < 254 && length($1) > 3) && ($1 != "" && $1 !~ "#|\\.\\." && $1 ~ "\\.[[:alnum:]]" && $1 ~ "[[:alpha:]]") { print $1 }'
}

FORMAT_HOSTS() {
	myawk -- 'BEGIN { OFS = "" } ($1 == "0.0.0.0" || $1 == "127.0.0.1") && (length($2) < 254 && length($2) > 3) && ($2 !~ "\\.\\." && $2 ~ "\\.[[:alnum:]]" && $2 ~ "[[:alpha:]]") { print $2 }'
}

RAW_TO_UNBOUND() {
	myawk -- 'BEGIN { OFS = "" } { print "local-zone: \"", $1, "\" always_nxdomain"}'
}

LIST_GEN() {
	# Delete empty files
	find "${tmpdir_domain}" "${tmpdir_hosts}" -type f -size 0 -delete || WARN_ERR 'ERROR: Failed to delete temporary files!'

	# Domain-only format data
	{ find "${tmpdir_domain}" -type f -exec gunzip -dcf -- {} + | tr -cd -- '[:alnum:][:blank:]%#.~\n_/\-' | FORMAT_DOMAIN ;} > "${tmpfile_domain}" || TMP_FILE_ABORT

	# /etc/hosts format data
	{ find "${tmpdir_hosts}" -type f -exec gunzip -dcf -- {} + | tr -cd -- '[:alnum:][:blank:]%#.~\n_/\-' | FORMAT_HOSTS ;} > "${tmpfile_hosts}" || TMP_FILE_ABORT

	# Merge and sort lists
	# Note: We use cat here because the mygrep func expects input from stdin
	cat -- "${tmpfile_domain}" "${tmpfile_hosts}" | mygrep '^[[:alnum:]._-]*$' | mygrep -v '^\.|^-|\.$|-$' | tr '[:upper:]' '[:lower:]' | WHITELIST_FILTER | mysort -u > "${rawout}" || TMP_FILE_ABORT
}



LIST_INSTALL() {
	typeset new_offset old_offset unbound_control unwind unwindctl

	# Backup old blocklist
	cp -- "${confpath}" "${oldconf}" || TMP_FILE_ABORT

	### Convert raw domain data to necessary output format
	# Old unbound specific 'local-data' format
	if [ "${_ALT_UNBOUND}" -eq 1 ]; then
		RAW_TO_UNBOUND < "${rawout}" > "${cnvtemp}" || TMP_FILE_ABORT
	# Unwind format (raw domains)
	elif [ "${_ALT_UNWIND}" -eq 1 ]; then
		cp -- "${rawout}" "${cnvtemp}" || TMP_FILE_ABORT
	# Cross-platform RPZ data
	else
		sed -- 's/$/ CNAME ./g' < "${rawout}" > "${cnvtemp}" || TMP_FILE_ABORT
	fi

	### Add date + stats header to generated blocklist
	# Unwind or old unbound specific format
	if [ "${_ALT_UNWIND}" -eq 1 ] || [ "${_ALT_UNBOUND}" -eq 1 ]; then
		{ printf '# Date Created: %s\n' "$(date)" && PRINT_STATS | sed 's/^/# /g' && printf '\n' && cat -- < "${cnvtemp}" ;} > "${finout}" || TMP_FILE_ABORT
	# Cross-platform RPZ data
	else
		{ printf ';; Date Created: %s\n' "$(date)" && PRINT_STATS | sed 's/^/;; /g' \
		  && if test -s "${user_rules}" ; then printf '\n;; Whitelist:\n\n' && cat -- < "${user_rules}" ; fi \
		  && printf '\n;; Blocklist:\n\n' && cat -- < "${cnvtemp}" ;} > "${finout}" || TMP_FILE_ABORT
	fi

	# Calculate byte offsets (to ignore info headers in cmp)
	old_offset="$(head -5 -- "${oldconf}" | wc -c)"
	new_offset="$(head -5 -- "${finout}" | wc -c)"

	# Reload unbound list only if there are changes
	# 'cmp -s' on most platforms has a bug where it ignores byte offsets :(
	if cmp -- "${oldconf}" "${finout}" "${old_offset}" "${new_offset}" >/dev/null 2>&1; then
		printf '\nNo blocklist changes...\n' 1>&2
		if [ "${_LOG}" -eq 1 ]; then
			{ printf '# Last Run (no changes): %s\n' "$(date)" ; cat -- < "${oldconf}" ; } > "${cnvtemp}" || TMP_FILE_ABORT
			cp -- "${cnvtemp}" /var/log/unbound-adblock/unbound-adblock.log || ERR 'Failed to update log file!'
		fi
		return 0
	fi

	# Move new blocklist into place
	cp -- "${finout}" "${confpath}" || ERR "Failed to update ${confpath}! Please ensure the file has correct permissions and that the partition has free space!"

	# Reload unbound/unwind IF needed (RPZ mode doesn't require unbound to be reloaded)
	if [ "${_ALT_UNWIND}" -eq 1 ]; then
		unwind="$(CHECK_CMD unwind)"
		unwindctl="$(CHECK_CMD unwindctl)"
		# Ensure proposed changes are valid before reloading unwind
		if "${unwind}" -n ; then
			"${getroot}" -- "${unwindctl}" reload >/dev/null 2>&1 || ABORT
		else
			ABORT
		fi
	elif [ "${_ALT_UNBOUND}" -eq 1 ]; then
		# Ensure proposed changes are valid before reloading unbound
		if nice unbound-checkconf ; then
			"${getroot}" -- "${rcd}" "${rcdarg1}" "${rcdarg2}" || ABORT
		else
			ABORT
		fi
	else
		# Ensure proposed changes are valid before reloading unbound
		if nice unbound-checkconf ; then
			unbound_control="$(CHECK_CMD unbound-control)"
			"${getroot}" -- "${unbound_control}" -q auth_zone_reload unbound-adblock || ABORT
			"${getroot}" -- "${unbound_control}" -q flush_zone unbound-adblock || ABORT
		else
			ABORT
		fi
	fi

	# Run logging function
	if [ "${_LOG}" -eq 1 ]; then
		LOGGER
	fi
}

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------

LOGGER() {
	# Gzip old log file
	gzip -9 -c -- < /var/log/unbound-adblock/unbound-adblock.log > "${gztemp}" || ERR 'Failed to rotate log file!'
	cp -- "${gztemp}" /var/log/unbound-adblock/unbound-adblock.log.0.gz || ERR 'Failed to rotate log file!'

	# Move new log into place
	cp -- "${finout}" /var/log/unbound-adblock/unbound-adblock.log || ERR 'Failed to create log file!'
	chmod 640 /var/log/unbound-adblock/unbound-adblock.log /var/log/unbound-adblock/unbound-adblock.log.0.gz >/dev/null 2>&1
}

PRINT_STATS() {
	# Calculate blocklist entries in current and previously installed lists
	typeset -i blk_num new_num old_num usr_num

	blk_num="$(SANITIZE_ARRAY_NO_SORT < "${rawout}" | wc -l)"
	old_num="$(SANITIZE_ARRAY_NO_SORT < "${oldconf}" | wc -l)"
	usr_num="${#_user_rule[@]}"
	new_num="$((usr_num + blk_num))"

	# Need to preface with '+', so do not store as integer
	typeset changes="$((new_num - old_num))"
	if [ "${changes}" -ge 0 ]; then
		changes="+${changes}"
	fi

	printf '\nChanges (+/-):  %s\n' "${changes}"
	printf 'Domain total :  %d\n\n'  "${new_num}"
}

# ------------------------------------------------------------------------------
# Temp File Functions
# ------------------------------------------------------------------------------

TMP_FILE_HOSTS() {
	mktemp -- "${tmpdir_hosts}/hosts.XXXXXXXX" || TMP_FILE_ABORT
}

TMP_FILE_DOMAIN() {
	mktemp -- "${tmpdir_domain}/domain.XXXXXXXX" || TMP_FILE_ABORT
}

TMP_FILE_SCRATCH() {
	mktemp -- "${scratchdir}/scratch.XXXXXXXX" || TMP_FILE_ABORT
}

# ------------------------------------------------------------------------------
# Tests and Sanity Checks
# ------------------------------------------------------------------------------

CHECK_DRIVE() {
	# Make sure output destination exists
	if [ -f "${confpath}" ] && [ -w "${confpath}" ]; then
		true
	else
		ERR "${confpath} either not found or has incorrect permissions!"
	fi

	# If logging is enabled, make sure permissions are correct
	if [ "${_LOG}" -eq 1 ]; then
		# Make sure log dir exists and has correct permissions
		if [ -d /var/log/unbound-adblock ] && [ -r /var/log/unbound-adblock ]; then
			true
		else
			ERR "Directory '/var/log/unbound-adblock' either not found, or has incorrect permissions!"
		fi
		# Make sure log file is writeable
		if [ -f /var/log/unbound-adblock/unbound-adblock.log ] && [ -w /var/log/unbound-adblock/unbound-adblock.log ]; then
			true
		else
			ERR "Log file '/var/log/unbound-adblock/unbound-adblock.log' has incorrect permissions!"
		fi
		# Make sure gzip file is writeable
		if [ -f /var/log/unbound-adblock/unbound-adblock.log.0.gz ] && [ -w /var/log/unbound-adblock/unbound-adblock.log.0.gz ]; then
			true
		else
			ERR "Log file '/var/log/unbound-adblock/unbound-adblock.log.0.gz' has incorrect permissions!"
		fi
	fi
}

CHECK_CMD() {
	typeset _cmd="${1}"
	command -v -- "${_cmd}" || ERR "'${_cmd}' not found! Please ensure that '${_cmd}' is installed!"
}

CHECK_PRIVILEGE() {
	# Make sure we're running as "_adblock" user
	if [ "$(whoami)" != '_adblock' ]; then
		printf '\nScript must be run as user "_adblock" - Exiting...\n' 1>&2
		exit 1
	fi
}

IS_INT() {
	case "$1" in
	    ''|*[!0-9]*) return 1 ;;
	    *) return 0 ;;
	esac
}

PRE_EXEC_TESTS() {
	typeset _cmd unbound_control

	# Make sure requisite utilities are installed
	for _cmd in 'cmp' 'find' 'gunzip' "${getroot}" "${rcd}" "${netget}" ; do
		CHECK_CMD "${_cmd}"
	done >/dev/null

	if [ "${_NO_UID_CHECK}" -ne 1 ]; then
		CHECK_PRIVILEGE
	fi

	# Make sure unbound/unwind is running
	if [ "${_PRINT_ONLY}" -ne 1 ]; then
		if [ "${_ALT_UNWIND}" -eq 1 ]; then
			CHECK_CMD 'unwindctl' >/dev/null
			unwindctl status >/dev/null 2>&1 || ERR 'unwind does not appear to be running!'
		else
			CHECK_CMD 'unbound-checkconf' >/dev/null
			UNBOUND_STATUS_CHECK || ERR 'unbound does not appear to be running!'
		fi
		# Make sure 'unbound-control' is working
		if [ "${_ALT_RPZ}" -eq 1 ]; then
			unbound_control="$(CHECK_CMD unbound-control)"
			"${getroot}" -- "${unbound_control}" -q status || ERR "Unable to connect to unbound with 'unbound-control'"
		fi
		CHECK_DRIVE
	fi

	# Check for network connectivity to GitHub, bail out if fail
	URL_FETCH https://github.com /dev/null || ERR 'No network connectivity!'
}

# Make sure unbound is running
UNBOUND_STATUS_CHECK() {
	case "${_OS_TYPE}" in
	alpine)
		"${rcd}" unbound status >/dev/null 2>&1 ; return ;;
	custom)
		return 0 ;;
	dragonflybsd)
		"${rcd}" unbound onestatus >/dev/null 2>&1 ; return ;;
	freebsd)
		"${getroot}" -- "${rcd}" unbound onestatus >/dev/null 2>&1 ; return ;;
	linux)
		systemctl is-active --quiet unbound >/dev/null 2>&1 ; return ;;
	netbsd)
		"${getroot}" -- "${rcd}" unbound onestatus >/dev/null 2>&1 ; return ;;
	openbsd)
		"${rcd}" check unbound >/dev/null 2>&1 ; return ;;
	*)
		ERR "Operating system type '${_OS_TYPE}' not recognized..."
	esac
}

# Make sure user-provided values are sane
VAR_SANITY_CHECK() {
	IS_INT "${_ALT_RPZ}" || ERR 'User defined variable "$_ALT_RPZ" contains a non-integer value - Unable to proceed!'
	IS_INT "${_ALT_UNBOUND}" || ERR 'User defined variable "$_ALT_UNBOUND" contains a non-integer value - Unable to proceed!'
	IS_INT "${_ALT_UNWIND}" || ERR 'User defined variable "$_ALT_UNWIND" contains a non-integer value - Unable to proceed!'
	IS_INT "${_CHECK_ONLY}" || ERR 'User defined variable "$_CHECK_ONLY" contains a non-integer value - Unable to proceed!'
	IS_INT "${_LOG}" || ERR 'User defined variable "$_LOG" contains a non-integer value - Unable to proceed!'
	IS_INT "${_NO_UID_CHECK}" || ERR 'User defined variable "$_NO_UID_CHECK" contains a non-integer value - Unable to proceed!'
	IS_INT "${_PRINT_ONLY}" || ERR 'User defined variable "$_PRINT_ONLY" contains a non-integer value - Unable to proceed!'
	IS_INT "${_RETRY}" || ERR 'User defined variable "$_RETRY" contains a non-integer value - Unable to proceed!'
	IS_INT "${_STRICT}" || ERR 'User defined variable "$_STRICT" contains a non-integer value - Unable to proceed!'
	IS_INT "${_VERBOSE}" || ERR 'User defined variable "$_VERBOSE" contains a non-integer value - Unable to proceed!'
	IS_INT "${_WHITELIST}" || ERR 'User defined variable "$_WHITELIST" contains a non-integer value - Unable to proceed!'

	# Make sure $_RETRY is greater than 0
	if [ "${_RETRY}" -lt 1 ]; then
		_RETRY=1
	fi

	if [ "${_ALT_UNBOUND}" -eq 1 ] && [ "${_ALT_UNWIND}" -eq 1 ]; then
		ERR 'RPZ, Unbound and Unwind format options are mutually exclusive!'
	elif [ "${_ALT_UNBOUND}" -eq 1 ] && [ "${_ALT_RPZ}" -eq 1 ]; then
		ERR 'RPZ, Unbound and Unwind format options are mutually exclusive!'
	elif [ "${_ALT_UNWIND}" -eq 1 ] && [ "${_ALT_RPZ}" -eq 1 ]; then
		ERR 'RPZ, Unbound and Unwind format options are mutually exclusive!'
	fi

	if [ "${_ALT_UNWIND}" -eq 1 ] && [ "${_PRINT_ONLY}" -ne 1 ] && [ "${_OS_TYPE}" != 'openbsd' ]; then
		ERR "'unwind' backend supported only on OpenBSD :("
	fi

	# Make sure there is at least 1 blocklist enabled
	if [ "${#_domain_url[@]}" -lt 1 ] && [ "${#_hosts_url[@]}" -lt 1 ]; then
		ERR 'No blocklists enabled! Please enable at least one blocklist!'
	fi

	# '-r' and '-w' whitelisting options are only supported with RPZ backend
	if [ "${#_user_rule[@]}" -ge 1 ] && [ "${_ALT_RPZ}" -ne 1 ]; then
		ERR "'-r' and '-w' options are only supported for use with RPZ backends!"
	fi
}

WHITELIST_FILTER() {
	# Pipe through cat to avoid wasting cycles on grep if whitelisting is disabled
	if [ "${_WHITELIST}" -eq 1 ]; then
		WHITELIST
	else
		cat
	fi
}

# ------------------------------------------------------------------------------
# URL Fetch Functions
# ------------------------------------------------------------------------------

# This function accepts 2 arguments, the first one being the URL to fetch,
# and the second argument being the intended output destination.
# If the second argument is '-' then we output to stdout
#
# Output to filesystem location - Example:
#	URL_FETCH https://example.com/file.txt /local/file/path
#
# Output to stdout - Example:
#	URL_FETCH https://example.com/file.txt -

URL_FETCH() {
	# Create local vars
	typeset _URL _OUTPUT_FILE || ERR 'Current shell does not support the non-POSIX "typeset" feature!'
	typeset -i _counter _STDOUT
	_counter=0

	# If constant 'RETRY' hasn't yet been set, create local var and set it to '3'
	test -n "${_RETRY}" || typeset -i _RETRY=3

	# Make sure URL and output destination were provided
	if [ -z "${2}" ] || [ -z "${1}" ]; then
		ERR 'No URL and/or output location provided to URL_FETCH function!' ; return 1
	elif [ "${2}" = '-' ]; then
		_STDOUT=1
		_URL="${1}"
		_OUTPUT_FILE='/dev/null'
	else
		_STDOUT=0
		_URL="${1}"
		_OUTPUT_FILE="${2}"
	fi

	while true ; do
		(( _counter++ )) || true # Increment counter for each download attempt
		if [ "${_counter}" -le "${_RETRY}" ]; then
			# Sleep 'n' seconds before reattempting download
			if [ "${_counter}" -gt 1 ]; then
				if [ "${_VERBOSE}" -ne 0 ]; then
					printf 'Sleeping for %d seconds before reattempting download...\n\n' "$((_counter * 10))" 1>&2
				fi
				sleep "$((_counter * 10))"
			fi
			# Upon successful download from a URL, break the loop and proceed to next URL
			if [ "${_STDOUT}" -eq 1 ]; then
				# Print to stdout
				if myfetch "${_URL}" ; then
					return
				else
					if [ "${_VERBOSE}" -ne 0 ]; then
						printf '\nFailed to Fetch List (Attempt #%d):  %s\n\n' "${_counter}" "${_URL}" 1>&2
					fi
				fi

			else
				# Output to specified filesystem location
				if myfetch "${_URL}" > "${_OUTPUT_FILE}" ; then
					return
				else
					if [ "${_VERBOSE}" -ne 0 ]; then
						printf '\nFailed to Fetch List (Attempt #%d):  %s\n\n' "${_counter}" "${_URL}" 1>&2
					fi
				fi
			fi
		else
			WARNING "Exceeded Maximum Number of Retries (${_RETRY}) For URL:  ${_URL}"
			if [ "${_STRICT}" -eq 0 ]; then
				# Clean-up any potential garbage from failed download
				if [ -f "${_OUTPUT_FILE}" ]; then
					rm -f -- "${_OUTPUT_FILE}"
				fi
				return 0
			else
				ERR 'Strict Mode Enabled' ; return 1
			fi
		fi
	done
}

PRINT_DOMAIN_LIST() {
	printf '%s\n' "${_DOMAIN_FMT_BLOCKLISTS}" | SANITIZE_ARRAY_NO_SORT | mysort -uR
}

PRINT_HOSTS_LIST() {
	printf '%s\n' "${_HOSTS_FMT_BLOCKLISTS}" | SANITIZE_ARRAY_NO_SORT | mysort -uR
}

SANITIZE_ARRAY() {
	mygrep -v -- '^#|^;|^[[:space:]]*#|^[[:space:]]*;|^[[:space:]]*$' | myawk -- '{print $1}' | mysort -u
}

SANITIZE_ARRAY_NO_SORT() {
	mygrep -v -- '^#|^;|^[[:space:]]*#|^[[:space:]]*;|^[[:space:]]*$' | myawk -- '{print $1}'
}

# ------------------------------------------------------------------------------
# Main Function
# ------------------------------------------------------------------------------

main() {
	# Set trap handler
	trap TRAP_ABORT ERR INT

	# Mark program info read-only
	readonly version release_date release_name

	# Initialize counters
	typeset -i _array_index=0 _d_counter=0 _l_counter=0 _r_counter=0
	# Initialize case (in)sensitive vars
	typeset -l _opt_arg
	# Initialize global configuration vars
	_ALT_RPZ=1 ; _ALT_UNBOUND=0 ; _ALT_UNWIND=0
	_CHECK_ONLY=0 ; _NO_UID_CHECK=0 ; _PRINT_ONLY=0 ; _VERBOSE=1

	# Command-line option handling
	while getopts DF:O:R:VW:Z:hd:l:no:r:t:u:w:x _opts ; do
	case "${_opts}" in
	    D)  _NO_UID_CHECK=1 ;;  # Disable UID checking
	    F)  netget="${OPTARG}" ;;  # set ftp/fetch/curl preference
	    O)  typeset -l -r _OS_TYPE="${OPTARG}" ;;
	    R)  _RETRY="${OPTARG}" ;; # Maximum number of URL fetch attempts
	    V)  _VERBOSE=0 ;;  # Disable printing of warning messages
	    W)  confpath="${OPTARG}" ;;
	    Z)  getroot="${OPTARG}" ;;
	    d)  # Add domain-only format URL
		_domain_url[${_d_counter}]="${OPTARG}"
		(( _d_counter++ )) || true ;;
	    h)  HELP_MESSAGE ; exit ;;
	    l)  # Add /etc/hosts format URL
		_hosts_url[${_l_counter}]="${OPTARG}"
		(( _l_counter++ )) || true ;;
	    n)  # Dry run
		_CHECK_ONLY=1 ;;
	    o)  # Formatting and runtime options
		_opt_arg="${OPTARG}"
		case "${_opt_arg}" in
		    domain) _PRINT_ONLY=1 ; _ALT_UNWIND=1 ; _ALT_UNBOUND=0 ; _ALT_RPZ=0
			    _LOG=0 ; _NO_UID_CHECK=1 ; confpath='/dev/null' ; getroot='false' ;;
		    log) _LOG=1 ;;
		    strict) _STRICT=1 ;;
		    uid-check) _NO_UID_CHECK=0 ;;
		    pipefail) set -o pipefail ;;
		    verbose) _VERBOSE=1 ;;
		    nolog) _LOG=0 ;;
		    no-strict) _STRICT=0 ;;
		    no-uid-check) _NO_UID_CHECK=1 ;;
		    no-verbose) _VERBOSE=0 ;;
		    rpz) _ALT_RPZ=1 ;; # We use RPZ data by default
		    unbound) _ALT_UNBOUND=1 ; _ALT_RPZ=0 ;;
		    unwind) _ALT_UNWIND=1 ; _ALT_RPZ=0 ; confpath='/var/db/unwind-adblock.db' ;;
		    *) ERR "Invalid option for '-o' : '${OPTARG}'" ;;
		esac
		;;
	    r)  # Add custom rule
		_user_rule[${_r_counter}]="${OPTARG}" # Custom user rules
		(( _r_counter++ )) || true ;;
	    t)  # Add domain-only URL in bulk from local list
		if [ -f "${OPTARG}" ] && [ -r "${OPTARG}" ]; then
		   for _i in $(SANITIZE_ARRAY < "${OPTARG}"); do
			_domain_url[${_d_counter}]="${_i}"
			(( _d_counter++ )) || true
		   done
		else
			ERR "File '${OPTARG}' either not found or has incorrect permissions!"
		fi ;;
	    u)  # Add /etc/hosts URL in bulk from local list
		if [ -f "${OPTARG}" ] && [ -r "${OPTARG}" ]; then
		   for _i in $(SANITIZE_ARRAY < "${OPTARG}"); do
			_hosts_url[${_l_counter}]="${_i}"
			(( _l_counter++ )) || true
		   done
		else
			ERR "File '${OPTARG}' either not found or has incorrect permissions!"
		fi ;;
	    w)  # Add custom user rules in bulk from local list
		if [ -f "${OPTARG}" ] && [ -r "${OPTARG}" ]; then
		   for _i in $(SANITIZE_ARRAY < "${OPTARG}"); do
			_user_rule[${_r_counter}]="${_i}"
			(( _r_counter++ )) || true
		   done
		else
			ERR "File '${OPTARG}' either not found or has incorrect permissions!"
		fi ;;
	    x)  _PRINT_ONLY=1 ; _LOG=0 ; _NO_UID_CHECK=1 ; confpath='/dev/null' ; getroot='false' ;;  # Print generated list to stdout
	    ?)  HELP_MESSAGE 1>&2 ; exit 2 ;;
    	esac
	done

	# Mark commandline flags as read-only
	readonly _CHECK_ONLY _NO_UID_CHECK _PRINT_ONLY _VERBOSE

	# Mark user-defined variables as read-only
	readonly _AGENT _LOG _STRICT _HOSTS_FMT_BLOCKLISTS _DOMAIN_FMT_BLOCKLISTS _WHITELIST 

	# Set variables based on specified operating system
	# We use 'test -n' here to check for config overrides provided via commandline argument
	case "${_OS_TYPE}" in
	alpine)
	  test -n "${getroot}" || getroot="$(CHECK_CMD doas)"
	  test -n "${netget}" || netget='wget'
	  test -n "${rcd}" || rcd="$(CHECK_CMD rc-service)"
	  test -n "${rcdarg1}" || rcdarg1='unbound'
	  test -n "${rcdarg2}" || rcdarg2='restart'
	  test -n "${confpath}" || confpath='/etc/unbound/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/etc/unbound/adblock.conf' ; fi
	  ;;
	dragonflybsd)
	  test -n "${getroot}" || getroot="$(CHECK_CMD doas)"
	  test -n "${netget}" || netget='fetch'
	  test -n "${rcd}" || rcd="$(CHECK_CMD service)"
	  test -n "${rcdarg1}" || rcdarg1='unbound'
	  test -n "${rcdarg2}" || rcdarg2='restart'
	  test -n "${confpath}" || confpath='/usr/local/etc/unbound/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/usr/local/etc/unbound/adblock.conf' ; fi
	  ;;
	freebsd)
	  test -n "${getroot}" || getroot="$(CHECK_CMD doas)"
	  test -n "${netget}" || netget='fetch'
	  test -n "${rcd}" || rcd="$(CHECK_CMD service)"
	  test -n "${rcdarg1}" || rcdarg1='unbound'
	  test -n "${rcdarg2}" || rcdarg2='restart'
	  test -n "${confpath}" || confpath='/usr/local/etc/unbound/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/usr/local/etc/unbound/adblock.conf' ; fi
	  ;;
	linux)
	  test -n "${getroot}" || getroot="$(CHECK_CMD sudo)"
	  test -n "${netget}" || netget='wget'
	  test -n "${rcd}" || rcd="$(CHECK_CMD systemctl)"
	  test -n "${rcdarg1}" || rcdarg1='restart'
	  test -n "${rcdarg2}" || rcdarg2='unbound'
	  test -n "${confpath}" || confpath='/etc/unbound/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/etc/unbound/adblock.conf' ; fi
	  ;;
	netbsd)
	  # NetBSD does annoying things with their $PATH, so make sure we set what we need
	  PATH="/usr/pkg/bin:/usr/pkg/sbin:${PATH}"
	  test -n "${getroot}" || getroot="$(CHECK_CMD doas)"
	  test -n "${netget}" || netget='curl'
	  test -n "${rcd}" || rcd="$(CHECK_CMD service)"
	  test -n "${rcdarg1}" || rcdarg1='unbound'
	  test -n "${rcdarg2}" || rcdarg2='restart'
	  test -n "${confpath}" || confpath='/usr/pkg/etc/unbound/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/etc/unbound/adblock.conf' ; fi
	  ;;
	openbsd)
	  test -n "${getroot}" || getroot="$(CHECK_CMD doas)"
	  test -n "${netget}" || netget='ftp'
	  test -n "${rcd}" || rcd="$(CHECK_CMD rcctl)"
	  test -n "${rcdarg1}" || rcdarg1='reload'
	  test -n "${rcdarg2}" || rcdarg2='unbound'
	  test -n "${confpath}" || confpath='/var/unbound/db/adblock.rpz'
	  if [ "${_ALT_UNBOUND}" -eq 1 ]; then confpath='/var/unbound/db/adblock.conf' ; fi
	  ;;
	custom)
	  test -n "${getroot}" || ERR "Custom OS type specified - please set doas/sudo preference with '-Z' option"
	  test -n "${netget}" || ERR "Custom OS type specified - please set ftp/fetch/curl preference with '-F' option"
	  test -n "${rcd}" || rcd='false'
	  test -n "${confpath}" || ERR "Custom OS type specified - please specifiy path to adblock.rpz with '-W' option"
	  ;;
	*)
	  printf '\n\nUnknown Operating System Specified. Available Options Are:\n * Alpine\n * DragonflyBSD\n * FreeBSD\n * Linux\n * NetBSD\n * OpenBSD\n\n' 1>&2
	  printf '\nQuitting Without Making Changes...\n' 1>&2
	  exit 1
	  ;;
	esac

	# Mark operating system specific variables as read-only
	readonly getroot netget rcd rcdarg1 rcdarg2 confpath

	# Add domain blocklist URLs specified in config to array
	if [ "${#_domain_url[@]}" -ge 1 ]; then
		_array_index=$((${#_domain_url[@]} + 1))
	else
		_array_index=0
	fi
	for _url in $(PRINT_DOMAIN_LIST); do
		_domain_url[${_array_index}]="${_url}"
		(( _array_index++ )) || true
	done

	# Add hosts blocklist URLs specified in config to array
	if [ "${#_hosts_url[@]}" -ge 1 ]; then
		_array_index=$((${#_hosts_url[@]} + 1))
	else
		_array_index=0
	fi
	for _url in $(PRINT_HOSTS_LIST); do
		_hosts_url[${_array_index}]="${_url}"
		(( _array_index++ )) || true
	done

	# Mark arrays as read-only
	readonly _domain_url _hosts_url _user_rule

	# Config test / dry run
	if [ "${_CHECK_ONLY}" -eq 1 ]; then
		if VAR_SANITY_CHECK && PRE_EXEC_TESTS ; then
			printf 'Config looks sane!\n' 1>&2 ; exit 0
		else
			ERR 'Invalid config!'
		fi
	fi

	# Ensure user-provided values are sane
	VAR_SANITY_CHECK

	# This is marked late because VAR_SANITY_CHECK() may modify it
	readonly _RETRY

	# Run pre-execution tests to ensure that conditions are sane
	PRE_EXEC_TESTS

	# Safely create temporary files
	tmpdir_domain="$(mktemp -d || TMP_FILE_ABORT)"
	tmpdir_hosts="$(mktemp -d || TMP_FILE_ABORT)"
	scratchdir="$(mktemp -d || TMP_FILE_ABORT)"
	workdir="$(mktemp -d || TMP_FILE_ABORT)"
	tmpfile_domain="$(TMP_FILE_SCRATCH)"
	tmpfile_hosts="$(TMP_FILE_SCRATCH)"
	user_rules="$(TMP_FILE_SCRATCH)"
	oldconf="$(TMP_FILE_SCRATCH)"
	cnvtemp="$(TMP_FILE_SCRATCH)"
	finout="$(TMP_FILE_SCRATCH)"
	rawout="$(TMP_FILE_SCRATCH)"
	gztemp="$(TMP_FILE_SCRATCH)"

	# Mark temporary file locations as read-only
	readonly tmpdir_domain tmpdir_hosts scratchdir workdir   \
		 tmpfile_domain tmpfile_hosts user_rules oldconf \
		 cnvtemp finout rawout gztemp

	# Set working directory
	cd -- "${workdir}" || TMP_FILE_ABORT

	# Generate user whitelist rules
	if [ "${_ALT_RPZ}" -eq 1 ] && [ "${#_user_rule[@]}" -ge 1 ]; then
		for _i in "${_user_rule[@]}"; do
			printf '%s CNAME rpz-passthru.\n' "${_i}"
		done | mysort -u > "${user_rules}"
	fi

	# Fetch /etc/hosts blocklist urls
	for _i in "${_hosts_url[@]}"; do
		URL_FETCH "${_i}" "$(TMP_FILE_HOSTS)"
	done

	# Fetch domain blocklist urls
	for _i in "${_domain_url[@]}"; do
		URL_FETCH "${_i}" "$(TMP_FILE_DOMAIN)"
	done

	# Generate lists to load into unbound
	LIST_GEN

	# If -x option is specified, we just print the generated list to stdout
	# without reloading the unbound blocklist or touching the filesytem (other than /tmp)
	if [ "${_PRINT_ONLY}" -eq 1 ]; then
		if [ "${_ALT_RPZ}" -eq 1 ]; then
			# Print cross-platform RPZ blocklist data to stdout
			if test -s "${user_rules}" ; then 
				cat -- < "${user_rules}"
			fi
			sed 's/$/ CNAME ./g' < "${rawout}"
		elif [ "${_ALT_UNWIND}" -eq 1 ]; then
			# Print raw domain blocklist data to stdout
			cat -- < "${rawout}"
		elif [ "${_ALT_UNBOUND}" -eq 1 ]; then
			# Print unbound specific blocklist data to stdout
			RAW_TO_UNBOUND < "${rawout}"
		else
			ERR 'No adblock backend enabled!'
		fi
	else
		# Install newly generated blocklist
		LIST_INSTALL
	fi

	# Print Blocklist Stats
	WARNING "$(PRINT_STATS)"

	# Clean up after ourselves
	CLEANUP
}

# ZSH needs to run in compatability mode to prevent it from puking
if command -v emulate >/dev/null 2>&1 ; then
	emulate -LR ksh
fi

# Make sure shell supports typeset
command -v typeset >/dev/null 2>&1 || ERR 'Are you running a modern shell? Current shell does not appear to support the non-POSIX "typeset" command...'

# Execute main function
main "$@"



