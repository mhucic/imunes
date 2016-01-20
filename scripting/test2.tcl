package require tclreadline
package require platform

namespace eval tclreadline {
    proc prompt1 {} {
	return "imunes@[info hostname]> "
    }
}

source "bla2.tcl"

::tclreadline::Loop 
