package require tclreadline
package require platform

namespace eval tclreadline {
	# Prompt line prefix
	proc prompt1 {} {
		upvar 0 ::cf::[set ::curcfg]::eid eid
		if {[info exists eid]} {
			return "imunes@$eid> "
		} else {
			return "imunes@[info hostname]> "
		}
	}
}

# Read available commands for autocompletion
set procedures ""
set filep [open "shellcommands.txt" r]
set commands [split [read $filep] "\n"]
close $filep
foreach command $commands {
	set command [string trim $command]
	if {[string length $command] > 0 } {
			lappend procedures $command 
	}
}
set procedures [lsort $procedures]

#****f* tcl_shell.tcl/customcpl
# NAME
#   customcpl -- custom completer
# SYNOPSIS
#   customcpl $word $start $end $line
# FUNCTION
#   Returns longest match and matched procedures that can be
#	completed from input string
# INPUTS
#   * word -- string that needs to be autocompleted
#	* start -- start position of word in line
#	* end -- end position of word in line
#	* line -- line text
# RESULT
#	* Completed longest match of matched procedures and 
#	  list of matched procedures
#****
proc customcpl {word start end line} {
	global procedures
	set matched_procedures ""
	
	##if {$word == "" && $line == "attachToRunningExperiment "} {
		##puts [getResumableExperiments]
	##}
	
	foreach procedure $procedures {
		if {[string first $word $procedure] == 0}  {
			set matched_procedures "$matched_procedures $procedure"
		}
	}
	set matched_procedures [string trim $matched_procedures]
	#Find longest match
	if {[string length $matched_procedures]> 0} {
		while 1 {
			set longest_match ""
			for {set i 0} {$i<[string length [lindex $matched_procedures 0]]} {incr i} {
				set current_match "$longest_match[string index [lindex $matched_procedures 0] $i]"
				foreach procedure $matched_procedures {
					if {[string match $current_match* $procedure] == 0} {
						return "$longest_match $matched_procedures"
					}
				}
				set longest_match "$current_match"
			}
			break
		}
		return "$longest_match $matched_procedures"
	} else {
	return ""
	}
}

source "shell_procedures.tcl"
::tclreadline::readline builtincompleter 0
::tclreadline::readline customcompleter customcpl

::tclreadline::Loop 
