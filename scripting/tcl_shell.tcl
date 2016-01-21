package require tclreadline
package require platform

namespace eval tclreadline {
    proc prompt1 {} {
	return "imunes@[info hostname]> "
    }
}

source "shell_procedures.tcl"

::tclreadline::Loop 
