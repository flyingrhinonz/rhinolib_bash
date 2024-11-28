# Name:         rhinolib
# Description:  bash script function library
# Version:      1.6.28
# Date:         2024-11-29
# Copyright:    2021+ Kenneth Aaron , flyingrhino AT orcon DOT net DOT nz
# License:      GPLv3
# Github:       https://github.com/flyingrhinonz/rhinolib_bash


# Prerequisites:
#
# Place this:  rhinolib.sh  file under:  /usr/local/lib/ .
# Calling script must have these vars configured:
#   ProcID, ScriptName, ScriptMaxLogLevel, SyslogProgName
# See example:  script_template.sh  for examples.
#
# Using this library will give you summary failure logs in
#   /tmp/rhinolib_script_errors . Use it as a reference if required.
#   I also use the presence of this file for detecting errors.


declare -r FailureTrapFile="/tmp/rhinolib_script_errors_${CurrentUser}"
    # ^ Now it's per user name in case of write permissions
    #   Note - this file does not survive reboots due to living in:  /tmp/
declare -r IndentString="    ...."
    # ^ In my python3 code I actually calculate the resulting string, but here it's
    #   good enough using a hardcoded string.
declare -r MaxLogLineLength=700
    # ^ Wrap lines longer than this. It's a good idea to keep this a sensible
    #       length. 700 is a good value.
    #   In LM19.3 syslog truncates at about 1000 chars.
    #   Note - configure a length 40 chars LESS than what you actually want
    #       because we're prepending and/or appending !!LINEWRAPPED!! to wrapped lines
    #       as well as adding the IndentString.
    #   Eg - if you want max 800 then configure 760.
    #       The reason for this is to avoid doing math in the wrapping code at
    #       this stage, and compensating for the IndentString.
    #   Note - this value only applies to the log text, not the syslog-created
    #       content, nor the additional log data I create inside the (...) - if you
    #       are calculating total line length, assume an additional 130-150 chars
    #       for this overhead.
declare -r ExpandBSN="yes"
    # ^ LogWrite expands \n in messages to newline in log file


# The following are linux commands that may exist in more than one place
#   therefore we will check for and use their correct path:

# getopt can exist in one of two places.
# If neither is found the script will crash on unset var which is good:
if [[ -x "/bin/getopt" ]]; then
    declare -r RhinoLib_GetoptCmd="/bin/getopt"
        # ^ RHEL 7/8 , Debian , LM19
elif [[ -x "/usr/bin/getopt" ]]; then
    declare -r RhinoLib_GetoptCmd="/usr/bin/getopt"
        # ^ RHEL 6
fi

# tail can exist in one of two places.
# If neither is found the script will crash on unset var which is good:
if [[ -x "/bin/tail" ]]; then
    declare -r RhinoLib_TailCmd="/bin/tail"
        # ^ RHEL 7/8 , Debian , LM19
elif [[ -x "/usr/bin/tail" ]]; then
    declare -r RhinoLib_TailCmd="/usr/bin/tail"
        # ^ RHEL 6
fi

# logger can exist in one of two places:
# If neither is found the script will crash on unset var which is good.
if [[ -x "/bin/logger" ]]; then
    declare -r RhinoLib_LoggerCmd="/bin/logger"
        # ^ RHEL 5
elif [[ -x "/usr/bin/logger" ]]; then
    declare -r RhinoLib_LoggerCmd="/usr/bin/logger"
        # ^ RHEL 6/7/8 , Debian , LM19
fi


# These tests verify that the calling script supplied these vars:
[ "$ProcID" ]               # Should fail due to shopt -s -o nounset
[ "$ScriptName" ]           # Same.
[ "$SyslogProgName" ]       # Same.
[ "$ScriptMaxLogLevel" ]    # Same.


function LogWrite {
    #   Usage: LogWrite [-t|-a] <LOG_LEVEL> <LOG_TEXT>
    #   LOG_LEVEL must be one of: none, critical, error, warning, info, debug
    #       and is case insensitive.
    #       Only lines equal to, or more severe than:  LOG_LEVEL  will be logged
    #       and optionally tee'd to stdout (-t arg).
    #
    #   Send whatever LOG_TEXT string you want - with or without newlines,
    #       and as long as you want. LogWrite will split the string into shorter log lines
    #       if necessary (per MaxLogLineLength setting) , and handle indentation
    #       chars for the new lines.
    #
    #   If you supply the optional:  -t  arg, LogWrite will also send the log line
    #       to stdout (echo) which mimics the linux tee feature - this is also
    #       subject to the value of:  LOG_LEVEL and will not echo for lower levels.
    #       Note - the echoed line will be printed as supplied without any of the
    #       fancy LogWrite string manipulation.
    #   The args:  -t  and:  -a  are mutually exclusive - you can only use one of them.
    #   Furthermore - the script is currently hardcoded to expect ONLY ONE optional arg
    #       as $1 (-t or -a). After clearing this ONE ARG, it then expects the next arg
    #       to be the LOG_LEVEL.
    #
    #   The optional:  -a  arg is similar to the:  -t  arg, but ALWAYS prints the
    #       log line to stdout REGARDLESS the value of:  LOG_LEVEL.
    #
    #   Logging using "LogWrite" mimics the syslog format I use in my open source
    #       python code.
    #
    #   Examples:
    #       LogWrite debug "This is a debug level log - written to log file only"
    #       LogWrite -t info "This line is logged and also printed to the screen"

    local TeeFlag="false"
    local AlwaysTeeFlag="false"
        # ^ Mutually exclusive:  If either flag is set then echo the message too.
        #   Note - this feature also appears in function:  ExitScript  - make sure you
        #       modify that function too if you make changes to this feature.

    # Special flags can be supplied to LogWrite. Check if any are present:
    if (( $# > 0 )); then
        case "${1}" in
            "-t")   TeeFlag="true"
                        # ^ Set the:  TeeFlag  so that we can print the line to screen too
                        #   Respects the value of:  LOG_LEVEL.
                    shift;;
                        # ^ We need this because the rest of LogWrite function assumes that
                        #       it is called with $1 (log level) and $2 (log message).
            "-a")   AlwaysTeeFlag="true"
                        # ^ Set the:  AlwaysTeeFlag  so that we ALWAYS print the line to screen too
                        #   Ignores the value of:  LOG_LEVEL and always prints to stdout.
                    shift;;
            *)      :;;
        esac
    fi

    local CallingLineLogLevel=${1:-ERROR}
        # ^ This is $1 since the SINGLE optional flag was cleared above and the arg shifted.
        #   Holds the log level (ERROR, INFO, etc) of the calling log line.
        #   Note - if you called LogWrite with no args then the log level which
        #       was supposed to be sent in:  $1 will be forced to:  ERROR .
        #       Also, $2 will be missing and it too will be preset by rhinolib
        #       to an error message which indicates the message part was missing.

    CallingLineLogLevel="${CallingLineLogLevel^^}"    # Uppercase it

    # Is the calling log level text correct?
    # Note - if you didn't send the log level correctly it will be forced
    #   here to:  ERROR  which hopefully will cause you to notice that your
    #   logging is wrong and you'll fix the log level in your caller:
    case "${CallingLineLogLevel}" in
        NONE | CRITICAL | ERROR | WARNING | INFO | DEBUG )      :;;
        *)                                                      CallingLineLogLevel="ERROR";;
    esac

    local LogText=
    local -a RecordMsgSplitNL=()
        # ^ This array will hold the message sent to Logrite as an array of lines
        #       split at the newline character.
    local -a SplitLinesMessage=()
        # ^ This array will hold the final version of line splitting after we do
        #       some processing in rhinolib.
    local LoggerText

    shift       # Message was sent in what is now $1
    LogText="${1:-"Check if you supplied Log Level and Error message args to the calling LogWrite"}"
        # ^ Looks like there's no  $2  argument  in your  LogWrite  line, so we'll
        #       force some log text for you, hopefully you'll pick this up in your logging output.

    if [[ "${AlwaysTeeFlag}" == "true" ]]; then
        echo -e "${LogText}"
            # ^ The:  -e  allows controls in the string such as  \n  to be respected.
    fi
        # ^ AlwaysTeeFlag was set - print the log line to screen ALWAYS.
        #   No fancy text processing is done on this line - it is printed exactly as supplied.

    # This block will stop processing if the script's ScriptMaxLogLevel is lower than the
    # log level of the log line. Kind of dirty way of doing it but bash doesn't supply
    # search in array, and regex search is clumsy.

    if [[ "${ScriptMaxLogLevel^^}" == "NONE" ]]; then
        return
        # ^ Script requested no logging
    fi

    if [[ "${ScriptMaxLogLevel^^}" == "CRITICAL" && "${CallingLineLogLevel}" != "CRITICAL" ]]; then
        return
        # ^ Only CRITICAL level logging
    fi

    if [[ "${ScriptMaxLogLevel^^}" == "ERROR" ]]; then
        case "${CallingLineLogLevel}" in
            WARNING | INFO | DEBUG )    return;;
        esac
    fi
        # ^ Only CRITICAL and ERROR level logging

    if [[ "${ScriptMaxLogLevel^^}" == "WARNING" ]]; then
        case "${CallingLineLogLevel}" in
            INFO | DEBUG )    return;;
        esac
    fi
        # ^ Only CRITICAL, ERROR and WARNING level logging

    if [[ "${ScriptMaxLogLevel^^}" == "INFO" && "${CallingLineLogLevel}" == "DEBUG" ]]; then
        return
        # ^ Log level INFO means only DEBUG is not allowed
    fi

    #if [[ "${ScriptMaxLogLevel^^}" == "DEBUG" ]]; then
    #   :
    #fi
        # ^ Log level DEBUG means everything is allowed
        #   Commenting out this line means it will accept  DEBUG  level or
        #       any invalid text supplied in this variable.
        #   If you wish to enforce correct values in this variable - uncomment
        #       this test and uncomment the test earlier in this script.

    if [[ "${TeeFlag}" == "true" ]]; then
        echo -e "${LogText}"
            # ^ The:  -e  allows controls in the string such as  \n  to be respected.
    fi
        # ^ TeeFlag was set - print the log line to screen too.
        #   No fancy text processing is done on this line - it is printed exactly as supplied.

    # Now we have the message, the code for line splitting follows:

    #LogText="${LogText//$'\n'/__|__}"
    # ^ Uncomment if you don't want newlines in your logged text
    #   This will still split long lines per MaxLogLineLength...

    # Replace tab with 4 spaces (because logger writes #011 instead of tab):
    LogText="${LogText//$'\t'/    }"

    # Expand messages containing \n to new line:
    # Otherwise a message such as   LogWrite warning "hello\nline"
    # appears as one line with the same literal txt
    if [[ "${ExpandBSN}" == "yes" ]]; then
        LogText="${LogText//\\n/$'\n'}"
    fi

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
    for LineLooper in "${RecordMsgSplitNL[@]}"; do
        if (( ${#LineLooper} < ${MaxLogLineLength} )); then
            # Normal line length detected:
            SplitLinesMessage+=("${LineLooper}")

        else
            # Long line detected, need to split:
            local FullLineLength=${#LineLooper}

            # Figure out how many lines of length MaxLogLineLength we need to split into:
            local -i NumOfSplits=$(( ${FullLineLength} / ${MaxLogLineLength} ))
                # ^ Integer division, remainder lost. So we need to check next
                #   if there is a remainder which means the number of splits
                #   increments by 1.

            if (( (${FullLineLength} % ${MaxLogLineLength}) > 0 )); then
                (( NumOfSplits++ )) || true
            fi

            local SLALooper
            for (( SLALooper=0; SLALooper<${NumOfSplits}; SLALooper++ ))
                do
                local -i StartIndex=$(( SLALooper * ${MaxLogLineLength} ))
                if (( ${SLALooper} == 0 )); then
                    SplitLinesMessage+=("${LineLooper:${StartIndex}:${MaxLogLineLength}}!!LINEWRAPPED!!")
                        # ^ First split, append !!LINEWRAPPED!! at the end
                fi

                if (( (${SLALooper} > 0) && (${SLALooper} < (NumOfSplits-1)) )); then
                    SplitLinesMessage+=("!!LINEWRAPPED!!${LineLooper:${StartIndex}:${MaxLogLineLength}}!!LINEWRAPPED!!")
                        # ^ Middle split, prepend and append !!LINEWRAPPED!! at both ends
                fi

                if (( ${SLALooper} == (NumOfSplits-1) )); then
                    SplitLinesMessage+=("!!LINEWRAPPED!!${LineLooper:${StartIndex}:${MaxLogLineLength}}")
                        # ^ Last split, prepend !!LINEWRAPPED!! at the start
                fi
                done

        fi
    done

    # Prepend the "    ...." IndentString to all lines except the first.
    # ( This includes wrapped lines already prepended with !!LINEWRAPPED!! ) :
    local -i Counter=0
    for LineLooper in "${SplitLinesMessage[@]}"
        do

        if (( $Counter > 0 )); then
            local TempString="${IndentString}${LineLooper}"
            SplitLinesMessage[$Counter]="${TempString}"
        fi

        (( Counter++ )) || true
            # ^ Need the || true else it crashes
        done

    # Write the array to syslog one line at a time per syslog call:
    for LineLooper in "${SplitLinesMessage[@]}"
        do

        # Used to be this code that did columized formatting, but now I'm
        # keeping it in line with my python3 logging:
        #LoggerText=$(printf "%-8s %-12s %-8s (%s) %s\n" \
        #    "${CallingLineLogLevel}" "[${ScriptName::10}]" \
        #    "[${ProcID}]" "${FUNCNAME[1]:-"UNKNOWN"}" "${LineLooper}")

        # This code is for syslog:
        #LoggerText="<${CallingLineLogLevel}> ($(date +%Y-%m-%d\ %H:%M:%S.%3N) , MN: ${ScriptName} , FN: ${FUNCNAME[1]:-UNKNOWN} , LI: ${BASH_LINENO}):    ${LineLooper}"
        #"${RhinoLib_LoggerCmd}" --id "${ProcID}" --tag "${SyslogProgName}" "${LoggerText}"

        # This code is for systemd / journalctl (but also logs to syslog properly):
        LoggerText="<${CallingLineLogLevel}> (PID: ${ProcID} , MN: ${ScriptName} , FN: ${FUNCNAME[1]:-UNKNOWN} , LI: ${BASH_LINENO}):    ${LineLooper}"
        # ^ Note - in journalctl the PID of the logger program is displayed inside the:     ProgramName[6923]:      rather than the PID of the script.
        #   Therefore I am adding the PID manually as a field inside the (...) section.
        #   For example:    Jul 03 13:17:09 asus303 ProgramName[7155]: <DEBUG> (PID: 7143 , MN: ScriptName
        #                   ^ Timestamp
        #                                           ^ Your script name
        #                                                       ^ PID of logger command
        #                                                                            ^ PID of the script itself (this is the one you want)
        #
        #   Also journalctl can show proper dates, so I removed the date field. Use this to read the journal:
        #     journalctl -fa -o short-iso -t ProgramName

        "${RhinoLib_LoggerCmd}" -t "${SyslogProgName}" "${LoggerText}"
        # ^ Don't need the --id for systemd as it's already added into journalctl incorrectly (it logs the PID of 'logger')
        #   and I send it manually inside the (...). See note above.

        done
}


function ExitScript {
    #   Exit script properly and write log file.
    #
    #   Format: ExitScript [-t|-a] <ERRORLEVEL> <EXITCODE> <REASON>
    #       ERRORLEVEL  - one of: critical, error, warning, info, debug
    #       EXITCODE    - 0 for success, 1-255 for failure
    #       REASON      - plaintext that will be logged at exit time
    #
    #   If you supply the optional:  -t  or:  -a  arg, ExitScript will also send the log line
    #       to stdout (echo) which mimics the linux tee feature.
    #       Note - the echoed line will be printed as supplied without any of the
    #       fancy LogWrite string manipulation.
    #   At the moment:  -t  and:  -a  both ALWAYS output the line to stdout irrespective
    #       the value of LogLevel.
    #
    #   Examples:
    #       ExitScript error 150 "error occurred"           # Log an error and exit
    #       ExitScript -t error 150 "Must be run as root"   # Log + print message and exit

    LogWrite debug "Function ExitScript started"

    local TeeFlag="false"
    local AlwaysTeeFlag="false"
        # ^ Mutually exclusive:  If either flag is set then echo the message too.

    # Special flags can be supplied to ExitScript. Check if any are present:
    if (( $# > 0 )); then
        case "${1}" in
            "-t")   TeeFlag="true"
                        # ^ Set the:  TeeFlag  so that we can print the line to screen too.
                    shift;;
                        # ^ We need this because the rest of ExitScript function assumes that
                        #       it is called with $1, $2, $3 args.
            "-a")   AlwaysTeeFlag="true"
                        # ^ At the moment does the same as:  TeeFlag
                    shift;;
            *)      :;;
        esac
    fi

    local LogLevel="${1:-"error"}"
    shift || :
    local -i ExitCode="${1:-"150"}"
    shift || :
    local ExitReason="${*:-"Error (a more specific exit reason was not supplied)"}"

    if [[ "${TeeFlag}" == "true" || "${AlwaysTeeFlag}" == "true" ]]; then
        echo -e "${ExitReason}"
        # ^ TeeFlag or AlwaysTeeFlag was set - print the log line to screen too.
        #   The:  -e  allows controls in the string such as  \n  to be respected.
    fi

    if (( $ExitCode !=0 )); then
        :   # Required when there is no code in the braces
        #LogWrite error "Exit code not zero, writing message to FailureTrapFile..."
        #WriteErrorFile "Exit code not zero"
            # ^ Ken disabled this on 2021-08-09 because sometimes we intentionally want to exit
            #       non-zero from our script and that's not necessarily an error - therefore
            #       in this case if the developer wants to write a line to the error file - it
            #       must be done explicilty via a call to function:  WriteErrorFile .
    fi

    trap '' EXIT
        # ^ Stop the exit error trap because we really want to exit here!
    LogWrite "${LogLevel}" "Script end, runtime:  $SECONDS  seconds. Exit code:  ${ExitCode} . Exit reason:  ${ExitReason}"
    exit "$ExitCode"
}


function ErrorTrap {
    # Traps errors, writes debugging information and kills self.
    # Note - function ExitScript will not be called!

    LogWrite debug "Function ErrorTrap started"
    WriteErrorFile "Function ErrorTrap called"
    trap '' EXIT
    LogWrite critical "Debugging information: \n Line number: ${1} \n \$BASH_COMMAND: \"${3}\" \n \$LAST_ARGUMENT: \"${4}\" \n failed with exit code: ${2}"
    LogWrite critical "Further debugging info: \n \$BASH_SOURCE: ${5} \n \$FUNCNAME: ${6} \n \$BASH_LINENO: ${7}"
    LogWrite critical "ErrorTrap in RhinoLib PID $$ is going to kill PID ${ProcID} now!"
    kill -9 ${ProcID} &>/dev/null
        # ^ Should not proceed any further
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
    LogWrite error "Wrote error line to ErrorFile: ${FailureTrapFile}"
        # ^ This is log level "error" to indicate that an error message was written -
        #       otherwise it may be skipped in syslog/journal if the script log level is set higher.
    LogWrite debug "Function WriteErrorFile ended"
}


function IsInteger {
    # Requires bash v3 or greater
    # Use: IsInteger "${var}" && echo "int" || echo "not int"
    # If multiple statements then use "if/else" rather than && {} and || {}
    # because it leads to trouble and the function may crash

    if [[ "${1}" =~ ^-?[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}


function IsAlnum {
    # Requires bash v3 or greater
    # Use: IsAlnum "${var}" && echo "pass" || echo "fail"

    if [[ "${1}" =~ ^[0-9a-zA-Z]+$ ]]; then
        return 0
    else
        return 1
    fi
}


function IsAlnum1 {
    # Requires bash v3 or greater
    # Accept also "-" and "_"

    if [[ "${1}" =~ ^[0-9a-zA-Z_-]+$ ]]; then
        return 0
    else
        return 1
    fi
}


function IsAlnum2 {
    # Requires bash v3 or greater
    # Accept also "-" , "_" , " "

    if [[ "${1}" =~ ^[0-9a-zA-Z\ _-]+$ ]]; then
        return 0
    else
        return 1
    fi
}


function CatToFile {
    #   Cats (appends) text to filename after confirming filename ends in \n
    #   Else adds \n before the text
    #       $1 filename to modify. If $1 doesn't exist it is created.
    #       $2 text to add. Remember to quote the text before calling,
    #           not using shift;$* to ease debugging of quoting problems.
    #   This function returns exit code 1 if it can't complete the request successfully.

    if [ -d "$1" ]; then
        LogWrite error "$1 is a directory"
        return 1
    fi

    if [[ -f "$1" ]] && [[ -s "$1" ]]; then   # Regular file non-zero size
        if [[ "$( ${RhinoLib_TailCmd} -c 1 $1 )" != "" ]]; then
            echo >> "$1"
        fi
            # ^ Line doesn't end in:  \n  so append an empty line to the end of the file.
            #   Another way of doing it is:  ${RhinoLib_TailCmd} -c 1 testfile | hexdump | cut -d " " -f 2 | head -n 1
    fi

    if echo "$2" >> "$1"; then
        :
    else
        LogWrite error "Unknown error writing to file $1"
        return 1
    fi
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


function ColorText {
    # Prints text to the screen in color
    # See codes here:   https://en.wikipedia.org/wiki/ANSI_escape_code
    #   and here:  https://misc.flogisoft.com/bash/tip_colors_and_formatting

    # Example:
    #   ColorText StUnderline FgGreen BgBlue "blah"
    #   ColorText StStandard FgRed BgBlack "test\n"
    #       Writes one word in one set of colors followed by another word in a different set of colors.
    #       Then prints a new line.
    #   Note - you explicitly need to supply:  `\n`  for new line.

    # ANSI color codes explained in detail:
    #
    #   Example format:
    #       echo -e "'\033[0;31m'blah'\033[0m'"         (style & color, without background)
    #       echo -e "'\033[0;31;46m'blah'\033[0m'"      (style & color, with background)
    #
    #   The:  `-e`  flag of the `echo` command allows you to use special characters
    #       like:  `\n`  (newline) and:  `\t`  (tab) inside of the input string.
    #
    #   All ansi escape sequences start with the ESCAPE CHARACTER which can be supplied in various formats.
    #   We use octal format, but here are all the options:
    #       Octal:      \033
    #       Hex:        `\x1B`
    #       Decimal     27
    #       Escape char `\e`
    #
    #   `\033`
    #       In our case we're using octal format for the escape char.
    #   `[`
    #       The opening bracket (Control Sequence Introducer) is optional,
    #           but helps separate the command from the escape character.
    #   `;`
    #       Used as a separator between the color codes if supplying more than one value
    #   `<VALUE>`
    #       Style code (in the first position - this defines attributes like bold, blinking, underline, etc)
    #       Text color code (in the second position - defines the color of the text foreground)
    #       Background color code (in the third position - defines the color of the background)
    #   `m`
    #       Need to figure out what the:  `m`  at the end does...
    #
    #   '\033[0m'
    #       This sequence removes all attributes (formatting and colors).
    #       Need to figure out what the:  `m`  at the end does...

    local StyleCode
    local FGCode
    local BGCode

    #LogWrite debug "1 == ${1} , 2 == ${2} , 3 == ${3} , 4 == ${4}"
        # ^ WARNING - logs your text! Use only for debugging this function.

    case "${1}" in
        "StStandard")       StyleCode="0";;
        "StBoldbright")     StyleCode="1";;
        "StDim")            StyleCode="2";;
        "StItalic")         StyleCode="3";;
        "StUnderline")      StyleCode="4";;
        "StBlink")          StyleCode="5";;
        "StReversed")       StyleCode="7";;
        "StInvisible")      StyleCode="8";;
        "StStrikethrough")  StyleCode="9";;
        *)                  StyleCode="0";;
    esac

    case "${2}" in
        "FgBlack")          FGCode="30";;
        "FgRed")            FGCode="31";;
        "FgGreen")          FGCode="32";;
        "FgYellow")         FGCode="33";;
        "FgBlue")           FGCode="34";;
        "FgPurple")         FGCode="35";;
        "FgCyan")           FGCode="36";;
        "FgGray")           FGCode="37";;
        *)                  FGCode="30";;
    esac

    case "${3}" in
        "BgBlack")          BGCode="40";;
        "BgRed")            BGCode="41";;
        "BgGreen")          BGCode="42";;
        "BgYellow")         BGCode="43";;
        "BgBlue")           BGCode="44";;
        "BgPurple")         BGCode="45";;
        "BgCyan")           BGCode="46";;
        "BgGray")           BGCode="47";;
        *)                  BGCode="40";;
    esac

    local EndColorString="\033[0m"
    local ColorFormatString="\033[${StyleCode};${FGCode};${BGCode}m"
    LogWrite debug "StyleCode == ${StyleCode} , FGCode == ${FGCode} , BGCode == ${BGCode} , ColorFormatString == ${ColorFormatString}"
    printf "${ColorFormatString}${4}${EndColorString}"
}


function PressAnyKey {
    read -n 1 -rsp "Press any key to continue..." || :
}


function DoYouWantToProceed {
    # Simple y/n to proceed. Accepts anything but only returns
    # 0 if user responds with 'y' or 'Y'
    # Usage: DoYouWantToProceed && echo "user said yes"

    local Ans
    read -p  "--> Do you want to proceed (y/n) ?  " Ans || :
    if [[ ( "${Ans}" == "y" ) || ( "${Ans}" == "Y" ) ]]; then
        return 0
    else
        return 1
    fi
}


function BackupFile {

    #   NOTE - This function is here for backwards compatability. New code should
    #       use function:  BackupFileV2  which is more advanced and future proof.
    #
    #   $1 = Source file - mandatory arg
    #   $2 = Dest dir - mandatory arg
    #
    #   Backs up source:  $1  to destination:  DIRECTORY $2
    #       and creates Dest Dir if it does not exist.
    #   Returns exit code == 0 if all successful else exit code == 1
    #   This function is designed to backup a single source file, do not supply wildcards!
    #
    #   Usage: BackupFile "/usr/local/bin/test.sh" "/tmp/" || LogWrite warning "backup failed"
    #       Always include the || or && at the end of the backup command to catch events that fail
    #       otherwise a failed backup could crash your script as a failed command.

    LogWrite debug "BackupFile called with args:  $*"
    if (( $# != 2 )); then
        LogWrite warning "Incorrect number of arguments. Expecting 2"
        return 1
    fi

    if [[ -f "${1}" ]]; then
        :
    else
        LogWrite warning "Cannot find source file:  ${1}"
        return 1
    fi

    if mkdir --parents "${2}"; then
        :
    else
        LogWrite warning "Error creating directory:  ${2}"
        return 1
    fi

    local FileName="$( /bin/basename "${1}" )"
    local TimeStamp="$(date +%Y-%m-%d_%H%M%S)"
    local TargetName="${2%%/}/${FileName}_${TimeStamp}"
    LogWrite debug "Source file == ${1} , Target dir == ${2} , FileName (source file basename) == ${FileName} , TimeStamp == ${TimeStamp} , TargetName == ${TargetName}"

    #   Note - $2 might come with a trailing slash and since we specify it manually
    #       in the copy command, we need to remove it from $2 with %%/   .
    #   Note - I'm using:  "/bin/cp --archive"  because I want to preserve the attributes -
    #       especially the selinux context.
    if /bin/cp --archive "${1}" "${TargetName}"; then
        LogWrite info "Successfully copied:  ${1}  to:  ${TargetName}"
        return 0
    else
        LogWrite warning "Error copying:  ${1}  to:  ${TargetName}"
        return 1
    fi
}


function BackupFileV2 {

    #   Format:  BackupFileV2 -s <sourcefile> -d <destdir> [-t "tag with space"]
    #       -s <source_file> / --source=<source_file>
    #           Source file to backup - mandatory field
    #       -d <dest_dir> / --dir=<dest_dir>
    #           Destination dir to place the backup file into - mandatory field
    #       -t <tag_text> / --tag=<tag_text>
    #           Tag text to append to end of file name - optional field
    #
    #   Note - if you're supplying variables with spaces - put them in double quotes.
    #       Try to use tag_text without spaces (underscore and minus are ok)
    #       to make file management easier for you.
    #
    #   Backs up source:  <sourcefile>  to destination dir:  <destdir>
    #       and creates destdir if it does not exist.
    #   Returns exit code == 0 if all successful else exit code == 1
    #   This function is designed to backup a single source file, do not supply wildcards!
    #
    #   Usage:
    #       BackupFileV2 -s sourcefile -d destdir -t "tag with space" || LogWrite warning "backup failed"
    #       BackupFileV2 -s "source file with spaces" -d destdir || LogWrite warning "backup failed"
    #       BackupFileV2 -s sourcefile -d destdir -t filename_without_spaces || LogWrite warning "backup failed"
    #
    #       Note - Always include the || or && at the end of the backup command to catch events that fail
    #           otherwise a failed backup could crash your script as a failed command.
    #
    #       Resulting backup file looks like:  OriginalFilename_2021-12-03_083245_TagText

    LogWrite debug "Function BackupFileV2 called with args:  $*"

    local RhinoLibShortOptions="s:d:t:"
    local RhinoLibLongOptions="dir:source:tag:"
    local SourceFilename=""
    local DestDir=""
    local TagText=""

    if CheckIfEnhancedGetopt; then
        LogWrite debug "Enhanced getopt command found - script will continue..."
    else
        ExitScript error 150 "This command requires the enhanced getopt command and will not continue without it"
    fi

    local RhinoLibParsedArgs="$( "${RhinoLib_GetoptCmd}" --alternative --name=${ScriptName} \
        --options "${RhinoLibShortOptions}" \
        --longoptions "${RhinoLibLongOptions}" \
        -- "$@" )" || \
            {
            ExitScript error 150 "Invalid arg supplied to function BackupFileV2 . Exiting"
            }

    LogWrite debug "RhinoLibParsedArgs (from calling getopt) == ${RhinoLibParsedArgs}"
    eval set -- ${RhinoLibParsedArgs}
    LogWrite debug "After eval set, args are:  ${*}"

    while :
        do
        case "${1}" in
            -s | --source)
                SourceFilename="${2}"
                shift 2
                LogWrite debug "Source arg supplied: SourceFilename == ${SourceFilename}";;

            -d | --dir)
                DestDir="${2}"
                shift 2
                LogWrite debug "Dir arg supplied: DestDir == ${DestDir}";;

            -t | --tag)
                TagText="${2}"
                shift 2
                LogWrite debug "Tag arg supplied: TagText == ${TagText}";;

            --)
                LogWrite debug "End of arguments reached"
                shift
                break;;

            *)
                ExitScript error 150 "Unexpected option:  ${1}";;

        esac
        done

    if [[ -f "${SourceFilename}" ]]; then
        :
    else
        LogWrite warning "Cannot find source file:  ${SourceFilename}"
        return 1
    fi

    if mkdir --parents "${DestDir}"; then
        :
    else
        LogWrite warning "Error creating directory:  ${DestDir}"
        return 1
    fi

    local BaseFileName="$( /bin/basename "${SourceFilename}" )"
    local TimeStamp="$(date +%Y-%m-%d_%H%M%S)"
    local TargetName="${DestDir%%/}/${BaseFileName}_${TimeStamp}"
    # ^ Note - $DestDir might come with a trailing slash and since we specify it manually
    #       in the copy command, we need to remove it from $DestDir with %%/   .

    if [[ "${TagText}" ]]; then
        TargetName="${TargetName}_${TagText}"
    fi

    LogWrite debug "Source file == \"${SourceFilename}\" , Target dir == \"${DestDir}\" , BaseFileName (source file basename) == \"${BaseFileName}\" , TimeStamp == ${TimeStamp} , TargetName == \"${TargetName}\""

    #   Note - I'm using:  "/bin/cp --archive"  because I want to preserve the attributes -
    #       especially the selinux context :
    if /bin/cp --archive "${SourceFilename}" "${TargetName}"; then
        LogWrite info "Successfully copied:  ${SourceFilename}  to:  ${TargetName}"
        return 0
    else
        LogWrite warning "Error copying:  ${SourceFilename}  to:  ${TargetName}"
        return 1
    fi
}


function LogNftRules {
    # Usage:    LogNftRules "After making change x y z"
    #   Supply some identifying text within the "..." so that you can find it in the logs

    LogWrite info "NFT OUTPUT LOGGING STARTS BELOW FOR: ${1}"
    local NftRules="$(sudo /usr/sbin/nft -nn --handle list ruleset 2>&1 || echo "Error running:  sudo /usr/sbin/nft . Do you have sudo permissions?" )"
    LogWrite info "${NftRules}"
    LogWrite info "NFT OUTPUT LOGGING ENDED ABOVE FOR: ${1}"
}


function CheckIfSelinuxPresent {

    #   This function checks if selinux is present (permissive or enabled)
    #       and returns 0 if 'yes' or 1 if 'no'.
    #   The primary use case here is to make a decision whether
    #       to set selinux permissions on files if selinux is present - the deciding
    #       factor is whether there is selinux or not, and not whether selinux is
    #       disabled/permissive vs enforcing.
    #   If selinux is disabled or the getenforce command doesn't exist or returns
    #       some form of error - we say that selinux is not present.
    #
    #   Usage: CheckIfSelinuxPresent && echo "present" || echo "absent"

    local Result="$( /sbin/getenforce 2>&1 || : )"
    Result="${Result,,}"    # Lowercase it
    LogWrite debug "Checking:  /sbin/getenforce  -->  Result == ${Result}"
    if [[ "${Result}" =~ (permissive|enforcing) ]]; then
        return 0
    else
        return 1
    fi
}


function CheckIfEnhancedGetopt {

    #   Enhanced getopt has advantages over the builtin getops and the older getopt command.

    local Result="$( "${RhinoLib_GetoptCmd}" -T &>/dev/null && echo $? || echo $? )"
    if (( ${Result} == 4 )); then
        LogWrite debug "Result == ${Result}  -> Enhanced getopt command found"
        return 0
    else
        LogWrite warning "Result == ${Result}  -> Enhanced getopt command not found or error occurred"
        return 1
    fi
}


function DuplicateScriptAction {

    #   Check if duplicate scripts exist with the same file name
    #       and exit if some are found.
    #       This is to ensure that only n copies of your script are running.
    #
    #   $1 == Max number of concurrent scripts to accept before exiting.
    #           Should be any value >= 1
    #   $2 == Action to take if this value is exceeded. Supported actions:
    #           teeexit == exit the script with a warning log message + terminal message.
    #           quietexit == exit the script with only a log message.
    #   $3 == Information collection to assist debugging. Supported actions:
    #           none == don't help at all (usually for scripts that constantly run duplicates
    #               and you know that dupes happen all the time).
    #           minimallog == use LogWrite to log the related ps lines.
    #           psfile == minimallog + write full ps output to /tmp/ps-auxfww_<timestamp>
    #           debuglog == LogWrite full ps output (basically psfile content written to log instead)
    #
    #   Example:  DuplicateScriptAction 3 teeexit psfile
    #               - Allow maximum 3 concurrent scripts
    #               - Echo message + log message + exit if your script is number 4.
    #               - Before exiting write a full ps output to file + short log.

    LogWrite debug "Function DuplicateScriptAction started"

    local ScriptFileName="${0##*/}"
    local MaxAllowed=$1
    local ActionToTake=$2
    local DebugAction=$3

    local -a PidofProcArray=( $( /usr/sbin/pidof -x "${ScriptFileName}" -o %PPID || : ) )
    local -a PgrepProcArray=( $( /usr/bin/pgrep -f -d " " "${ScriptFileName}" ) )
        # ^ This array is used for debugging info only + script development.
        #       Use it for your own information and to assist you with further data - you can
        #       compare its info to:  PidofProcArray  but we are not using its
        #       contents for any kind of decision making because it includes the PPID
        #       if the text contained in:  ${ScriptFileName}  appears in the parent's args.
        #       If this happens - the count of:  PgrepProcArray  will be higher than that
        #       of:  PidofProcArray .
        #       You'd normally get this condition when your script is run by a cron job
        #       or some other caller in which case you'll get more PIDs than actual running script copies.
        #       If you run your script from the command line you won't see this happen.

    LogWrite debug "Various args: MaxAllowed == ${MaxAllowed} , ActionToTake == ${ActionToTake} , DebugAction == ${DebugAction} . ScriptFileName == ${ScriptFileName} , PidofProcArray == ${PidofProcArray[*]} , PidofProcArray count == ${#PidofProcArray[*]}"
    LogWrite debug "Helpful vars (for comparison only - not used by script): PgrepProcArray == ${PgrepProcArray[*]} , PgrepProcArray count == ${#PgrepProcArray[*]}"

    if (( ${#PidofProcArray[*]} > ${MaxAllowed} )); then

        # Information collection:

        LogWrite warning "Duplicate script action triggered. Here is some helpful information before exiting:"

        if [[ "${DebugAction}" == "none" ]]; then
            LogWrite info "DebugAction == ${DebugAction} . No information will be collected."
        fi

        if [[ "${DebugAction}" == "minimallog" ]]; then
            LogWrite info "Related lines from:  ps auxww  follow:\n$( /usr/bin/ps auxww | /usr/bin/grep "${ScriptFileName}" || : )"
        fi

        if [[ "${DebugAction}" == "psfile" ]]; then
            /usr/bin/ps auxfww > /tmp/ps-auxfww_"$(date +%Y-%m-%d_%H%M%S)"
            LogWrite info "Related lines from:  ps auxww  follow:\n$( /usr/bin/ps auxww | /usr/bin/grep "${ScriptFileName}" || : )"
            LogWrite info "Full:  ps auxfww  can be found in:  /tmp/ps-auxfww_*"
        fi

        if [[ "${DebugAction}" == "debuglog" ]]; then
            LogWrite info "Full output of:  ps auxfww  follows:\n$( /usr/bin/ps auxfww || : )"
        fi

        # Exit strategies:

        if [[ "${ActionToTake}" == "quietexit" ]]; then
            ExitScript warning 150 "Too many concurrent scripts named:  ${ScriptFileName}  found . Max concurrent allowed == ${MaxAllowed} . Concurrent PIDs found: ${PidofProcArray[*]} , Concurrent PIDs count == ${#PidofProcArray[*]} . Exiting"
        fi

        if [[ "${ActionToTake}" == "teeexit" ]]; then
            ExitScript -t warning 150 "Too many concurrent scripts named:  ${ScriptFileName}  found . Max concurrent allowed == ${MaxAllowed} . Concurrent PIDs found: ${PidofProcArray[*]} , Concurrent PIDs count == ${#PidofProcArray[*]} . Exiting"
        fi

    else
        LogWrite debug "Function DuplicateScriptAction ended. Not enough duplicates found to trigger script exit. Returning control to the script..."

    fi
}


