#!/bin/bash

declare -r ScriptName="ScriptName"
    # ^ Appears in the extended log info. "${SyslogProgName}"  is the syslog program name
    #       that can be filtered upon (eg with kenmode:  `jcff -t ProgramName`)
declare -r ScriptDescription="Script template for use with rhinolib"
declare -r ScriptVersion="1.1.1"
declare -r ScriptDate="2024-11-29"
declare -r ScriptCopyright="2024+"
declare -r ScriptAuthor="Kenneth Aaron"
declare -r ScriptAuthorEmail="flyingrhino AT orcon DOT net DOT nz"
declare -r ScriptLicense="GPLv3"
declare -r ScriptRepo="https://github.com/flyingrhinonz/rhinolib_bash"

# This script originates from the master script file that comes with rhinolib.
# Edit and reuse this script to take advantage of rhinolib functions.
# For details refer to github:  https://github.com/flyingrhinonz/rhinolib_bash .
#
# Place a description of your script here.


set -o nounset      # Crash when an unset variable is used
set -o errtrace     # Capture errors in functions, command substitutions and subshells
set -o errexit      # Exit when a command fails
set -o pipefail     # Capture and crash when pipes failed anywhere in the pipe


declare -r ProcID="$(echo $$)"
    # ^ Script process ID for logging purposes
    #   Note - in systemd / journalctl the PID of logger is displayed and not this!
    #   Therefore I log it separately in rhinolib.

declare -r CurrentUser="$( /usr/bin/id -un )"

declare -r ScriptMaxLogLevel="debug"
    # ^ Max log level lines that will be logged (case insensitive)
    #   Supported values - none, critical, error, warning, info, debug
    #   For example - if you set it to "WARNING" then INFO and DEBUG
    #   level lines will not get logged (only CRITICAL, ERROR, WARNING
    #   lines will get logged).
    #   Use "NONE" to disable logging.
    #   Check rhinolib for details on how a typo in this variable is handled.

declare -r SyslogProgName="ProgramName"
    # ^ This is 'ProgramName' in syslog line (just before the PID value)
    #   Different from ScriptName because ProgramName allows syslog to filter
    #       and log lines with this value in different files.
    #   So you can configure syslog to log all your programs to your
    #       own log file by using your own ProgramName here.
    #   In journalctl use this for tailing based on ProgramName:
    #     journalctl -fa -o short-iso -t ProgramName

declare -r OriginalIFS="${IFS}"
    # ^ In case we need to change it along the way


if ! . /usr/local/lib/rhinolib.sh; then
    echo "CRITICAL - Cannot source:  /usr/local/lib/rhinolib.sh  . Aborting!"
    logger -a "${SyslogProgName}" "CRITICAL - Cannot source:  /usr/local/lib/rhinolib.sh  . Aborting!"
    exit 150
fi


# Setup error traps that send debug information to rhinolib for logging:
trap 'ErrorTrap "$LINENO" "$?" "$BASH_COMMAND" "$_" "${BASH_SOURCE[*]}" "${FUNCNAME[*]:-FUNCNAME_is_unset}" "${BASH_LINENO[*]}"' ERR
    # ^ In RH I found that this trap gives an error: FUNCNAME[*]: unbound variable
    #     so I'm mitigating that by checking for unset and supplying text 'FUNCNAME_is_unset'
trap 'ExitScript' EXIT


SymLinkResolved="(Symlink resolved: $( /bin/readlink --quiet --no-newline $0 )) " || SymLinkResolved=""
LogWrite info "${ScriptDescription} . v${ScriptVersion} , ${ScriptDate} , by ${ScriptAuthor} ( ${ScriptAuthorEmail} )"
    # ^ Results in a line like:
    #       2024-11-11T09:24:51+1300 andromeda ProgramName[169940]: <INFO> (PID: 169935 , MN: ScriptName , FN: main , LI: 71):    Script template for use with rhinolib  v1.0.0 , 2024-11-11 , by Kenneth Aaron ( flyingrhino AT orcon DOT net DOT nz )
    #                                          ^ ${SyslogProgName}                            ^ ${ScriptName}
LogWrite info "Invoked commandline: $0 $* ${SymLinkResolved}, from directory: ${PWD:-unknown} , by user: $UID: ${CurrentUser:-unknown} , ProcID: ${ProcID} , PPID: ${PPID:-unknown} , Script max log level: ${ScriptMaxLogLevel}"
LogWrite info "Fields explained: PID == Script PID , MN == Module (script) Name , FN == Function Name , LI == LIne number"
    # ^ The reason we have a PID in here is because journalctl logs the PID of the 'logger' command
    #       (that is used to do the actual logging, and this changes every time a line is logged)
    #       and not the PID of the actual script.
    #   MN field is present to keep this log line identical to the log line I use in my python code.


# Setup variables here:


# Script body begins here. Put your code below this:


# The lines that are actually written to log depend upon the maximum value of ${ScriptMaxLogLevel}
# The loglevel codes are described in RhinoLib

# Error condition logs:
LogWrite critical "This is the most severe log level and usually describes a script crash. This is justifiction for the script to die"
LogWrite error "Major error in the system, but normally not in the script itself. The script normally voluntarily exits here"
LogWrite warning "Normally a warning about various conditions. Script continues to run"

# Information condition logs:
LogWrite -t info "Info level log + output to screen"
    # ^ This line uses:  -t  to tell LogWrite to write log + print to screen.
    #   You can use:  -t  on any log level and text is output to screen respecting the
    #       log level - if the log level is higher than the line level - no text is output.
    #   Use the:  -a  arg (instead of:  -t) to ALWAYS print to screen - ignoring the log level.
LogWrite debug "Information for advanced engineers/developers to interpret"
    # ^ A very long line from shakespere used for testing log line splitting


# Script body ends here. Put your code above this

# You cannot simply 'exit' or 'exit 0' because the error trap is designed
# to catch unintended exits.
# You must exit using the format below:
# Note - the ERRORTEXT is given in this case!


ExitScript -a info 0 "Script completed successfully"
    # ^ Successful exits are info/debug and code 0
    #       The optional:  -t or:  -a  ALWAYS echoes the line to stdout too.
    #       Only in the case of:  ExitScript  the line is always echoed - ignoring the log level.

ExitScript error 150 "Script exited with an error"
    # ^ Failed exits are critical/error/warning and code != 0

