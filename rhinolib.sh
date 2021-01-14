# rhinolib bash script function library v1.5.5
# 2021-01-08 by Kenneth Aaron , flyingrhino AT orcon DOT net DOT nz
# License: GPLv3.

# Prerequisites:
#
# Place this rhinolib.sh file under /usr/local/lib/
# Calling script must have these vars configured:
# ProcID, ScriptName, ScriptMaxLogLevel, SyslogProgName
# See example script_template.sh for examples.
# In order to use function LogNftRules - you must define the NftCommand
# variable in your calling script as the path to nftables 'nft' command.
#
# Using this library will give you summary failure logs in
# /tmp/rhinolib_script_errors . Use it as a reference if required.
# I also use the presence of this file for detecting errors.


declare -r FailureTrapFile="/tmp/rhinolib_script_errors"
declare -r IndentString="    ...."
    # ^ In my python3 code I actually calculate the resulting string, but here it's
    #   good enough using a hardcoded string.
declare -r MaxLogLineLength=700
    # ^ Wrap lines longer than this. It's a good idea to keep this a sensible
    #   length. 700 is a good value.
    #   In LM19.3 syslog truncates at about 1000 chars.
    #   Note - please use a length 40 chars LESS than what you actually want
    #   because we're prepending/appending !!LINEWRAPPED!! to wrapped lines and
    #   adding the IndentString.
    #   Eg - if you want max 800 then configure 760.
    #   The reason for this is to avoid doing math in the wrapping code at
    #   this stage, and compensating for the IndentString.
    #   Note - this value only applies to the log text, not the syslog-created
    #   content, nor the additional log data I create inside the (...) - if you
    #   are calculating total line length, assume an additional 130-150 chars
    #   for this overhead.
declare -r ExpandBSN="yes"
    # ^ LogWrite expands \n in messages to newline in log file


#These tests verify that the calling script supplied these vars:
[ "$ProcID" ]               # Should fail due to shopt -s -o nounset
[ "$ScriptName" ]           # Same.
[ "$ScriptMaxLogLevel" ]    # Same.
[ "$SyslogProgName" ]       # Same.


function LogWrite {
    # Usage LogWrite <LOG_LEVEL> <LOG_TEXT>
    # LOG_LEVEL must be one of: none, critical, error, warning, info, debug
    # and is case insensitive.
    #
    # Send whatever LOG_TEXT string you want - with or without newlines,
    # and as long as you want. LogWrite will split the string into shorter log lines
    # if necessary (per MaxLogLineLength setting) , and handle indentation
    # chars for the new lines.
    #
    # Logging using "LogWrite" mimics the syslog format I use in my open source
    # python code.

    local LogLevelText=${1:-ERROR}
        # ^ Holds the log level (ERROR, INFO, etc) of the calling log line

    LogLevelText="${LogLevelText^^}"    # Uppercase it

    # Is the calling log level text correct?
    # Note - if you forgot to supply the log level text as $1 and only supplied
    # the log line (which will be $1) - it will be overwritten by this code block,
    # meaning you get "ERROR" and no log line content:
    case "${LogLevelText}" in
        NONE | CRITICAL | ERROR | WARNING | INFO | DEBUG )     :;;
        *)                                              LogLevelText="ERROR";;
    esac

    local LogText=
    local -a RecordMsgSplitNL=()
        # ^ Split the message sent to LogWrite into an array of lines
        #   at the newline character
    local -a SplitLinesMessage=()
        # ^ Final version of line splitting
    local LoggerText

    # This block will stop processing if the script's ScriptMaxLogLevel is lower than the
    # log level of the log line. Kind of dirty way of doing it but bash doesn't supply
    # search in array, and regex search is clumsy.

    [[ "${ScriptMaxLogLevel^^}" == "NONE" ]] && return
        # ^ Script requested no logging

    [[ "${ScriptMaxLogLevel^^}" == "CRITICAL" && "${LogLevelText}" != "CRITICAL" ]] && return
        # ^ Only CRITICAL level logging

    [[ "${ScriptMaxLogLevel^^}" == "ERROR" ]] && \
        {
        case "${LogLevelText}" in
            WARNING | INFO | DEBUG )    return;;
        esac
        }
        # ^ Only CRITICAL and ERROR level logging

    [[ "${ScriptMaxLogLevel^^}" == "WARNING" ]] && \
        {
        case "${LogLevelText}" in
            INFO | DEBUG )    return;;
        esac
        }
        # ^ Only CRITICAL, ERROR and WARNING level logging

    [[ "${ScriptMaxLogLevel^^}" == "INFO" && "${LogLevelText}" == "DEBUG" ]] && return
        # ^ Log level INFO means only DEBUG is not allowed

    [[ "${ScriptMaxLogLevel^^}" == "DEBUG" ]] && \
        {
        :
        } || {
        ScriptMaxLogLevel="NotSetCorrectly"
            # Best to crash the script if ScriptMaxLogLevel wasn't set correctly.
            # Check the value of ScriptMaxLogLevel - it should be one of the
            # allowed values.
        }


    shift       # Message was sent in $2
    LogText="${1:-"Check if you supplied Log Level and Error message args to LogWrite"}"
    # ^ Check if log message was supplied else set it to a warning message

    # Now we have the message, code for line splitting follows:

    #LogText="${LogText//$'\n'/__|__}"
    # ^ Uncomment if you don't want newlines in your logged text
    #   This will still split long lines per MaxLogLineLength...

    # Replace tab with 4 spaces (because logger writes #011 instead of tab):
    LogText="${LogText//$'\t'/    }"

    # Expand messages containing \n to new line:
    # Otherwise a message such as   LogWrite 4 "hello\nline"
    # appears as one line with the same literal txt
    [[ "${ExpandBSN}" == "yes" ]] && \
        {
        LogText="${LogText//\\n/$'\n'}"
        }

    # Place other text conversions here, before we convert variable LogText
    # into array RecordMsgSplitNL:
    # ^ End of text conversions above.

    # Expand LogText into an array RecordMsgSplitNL, one line per element.
    # Remember - this is only split by embedded newline char, not by line length!
    local ScriptIFS="${IFS}"
    local IFS=$'\n'
    RecordMsgSplitNL=($LogText)
    local IFS="${ScriptIFS}"

    # Split RecordMsgSplitNL lines if they exceed MaxLogLineLength length
    # otherwise pass them through without splitting.
    # Store results in SplitLinesMessage:
    for LineLooper in "${RecordMsgSplitNL[@]}"
        do
        (( ${#LineLooper} < ${MaxLogLineLength} )) && \
            {

            # Normal line length detected:
            SplitLinesMessage+=("${LineLooper}")

            } || {

            # Long line detected, need to split:
            FullLineLength=${#LineLooper}

            # Figure out how many lines of length MaxLogLineLength we need to split into:
            local -i NumOfSplits=$(( ${FullLineLength} / ${MaxLogLineLength} ))
                # ^ Integer division, remainder lost. So we need to check next
                #   if there is a remainder which means the number of splits
                #   increments by 1.

            (( (${FullLineLength} % ${MaxLogLineLength}) > 0 )) && \
                {
                (( NumOfSplits++ )) || true
                }

            for (( SLALooper=0; SLALooper<${NumOfSplits}; SLALooper++ ))
                do
                local -i StartIndex=$(( SLALooper * ${MaxLogLineLength} ))
                (( ${SLALooper} == 0 )) && \
                    {
                    SplitLinesMessage+=("${LineLooper:${StartIndex}:${MaxLogLineLength}}!!LINEWRAPPED!!")
                        # ^ First split, append !!LINEWRAPPED!! at the end
                    }

                (( (${SLALooper} > 0) && (${SLALooper} < (NumOfSplits-1)) )) && \
                    {
                    SplitLinesMessage+=("!!LINEWRAPPED!!${LineLooper:${StartIndex}:${MaxLogLineLength}}!!LINEWRAPPED!!")
                        # ^ Middle split, prepend and append !!LINEWRAPPED!! at both ends
                    }

                (( ${SLALooper} == (NumOfSplits-1) )) && \
                    {
                    SplitLinesMessage+=("!!LINEWRAPPED!!${LineLooper:${StartIndex}:${MaxLogLineLength}}")
                        # ^ Last split, prepend !!LINEWRAPPED!! at the start
                    }
                done

            }
        done

    # Prepend the "    ...." IndentString to all lines except the first.
    # ( This includes wrapped lines already prepended with !!LINEWRAPPED!! ) :
    local -i Counter=0
    for LineLooper in "${SplitLinesMessage[@]}"
        do
        (( $Counter > 0 )) && \
            {
            TempString="${IndentString}${LineLooper}"
            SplitLinesMessage[$Counter]="${TempString}"
            }
        (( Counter++ )) || true
            # ^ Need the || true else it crashes
        done

    # Write the array to syslog one line at a time per syslog call:
    for LineLooper in "${SplitLinesMessage[@]}"
        do

        # Used to be this code that did columized formatting, but now I'm
        # keeping in in line with my python3 logging:
        #LoggerText=$(printf "%-8s %-12s %-8s (%s) %s\n" \
        #    "${LogLevelText}" "[${ScriptName::10}]" \
        #    "[${ProcID}]" "${FUNCNAME[1]:-"UNKNOWN"}" "${LineLooper}")

        LoggerText="<${LogLevelText}> ($(date +%Y-%m-%d\ %H:%M:%S.%3N) , MN: ${ScriptName} , FN: ${FUNCNAME[1]:-UNKNOWN} , LI: ${BASH_LINENO}):    ${LineLooper}"

        logger --id="${ProcID}" --tag "${SyslogProgName}" "${LoggerText}"
        done
}


function ExitScript {
    # Exit script properly and write log file
    # Format: ExitScript <ERRORLEVEL> <EXITCODE> <REASON>
    #   ERRORLEVEL  - one of: critical, error, warning, info, debug
    #   EXITCODE    - 0 for success, 1-255 for failure
    #   REASON      - plaintext that will be logged at exit time

    LogWrite debug "Function ExitScript started with args: $*"
    local LogLevel="${1:-"error"}"
    shift || :
    local -i ExitCode="${1:-"150"}"
    shift || :
    local ExitReason="${*:-"Error - exit reason was not supplied"}"

    (( $ExitCode !=0 )) && \
        {
        # Perhaps this causes duplicate writes to this file?
        LogWrite error "Exit code not zero, writing timestamp to FailureTrapFile..."
        WriteErrorFile "Exit code not zero"
        }

    trap '' EXIT
        # ^ Stop the exit error trap because we really want to exit here!
    LogWrite "${LogLevel}" "Script end, runtime $SECONDS seconds. Exit code: ${ExitCode} . Exit reason: ${ExitReason}"
    exit "$ExitCode"
    # ^ The script should not continue any further
    LogWrite error "Exit command issued above this line. Script should have already exited"
}


function ErrorTrap {
    LogWrite debug "Function ErrorTrap started"
    WriteErrorFile "Function ErrorTrap called"
    trap '' EXIT
    LogWrite critical "Debugging information: \n Line number: ${1} \n \$BASH_COMMAND: \"${3}\" \n \$LAST_ARGUMENT: \"${4}\" \n failed with exit code: ${2}"
    LogWrite critical "Further debugging info: \n \$BASH_SOURCE: ${5} \n \$FUNCNAME: ${6} \n \$BASH_LINENO: ${7}"
    LogWrite critical "ErrorTrap in RhinoLib PID $$ is going to kill PID ${ProcID} now!"
    kill -9 ${ProcID} &>/dev/null
        # ^ Should not proceed any further
    ExitScript CRITICAL 150 "Killed by ErrorTrap"
}


function WriteErrorFile {
    # Call this function as follows:
    #   WriteErrorFile "Error message"
    # and it will write the Error message to the ErrorFile. This can be later checked by a watchdog script
    # or some other program that acts upon the existence of ErrorFile.
    # This function is called automatically upon script crash, but you can also call it manually
    # if you wish to write error messages to the ErrorFile. For example you have an error handler
    # and your script doesn't crash, but it's important to alert of this error.

    LogWrite debug "Function WriteErrorFile started"
    printf "%s  %s  %s; \n" "$(date +%Y-%m-%d\ %H:%M:%S.%3N)" "[${ScriptName}]" "${*}" >> "${FailureTrapFile}"
    LogWrite debug "Function WriteErrorFile ended"
}


function IsInteger {
    # Requires bash v3 or greater
    # Use: IsInteger "${var}" && echo "int" || echo "not int"
    # If multiple statements then use "if/else" rather than && {} and || {}
    # because it leads to trouble and the function may crash

    [[ "${1}" =~ ^-?[0-9]+$ ]] && return 0 || return 1
}


function IsAlnum {
    # Requires bash v3 or greater
    # Use: IsAlnum "${var}" && echo "pass" || echo "fail"

    [[ "${1}" =~ ^[0-9a-zA-Z]+$ ]] && return 0 || return 1
}


function IsAlnum1 {
    # Requires bash v3 or greater
    # Accept also "-" and "_"

    [[ "${1}" =~ ^[0-9a-zA-Z_-]+$ ]] && return 0 || return 1
}


function IsAlnum2 {
    # Requires bash v3 or greater
    # Accept also "-" , "_" , " "

    [[ "${1}" =~ ^[0-9a-zA-Z\ _-]+$ ]] && return 0 || return 1
}


function CatToFile {
    # Cats text to filename after confirming filename ends in \n
    # Else adds \n before the text
        # $1 filename to modify. If $1 doesn't exist it is created
        # $2 text to add. Remember to quote the text before calling,
        #   not using shift;$* to ease debugging of quoting problems
    # This function returns exit code 1 if it can't complete the request successfully.

    [ -d "$1" ] && \
        {
        LogWrite error "$1 is a directory"
        return 1
        }

    if [[ -f "$1" ]] && [[ -s "$1" ]]   # Regular file non-zero size
        then
            [ "`tail -c 1 $1`" != "" ] && echo >> "$1"  # Line doesn't end in \n
            # Another way of doing it is:  tail -c 1 testfile | hexdump | cut -d " " -f 2 | head -n 1
    fi
    echo "$2" >> "$1" || \
        {
        LogWrite error "Unknown error writing to file $1"
        return 1
        }
}


function UnderlineText {
    # Accepts $1 as the underline character to repeat. Normally '-'
    # and $2 as the text to return underlined

    local UnderlineChar="$1"
    local UnderlineText="$2"
    local -i TextLen="${#UnderlineText}"
    echo "${UnderlineText}"
    while (( TextLen-- > 0 ))
        do
        echo -n "${UnderlineChar}"
    done
    echo
}


function PressAnyKey {
    read -n 1 -rsp "Press any key to continue..." || :
}


function DoYouWantToProceed {
    # Simple y/n to proceed. Accepts anything but only returns
    # 0 if user responds with 'y' or 'Y'
    # Usage: DoYouWantToProceed && echo "user said yes"

    local Ans
    read -p  "--> Do you want to proceed? y/n  " Ans || :
    [[ ( "${Ans}" == "y" ) || ( "${Ans}" == "Y" ) ]] && return 0 || return 1
}


function BackupFile {

    # $1 = Source file
    # $2 = Dest dir
    # This function creates Dest Dir if it does not exist.
    # Returns exit code == 0 if all successful else exit code == 1
    #
    # Usage: BackupFile "/usr/local/bin/test.sh" "/tmp/" || LogWrite 4 "backup failed"
    #   Always include the || or && at the end of the backup command to catch events that fail
    #   otherwise a failed backup could crash your script as a failed command.

    LogWrite debug "BackupFile called with args: $*"
    (( $# != 2 )) && \
        {
        LogWrite warning "Incorrect number of arguments. Expecting 2"
        return 1
        }

    [[ -f "${1}" ]] || \
        {
        LogWrite warning "Cannot find source file: ${1}"
        return 1
        }

    mkdir --parents "${2}" || \
        {
        LogWrite warning "Error creating directory ${2}"
        return 1
        }

    local FileName="$(basename "${1}")"
    local TimeStamp="$(date +%Y-%m-%d_%H%M%S)"
    cp "${1}" "${2}"/"${TimeStamp}"_"${FileName}" && \
        {
        LogWrite info "Successfully copied: ${1} to: ${2}/${TimeStamp}_${FileName}"
        return 0
        } || {
        LogWrite warning "Error copying: ${1} to: ${2}/${TimeStamp}_${FileName}"
        return 1
        }
}


function LogNftRules {
    # Call with: LogNftRules "After making change x y z"
    # ^ Supply some identifying text within the "..." so that you can find it in the logs

    LogWrite info "NFT OUTPUT LOGGING STARTS BELOW FOR: ${1}"
    local NftRules="$(sudo ${NftCommand} list ruleset -nn --handle 2>&1)"
        # ^ May need to check if the script's user can sudo, else I need
        #   to log it with an error and return 1
    LogWrite info "${NftRules}"
    LogWrite info "NFT OUTPUT LOGGING ENDED ABOVE FOR: ${1}"
}

