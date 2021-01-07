#!/bin/bash

set -o nounset      # Crash when an unset variable is used
set -o errtrace     # Capture errors in functions, command substitutions and subshells
set -o errexit      # Exit when a command fails
set -o pipefail     # Capture and crash when pipes failed anywhere in the pipe

declare -r ScriptVersion="SCRIPT DESCRIPTION v1.0.8, 2021-01-08, by YOUR NAME, YOUR EMAIL"
declare -r ProcID="$(echo $$)"
    # ^ Script process ID for logging purposes
declare -r ScriptName="ScriptName"
    # ^ Script name for logging purposes
declare -r CurrentUser="$(id -un)"
declare -r ScriptMaxLogLevel="debug"
    # ^ Max log level lines that will be logged (case insensitive)
    #   Supported values - none, critical, error, warning, info, debug
    #   For example - if you set it to "WARNING" then INFO and DEBUG
    #   level lines will not get logged (only CRITICAL, ERROR, WARNING
    #   lines will get logged).
    #   Use "NONE" to disable logging.
declare -r SyslogProgName="ProgramName"
    # ^ This is 'ProgramName' in syslog line (just before the PID value)
    #   Different from ScriptName because ProgramName allows syslog to filter
    #   and log lines with this value in different files.
    #   So you can configure syslog to log all your programs to your
    #   own log file by using your own ProgramName here.
declare -r OriginalIFS="${IFS}"
    # ^ In case we need to change it along the way

. /usr/local/lib/rhinolib.sh || {
    echo "Cannot source /usr/local/lib/rhinolib.sh . Aborting!"
    exit 150
    }

# Setup error traps that send debug information to rhinolib for logging:
trap 'ErrorTrap "$LINENO" "$?" "$BASH_COMMAND" "$_" "${BASH_SOURCE[*]}" "${FUNCNAME[*]}" "${BASH_LINENO[*]}"' ERR
trap 'ExitScript' EXIT

SymLinkResolved="(Symlink resolved: $( readlink --quiet --no-newline $0 )) " || SymLinkResolved=""
LogWrite info "${ScriptVersion}"
LogWrite debug "Invoked commandline: $0 $* ${SymLinkResolved}, from directory: ${PWD:-unknown} , by user: $UID: ${CurrentUser:-unknown} , PPID: ${PPID:-unknown} , Script max log level ${ScriptMaxLogLevel}"

# Script body begins here. Put your code below this:


# The lines that are actually written to log depend upon the maximum value of ${ScriptMaxLogLevel}
# The loglevel codes are described in RhinoLib

# Error condition logs:
LogWrite critical "This is the most severe log level and usually describes a script crash. This is justifiction for the script to die"
LogWrite error "Major error in the system, but normally not in the script itself. The script normally voluntarily exits here"
LogWrite warning "Normally a warning about various conditions. Script continues to run"

# Information condition logs:
LogWrite info "Information for regular operators to interpret"
LogWrite debug "Information for advanced engineers/developers to interpret"
    # ^ A very long line from shakespere used for testing log line splitting


# Script body ends here. Put your code above this

# You cannot simply 'exit' or 'exit 0' because the error trap is designed
# to catch unintended exits.
# You must exit using the format below:
# Note - the ERRORTEXT is given in this case!


ExitScript info 0 "Script completed successfully"
    # ^ Successful exits are info/debug and code 0

ExitScript error 150 "Script exited with an error"
    # ^ Failed exits are critical/error/warning and code != 0

