###
# Initialization of variables
###

set isOSfreebsd false
set isOSlinux false
set isOSwin false

package require ip

set LIBDIR ""
set ROOTDIR "."

if { $ROOTDIR == "." } {
    set BINDIR ""
} else {
    set BINDIR "bin"
}


set os [platform::identify]
switch -glob -nocase $os {
    "*freebsd*" {
        set isOSfreebsd true
            source "../runtime/freebsd.tcl"
    }
    "*linux*" {
        set isOSlinux true
            source "../runtime/freebsd.tcl"
            source "../runtime/linux.tcl"
    }
    "*win*" {
        set isOSwin true
    }
}

foreach f [list cfgparse exec services] {
    source "../runtime/$f.tcl"
}

foreach f [list mac nodecfg linkcfg ipv4 ipv6 ipsec packgencfg filtercfg stpswitchcfg nat64cfg] {
    source "../config/$f.tcl"
}

foreach f [list editor] {
    source "../gui/$f.tcl"
}

source  "../gui/canvas.tcl"
# Set default L2 node list
set l2nodes "hub lanswitch click_l2 rj45 stpswitch filter packgen ext"
# Set default L3 node list
set l3nodes "genericrouter quagga xorp static click_l3 host pc nat64"

#Node list for displaying to user
#added router to l3nodes and without genericrouter
set l3nodes_a "router quagga xorp static click_l3 host pc nat64"
set l2nodes_a "hub lanswitch click_l2 rj45 stpswitch filter packgen ext"
# Set default supported router models
set supp_router_models "xorp quagga static"

if { $isOSlinux } {
    # Limit default nodes on linux
    set l2nodes "lanswitch rj45 ext"
    set l3nodes "genericrouter quagga static pc host nat64"
    #remove genericrouter, nodes with "_a" appendix are for displaying to user
    #added router to l3nodes
    set l3nodes_a "router quagga static pc host nat64"
    set l2nodes_a "lanswitch rj45 ext"
    set supp_router_models "quagga static"
}

# L2 nodes
foreach file $l2nodes {
    source "../nodes/$file.tcl"
}
# L3 nodes
foreach file $l3nodes {
    source "../nodes/$file.tcl"
}

set runtimeDir "/var/run/imunes"
set execMode "batch"
set debug 0

set cfg_list {}
set curcfg "c0"
namespace eval cf::[set curcfg] {}
set cf::[set curcfg]::node_list {}
set cf::[set curcfg]::link_list {} 
set cf::[set curcfg]::annotation_list {} 
set cf::[set curcfg]::image_list {} 
set cf::[set curcfg]::canvas_list {} 
set cf::[set curcfg]::IPv4UsedList ""
set cf::[set curcfg]::IPv6UsedList ""
set cf::[set curcfg]::MACUsedList ""
set cf::[set curcfg]::etchosts ""
set cf::[set curcfg]::zoom "1.0"

foreach x "showIfNames showIfIPaddrs showIfIPv6addrs showNodeLabels showLinkLabels showBkgImage showAnnotations hostsAutoAssign showGrid" {
    set $x 1
}

set iconSize normal
set defEthBandwidth 0
set IPv4autoAssign 1
set IPv6autoAssign 1
set editor_only 0

#Auto saving of configuration files when creating a new node
set autoSaveOnChange 1

# bases for naming new nodes
array set nodeNamingBase {
    pc pc
    click_l2 cswitch
    click_l3 crouter
    ext ext
    filter filter
    router router
    host host
    hub hub
    lanswitch switch
    nat64 nat64-
    packgen packgen
    stpswitch stpswitch
}


# Default for router
set rdconfig ""
set model quagga
set router_model $model
set routerDefaultsModel $model
set def_router_model quagga


#TODOchangeME
set currentFileBatch remoteBla

lappend cfg_list $curcfg
namespace eval ::cf::[set curcfg] {}


#****f* shell_procedures.tcl/createContainer
# NAME
#   createContainer
# SYNOPSIS
#   createContainer
# FUNCTION
#   Procedure creates new container for experiment
#****
proc createContainer {} {
	upvar 0 ::cf::[set ::curcfg]::eid eid
    global runtimeDir isOSfreebsd
    set eid_base i[format %04x [expr {[pid] + [expr { round( rand()*10000 ) }]}]]
    #if {[info exists eid]} {
		#puts "Experiment allready exist. Do you want to create"
	#}
    set eid ${eid_base}[string range $::curcfg 1 end]
    loadKernelModules
    prepareVirtualFS
    prepareDevfs
    createExperimentContainer
    newCanvas c0

    file mkdir "$runtimeDir/$eid"
    if {$isOSfreebsd} {
        upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
        set ngmapFile "$runtimeDir/$eid/ngnodemap"
        writeDataToFile $runtimeDir/$eid/timestamp [clock format [clock seconds]]
        array set ngnodemap ""
        dumpNgnodesToFile $runtimeDir/$eid/ngnodemap 
    }

    puts "Experiment container created with ID: $eid"
}

#****f* shell_procedures.tcl/createNode
# NAME
#   createNode
# SYNOPSIS
#   createNode $type
# FUNCTION
#   Creates new node of given type
# INPUTS
#   * type -- node type
# RESULT
#   * node -- node id
#****
proc createNode { type } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
    if {![info exists eid]} {
        puts "Container for experiment doesn't exist. Please create one using:"
        puts "> createContainer"
        return
    }
    global l3nodes l2nodes isOSlinux isOSfreebsd supp_router_models l3nodes_a l2nodes_a 
    global router_model routerDefaultsModel model
    if {[lsearch -exact $l2nodes_a $type]<0 && [lsearch -exact $l3nodes_a $type]<0} {
        puts "Node not created. Wrong type of node. Use one of following: "
        puts $l2nodes_a
        puts $l3nodes_a
        return
    } elseif {$type == "pseudo"} {
        puts "Can't create \"pseudo\" node"
        return
    } elseif {$type == "rj45"} {
        puts "External interface requires appointed physical interface for bridging."
        puts "Please choose number in front of physical interface:"
        set i 0
        set ifcs [getExtIfcs]
        foreach ifc $ifcs {
            puts "$i) $ifc"
            incr i
        }
        set input [gets stdin]
        if {$input>-1 && $input<$i} {
            set name [lindex $ifcs $input]
            if { $isOSlinux && [string length "$eid-$name.0"] > 15 } {
                puts $eid-$name.0
                puts "Bridge name too long, node not created, please choose another."
                return
            } else {
				set node [newNode $type]
                setNodeName $node $name
            }
        } else {
            puts "Wrong choice, node not created, please try again."
            #removeNode $node
            return
        }

    } elseif {$type == "router"} {
        puts "Choose router model:"
        set i 0
        foreach rtype $supp_router_models {
            puts "$i) $rtype"
            incr i
        }
        puts "Enter number in front of model:"
        set input [gets stdin]
        if {$input>-1 && $input<$i} {
			set node [newNode "router"]
			set model [lindex $supp_router_models $input]
			set router_model [lindex $supp_router_models $input]
			set routerDefaultsModel [lindex $supp_router_models $input]
            setNodeModel $node [lindex $supp_router_models $input]
        } else {
            puts "Wrong choice, node not created, please try again."
            #removeNode $node
            return
        }
        setNodeProtocolRip $node 1
	} elseif {[lsearch -exact $supp_router_models $type]>=0} {
		set node [newNode "router"]
		set model $type
		set router_model $type
		set routerDefaultsModel $type
		setNodeModel $node $type
		setNodeProtocolRip $node 1
	} else {
		set node [newNode $type]
	}

    instNode $node
    if {$isOSlinux} {
		startNode $node
	} elseif {$isOSfreebsd} {
		if {$type != "rj45" && [lsearch -exact $l3nodes $type]>=0} {
			runConfOnNode $node
		}
	}

    setNodeCanvas $node c0
    set coords [getRandomCoords]
    setNodeCoords $node $coords
    setNodeLabelCoords $node "[lindex $coords 0] [expr {[lindex $coords 1] +30}]" 

    global autoSaveOnChange
    if {$autoSaveOnChange} {
        saveConfiguration
    }

    puts "Node $node ([getNodeName $node]) created"
}

#****f* shell_procedures.tcl/instNode
# NAME
#   instNode
# SYNOPSIS
#   instNode $node
# FUNCTION
#   Procedure instantiate creates a new virtual node
# INPUTS
#   * node -- node id
#****
proc instNode { node } {
    upvar 0 ::cf::[set ::curcfg]::eid eid

    pipesCreate
    [typemodel $node].instantiate $eid $node
    pipesClose
}

#****f* shell_procedures.tcl/startNode
# NAME
#   startNode
# SYNOPSIS
#   startNode $node
# FUNCTION
#   Procedure starts a new node
# INPUTS
#   * node -- node id
#****
proc startNode { node } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
    if {[info procs [typemodel $node].start] != ""} {
        [typemodel $node].start $eid $node
    }
}

#****f* shell_procedures.tcl/stopNode
# NAME
#   stopNode
# SYNOPSIS
#   stopNode $node
# FUNCTION
#   Procedure stops existing node
# INPUTS
#   * node -- node id
#****
proc stopNode { node } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
    if {[nodeType $node] == "pseudo"} {
        puts "Can't stop \"pseudo\" node"
        return
    }
    if {[info procs [typemodel $node].shutdown] != ""} {
        [typemodel $node].shutdown $eid $node
    }
}

#****f* shell_procedures.tcl/createLink
# NAME
#   createLink -- create link between nodes
# SYNOPSIS
#   createLink $node1 $ifc1 $node2 $ifc2 
# FUNCTION
#   Procedure creates a new link between nodes node1 and node2
# INPUTS
#   * node1 -- node id
#   * ifc1  -- interface on node1
#   * node2 -- node id
#   * ifc2  -- interface on node2
# RESULTS
#   * link  -- link id
#****
proc createLink { node1 ifc1 node2 ifc2 } {
    upvar 0 ::cf::[set ::curcfg]::node_list node_list
    upvar 0 ::cf::[set ::curcfg]::eid eid
    global isOSfreebsd isOSlinux runtimeDir

	if {$isOSlinux} {
		puts "Using createLinkNewIfcs on Linux"
        createLinkNewIfcs $node1 $node2
		return
		#set link [newLink $node1 $node2]
	}
    if {[lsearch -exact $node_list $node1]<0} {
        puts "Node $node1 doesn't exist. Choose another node."
        return
    }
    if {[lsearch -exact $node_list $node2]<0} {
        puts "Node $node2 doesn't exist. Choose another node."
        return
    }
    if {[lsearch -exact [ifcList $node1] $ifc1]<0 } {
        puts "Interface $ifc1 on $node1 doesn't exist. Please choose another or create one."
        return
    } 
    if {[lsearch -exact [ifcList $node2] $ifc2]<0} {
        puts "Interface $ifc2 on $node2 doesn't exist. Please choose another or create one."
        return
    }
	if {[nodeType $node1] == "pseudo" || [nodeType $node2] == "pseudo"}    {
        puts "Can't create link to \"pseudo nodes\""
        return
    }
    #Check if interface is used by another link
    if {[peerByIfc $node1 $ifc1]!=$node1} {
        puts "Interface $ifc1 on $node1 is used and connected to node [peerByIfc $node1 $ifc1]." 
        puts "Please choose another interface or create one."
        return
    }
    if {[peerByIfc $node2 $ifc2]!=$node2} {
        puts "Interface $ifc2 on $node2 is used and connected to node [peerByIfc $node2 $ifc2]." 
        puts "Please choose another interface or create one."
        return
    }
    
    
	upvar 0 ::cf::[set ::curcfg]::link_list link_list
	upvar 0 ::cf::[set ::curcfg]::$node1 $node1
	upvar 0 ::cf::[set ::curcfg]::$node2 $node2
	global defEthBandwidth defSerBandwidth defSerDelay

	foreach node "$node1 $node2" {
		if {[info procs [nodeType $node].maxLinks] != "" } {
			if { [ numOfLinks $node ] == [[nodeType $node].maxLinks] } {
				puts "IMUNES warning"
				puts "Warning: Maximum links connected to the node $node"
				#return
				#TODO rj 45 ima samo jednog, dodati +1, jer mi već imamo interface

			}
		}
	}
	if {$isOSfreebsd} {	
		set link [newObjectId link]
		upvar 0 ::cf::[set ::curcfg]::$link $link
		set $link {}

		lappend $link "nodes {$node1 $node2}"
		if { ([nodeType $node1] == "lanswitch" || \
			[nodeType $node2] == "lanswitch" || \
			[string first eth "$ifc1 $ifc2"] != -1) && \
			[nodeType $node1] != "rj45" && \
			[nodeType $node2] != "rj45" } {
			lappend $link "bandwidth $defEthBandwidth"
		} elseif { [string first ser "$ifc1 $ifc2"] != -1 } {
			lappend $link "bandwidth $defSerBandwidth"
			lappend $link "delay $defSerDelay"
		}
		
		lappend link_list $link

		set i [lsearch [set $node1] "interface-peer {$ifc1 $node1}"]
		set $node1 [lreplace [set $node1] $i $i "interface-peer {$ifc1 $node2}"]
		set i [lsearch [set $node2] "interface-peer {$ifc2 $node2}"]
		set $node2 [lreplace [set $node2] $i $i "interface-peer {$ifc2 $node1}"]
		
			if {[isNodeRouter $node1]} {
				if {[info procs [nodeType $node1].confNewIfc] != ""} {
					[nodeType $node1].confNewIfc $node1 $ifc1
				}
				if {[info procs [nodeType $node2].confNewIfc] != ""} {
					[nodeType $node2].confNewIfc $node2 $ifc2
				}
			} else {
				if {[info procs [nodeType $node2].confNewIfc] != ""} {
					[nodeType $node2].confNewIfc $node2 $ifc2
				}
				if {[info procs [nodeType $node1].confNewIfc] != ""} {
					[nodeType $node1].confNewIfc $node1 $ifc1
				}
			}
    } 
	
    #

    createLinkBetween $node1 $node2 $ifc1 $ifc2
    configureLinkBetween $node1 $node2 $ifc1 $ifc2 $link

    #start node to get IP addresses
    foreach node "$node1 $node2" {
        ##stopNode $node
        startNode $node
    }

    global autoSaveOnChange
    if {$autoSaveOnChange} {
        saveConfiguration
    }

    puts "Link $link ([lindex [linkPeers $link] 0] - [lindex [linkPeers $link] 1]) created"
}

#****f* shell_procedures.tcl/createNodeIfc
# NAME
#   createNodeIfc -- create interface on node
# SYNOPSIS
#   createNodeIfc $node
# FUNCTION
#   Procedure creates a new interface on node
# INPUTS
#   * node -- node id
# RESULTS
#   * $ifname -- interface name
#****
proc createNodeIfc { node } {
	upvar 0 ::cf::[set ::curcfg]::eid eid
    upvar 0 ::cf::[set ::curcfg]::$node $node
    upvar 0 ::cf::[set ::curcfg]::node_list node_list

    global isOSfreebsd runtimeDir isOSlinux
    
    #Currently creating node interfaces on Linux is not supported.
    #TODO mapping procedures of vethpairs
    if {$isOSlinux} {
        puts "Currently creating node interfaces on Linux is not supported."
        puts "To create link with interfaces, use createLinkWithIfcs"
        return
    }
    
    if {[lsearch -exact $node_list $node]<0} {
        puts "Node $node doesn't exist. Choose another node."
        return
    }   
        
    if {[nodeType $node] == "pseudo"} {
        puts "Can't create interface on \"pseudo node\""
		return
    }
    
    if {[nodeType $node] != "rj45"} {
        set type [[nodeType $node].ifcName $node $node]
		#TODO maximal number of interfaces on node

		set ifname [newIfc $type $node]
    } else {
		set ifname 0
	}

	#When interface is free, it is connected to itself
	lappend $node "interface-peer {$ifname $node}"
	if {[isNodeRouter $node] || [[nodeType $node].virtlayer] == "VIMAGE"} {
		
		autoMACaddr $node $ifname

		if {$isOSfreebsd} {
			pipesCreate
			createNodePhysIfc $node $ifname
			pipesClose
			dumpNgnodesToFile $runtimeDir/$eid/ngnodemap 
		}
	}

	#if {[info procs [nodeType $node].confNewIfc] != ""} {
	#[nodeType $node].confNewIfc $node $ifname
	#}

	#stopNode $node
	#startNode $node
    global autoSaveOnChange
        if {$autoSaveOnChange} {
            saveConfiguration
        }
    puts "Interface $ifname created on node $node"
    return $ifname
}

#****f* shell_procedures.tcl/createLinkNewIfcs
# NAME
#   createLinkNewIfs -- create link between nodes and new network interfaces
# SYNOPSIS
#   createLink $node1 $node2
# FUNCTION
#   Procedure creates a new link between nodes node1 and node2 and new 
#    interface on each node
# INPUTS
#   * node1 -- node id
#   * node2 -- node id
#****
proc createLinkNewIfcs { node1 node2 } {
    upvar 0 ::cf::[set ::curcfg]::node_list node_list
	upvar 0 ::cf::[set ::curcfg]::eid eid


	if {[nodeType $node1] == "pseudo" || [nodeType $node2] == "pseudo"}    {
		puts "Can't create link to \"pseudo nodes\""
			return
	}

    if {[lsearch -exact $node_list $node1]<0} {
        puts "Node $node1 doesn't exist. Choose another node"
            return
    } elseif {[lsearch -exact $node_list $node2]<0} {
        puts "Node $node2 doesn't exist. Choose another node"
            return
    }

	global isOSfreebsd isOSlinux runtimeDir
	if {$isOSfreebsd} {
		set ifc1 [createNodeIfc $node1]
		set ifc2 [createNodeIfc $node2]
		createLink $node1 $ifc1 $node2 $ifc2
	}
    if {$isOSlinux} {
		set link [newLink $node1 $node2]
		startLink $link
		foreach node "$node1 $node2" {
			stopNode $node
			startNode $node
		}
        puts "Link $link ([lindex [linkPeers $link] 0] - [lindex [linkPeers $link] 1]) created"
	}
    global autoSaveOnChange
        if {$autoSaveOnChange} {
            saveConfiguration
        }
}

#****f* shell_procedures.tcl/startLink
# NAME
#   startLink
# SYNOPSIS
#   startLink $link
# FUNCTION
#   Procedure configures and starts a new link
# INPUTS
#   * link -- link id
#****
proc startLink { link } {
    set node_id1 [lindex [linkPeers $link] 0]
	set node_id2 [lindex [linkPeers $link] 1]
	set ifname1 [ifcByPeer $node_id1 $node_id2]
	set ifname2 [ifcByPeer $node_id2 $node_id1]

	createLinkBetween $node_id1 $node_id2 $ifname1 $ifname2
	configureLinkBetween $node_id1 $node_id2 $ifname1 $ifname2 $link
}

#****f* shell_procedures.tcl/deleteNode
# NAME
#   deleteNode
# SYNOPSIS
#   deleteNode $node
# FUNCTION
#   Procedure deletes existing node and links to this node
# INPUTS
#   * node -- node id
#****
proc deleteNode { node } {
    upvar 0 ::cf::[set ::curcfg]::node_list node_list
    upvar 0 ::cf::[set ::curcfg]::eid eid
    upvar 0 ::cf::[set ::curcfg]::$node $node
    global nodeNamingBase isOSfreebsd

    if {[lsearch -exact $node_list $node]<0} {
        puts "Node $node1 doesn't exist. Choose another node"
        return
    }
    if {[nodeType $node] == "pseudo"}    {
        puts "Can't delete \"pseudo\" node"
        return
        }

    if { [getCustomIcon $node] != "" } {
        removeImageReference [getCustomIcon $node] $node
    }
    #problem ako je interface sam jer očekuje da ako ima interface da pokazuje na drugi čvor
    foreach ifc [ifcList $node] {
        set peer [peerByIfc $node $ifc]
        if {$peer != $node} {
            set link [linkByPeers $node $peer]
            deleteLink $link
        }
		if {$isOSfreebsd} {
			deleteNodeIfc $node $ifc
		}
    }

    #removeNode $node

    stopNode $node
    set i [lsearch -exact $node_list $node]
    set node_list [lreplace $node_list $i $i]

    set node_type [nodeType $node]
    if { $node_type in [array names nodeNamingBase] } {
        recalculateNumType $node_type $nodeNamingBase($node_type)
    }

    global autoSaveOnChange
    if {$autoSaveOnChange} {
        saveConfiguration
    }
    pipesCreate
    [typemodel $node].destroy $eid $node
    pipesClose
    puts "Node $node removed"
}


#****f* shell_procedures.tcl/deleteLinkIfcs
# NAME
#   deleteLinkIfcs -- delete link and interfaces on node
# SYNOPSIS
#   deleteLink $node
# FUNCTION
#   Procedure deletes link
# INPUTS
#   * link -- link id
#****
proc deleteLinkWithIfcs { link } {
	upvar 0 ::cf::[set ::curcfg]::link_list link_list
	global isOSlinux isOSfreebsd
	if {[lsearch -exact $link_list $link]<0} {
        puts "Link $link doesn't exist. Please choose another link"
        return
    }
    set pnodes [linkPeers $link]
	if {$isOSlinux} {
        foreach node $pnodes {
            stopNode $node
        }
        removeLink $link
        foreach node $pnodes {
            startNode $node
        }
        puts "Link $link ([lindex [linkPeers $link] 0] - [lindex [linkPeers $link] 1]) removed"
    }
	if {$isOSfreebsd} {
        set ifc1 [ifcByPeer [lindex $pnodes 0] [lindex $pnodes 1]]
        set ifc2 [ifcByPeer [lindex $pnodes 1] [lindex $pnodes 0]]
        deleteNodeIfc [lindex $pnodes 0] $ifc1
        deleteNodeIfc [lindex $pnodes 1] $ifc2
    }

	
    global autoSaveOnChange
        if {$autoSaveOnChange} {
            saveConfiguration
        }
}

#****f* shell_procedures.tcl/deleteNodeIfc
# NAME
#   deleteNodeIfc -- deletes interface on node
# SYNOPSIS
#   deleteNodeIfc $node $ifcname
# FUNCTION
#   Procedure deletes interface on node
# INPUTS
#   * node -- node id
#   * ifcname -- interface name
#****
proc deleteNodeIfc {node ifcname} {
    upvar 0 ::cf::[set ::curcfg]::$node $node
	upvar 0 ::cf::[set ::curcfg]::node_list node_list
	upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
	upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::MACUsedList MACUsedList
	global isOSfreebsd isOSlinux
    
  if {$isOSlinux} {
        puts "Can't delete interface on node on Linux"
		return
    }
	if {[lsearch -exact $node_list $node]<0} {
		puts "Node $node doesn't exist. Choose another node"
			return
	}
    if {[lsearch -exact [ifcList $node] $ifcname]<0} {
        puts "Interface $ifcname doesnt exist on node $node"
		if {[ifcList $node]!=""} {
			puts "Available interfaces: [ifcList $node]"
		}else{
			puts "No available interface on node $node to delete"
		}
        return
    }
    #if {[linkByIfc $node $ifcname] != ""} {
        #puts "Link [linkByIfc $node $ifcname] is connected to interface"
        #puts "Please delete link first then interface"
        #return
    #}
    if {$isOSfreebsd} {
        pipesCreate
		set ngnode $ngnodemap($ifcname@$eid.$node)
		pipesExec "jexec $eid ngctl shutdown $ngnode:"
		pipesClose
    }
    
    #Delete link connected to this interface
	set peer [peerByIfc $node $ifcname]
	if {$peer != $node} {
		set link [linkByPeers $node $peer]
		deleteLink $link
	}
    unset ngnodemap($ifcname@$eid.$node)

	netconfClearSection $node "interface $ifcname"
	set i [lsearch [set $node] "interface-peer {$ifcname $node}"]
	set $node [lreplace [set $node] $i $i]
	
	set index [lsearch -exact $MACUsedList [getIfcMACaddr $node $ifcname]]
    set MACUsedList [lreplace $MACUsedList $index $index]

	global autoSaveOnChange
	if {$autoSaveOnChange} {
		saveConfiguration
	}
    puts "Interface $ifcname deleted on node $node"

}

#****f* shell_procedures.tcl/deleteLink
# NAME
#   deleteLink
# SYNOPSIS
#   deleteLink $node
# FUNCTION
#   Procedure deletes link
# INPUTS
#   * link -- link id
#****
proc deleteLink { link } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
    upvar 0 ::cf::[set ::curcfg]::link_list link_list
    upvar 0 ::cf::[set ::curcfg]::$link $link
    upvar 0 ::cf::[set ::curcfg]::IPv4UsedList IPv4UsedList
    upvar 0 ::cf::[set ::curcfg]::IPv6UsedList IPv6UsedList
    upvar 0 ::cf::[set ::curcfg]::MACUsedList MACUsedList
	global isOSfreebsd isOSlinux runtimeDir

	if {[lsearch -exact $link_list $link]<0} {
        puts "Link $link doesn't exist. Please choose another link"
        return
    }

    set pnodes [linkPeers $link]
    if {$isOSlinux} {
        foreach node $pnodes {
            stopNode $node
        }
        removeLink $link
        foreach node $pnodes {
            startNode $node
        }
        return "Link $link removed"
    }
    foreach node $pnodes {
        upvar 0 ::cf::[set ::curcfg]::$node $node

        set i [lsearch $pnodes $node]
        set peer [lreplace $pnodes $i $i]
        set ifc [ifcByPeer $node $peer]
        set index [lsearch -exact $IPv4UsedList [getIfcIPv4addr $node $ifc]]
        set IPv4UsedList [lreplace $IPv4UsedList $index $index]
        set index [lsearch -exact $IPv6UsedList [getIfcIPv6addr $node $ifc]]
        set IPv6UsedList [lreplace $IPv6UsedList $index $index]
        #set index [lsearch -exact $MACUsedList [getIfcMACaddr $node $ifc]]
        #set MACUsedList [lreplace $MACUsedList $index $index]

        set node_id "$eid.$node"
        set ipv4 [getIfcIPv4addr $node $ifc]
        set ipv6 [getIfcIPv6addr $node $ifc]
        #TODO DENIS zasto ne prolazi a inace prolazi
        pipesCreate
        pipesExec "exec jexec $node_id ifconfig $ifc $ipv4 -alias" "hold"
        pipesExec "exec jexec $node_id ifconfig $ifc inet6 $ipv6 -alias"
        pipesClose
		setIfcIPv4addr $node $ifc ""
		setIfcIPv6addr $node $ifc ""
        set i [lsearch [set $node] "interface-peer {$ifc $peer}"]
        set $node [lreplace [set $node] $i $i "interface-peer {$ifc $node}"]

        if { [[typemodel $node].layer] == "NETWORK" } {
            set ifcs [ifcList $node]
                foreach iface $ifcs {
                    autoIPv4defaultroute $node $iface
                }
        }

        foreach lifc [logIfcList $node] {
            switch -exact [getLogIfcType $node $lifc] {
                vlan {
                    if {[getIfcVlanDev $node $lifc] == $ifc} {
                        netconfClearSection $node "interface $lifc"
                    }
                }
            }
        }
    }
    set i [lsearch -exact $link_list $link]
    set link_list [lreplace $link_list $i $i]


    pipesCreate
    destroyLinkBetween $eid [lindex [linkPeers $link] 0] [lindex [linkPeers $link] 1]
    pipesClose

    global autoSaveOnChange
    if {$autoSaveOnChange} {
        saveConfiguration
    }

    puts "Link $link ([lindex [linkPeers $link] 0] - [lindex [linkPeers $link] 1]) removed"
}

#****f* shell_procedures.tcl/saveConfiguration
# NAME
#   saveConfiguration
# SYNOPSIS
#   saveConfiguration
# FUNCTION
#   Procedure saves experiment configuration files to runtime directory
#****
proc saveConfiguration {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
	global runtimeDir
	if {![info exists eid]} {
		return "Container for experiment doesn't exist. Please create one"
	}
	saveRunningConfigurationInteractive $eid
	writeDataToFile $runtimeDir/$eid/timestamp [clock format [clock seconds]]
	dumpLinksToFile $runtimeDir/$eid/links
	dumpNgnodesToFile $runtimeDir/$eid/ngnodemap

}

#****f* shell_procedures.tcl/startConfiguration
# NAME
#   startConfiguration
# SYNOPSIS
#   startConfiguration 
# FUNCTION
#   Procedure creates nodes and links from loaded configuration
#****
proc startConfiguration {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::node_list node_list
	upvar 0 ::cf::[set ::curcfg]::link_list link_list

	pipesCreate
	foreach node $node_list {
		[typemodel $node].instantiate $eid $node
	}
    pipesClose

	foreach link $link_list {
		set node_id1 [lindex [linkPeers $link] 0]
		set node_id2 [lindex [linkPeers $link] 1]
		set ifname1 [ifcByPeer $node_id1 $node_id2]
		set ifname2 [ifcByPeer $node_id2 $node_id1]
		createLinkBetween $node_id1 $node_id2 $ifname1 $ifname2
		configureLinkBetween $node_id1 $node_id2 $ifname1 $ifname2 $link
	}

    #foreach node $node_list {
		#set type [nodeType $node]
		#if {$isOSlinux} {
			#startNode $node
		#} elseif {$isOSfreebsd} {
			#if {$type != "rj45" && [lsearch -exact $l3nodes $type]>=0} {
				#runConfOnNode $node
			#}
		#}
        
    #}
    foreach node $node_list {
				startNode $node
		}
    
}

#****f* shell_procedures.tcl/attachToRunningExperiment
# NAME
#   attachToRunningExperiment
# SYNOPSIS
#   attachToRunningExperiment $eid 
# FUNCTION
#   Attach to currently running experiment
# INPUT
#    * eidInput -- eid of running experiment
#****
proc attachToRunningExperiment { eidInput } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
	global runtimeDir
	
	set experiments [getResumableExperiments]
	
	if {[lsearch -exact $experiments $eidInput]<0} {
        puts "Experiment $eidInput doesn't exist! Choose another one:"
        puts ""
        printResumableExperiments
        return
    }
	
	set eid $eidInput

	set fileId [open $runtimeDir/$eid/config.imn r]
	set ngmapFile "$runtimeDir/$eid/ngnodemap"
	set fileIdn [open $ngmapFile r]
	array set ngnodemap [gets $fileIdn]
	close $fileIdn

	set cfg ""
	foreach entry [read $fileId] {
		lappend cfg $entry
	}
	close $fileId

	loadCfg $cfg
}

#****f* shell_procedures.tcl/printResumableExperiments
# NAME
#   printResumableExperiments
# SYNOPSIS
#   printResumableExperiments 
# FUNCTION
#   List resumable experiments
#****
proc printResumableExperiments {} {
    set experiments [getResumableExperiments]
	if {[llength $experiments] != 0} {
		puts "Resumable experiments:"
			puts "Experiment ID - name : Timestamp"
			foreach exp $experiments {
				puts "$exp - [getExperimentNameFromFile $exp] : [getExperimentTimestampFromFile $exp]"
			}
		puts "Use command \"attachToRunningExperiment experiment_id\" to attach to experiment."
	} else {
		puts "No resumable experiments"
	}
}

#****f* shell_procedures.tcl/printNodeList
# NAME
#   printNodeList
# SYNOPSIS
#   printNodeList 
# FUNCTION
#   List node and link list of current eid
#****
proc printNodeList {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::node_list node_list
	upvar 0 ::cf::[set ::curcfg]::link_list link_list

	puts "Experiment id: $eid"
	puts "Nodes: id (hostname)"
	foreach node $node_list {
		if {[nodeType $node] == "pseudo"} {
			puts "   $node (pseudo node)"
		} else {
			puts "   $node ([getNodeName $node])"    
		}
        }
    if {[llength $link_list]>0} {
        puts "Links: "
		foreach link $link_list {
			set linkpeer1 [lindex [linkPeers $link] 0]
				set linkpeer2 [lindex [linkPeers $link] 1]
				set nodeName1 [getNodeName $linkpeer1]
				set nodeName2 [getNodeName $linkpeer2]
				if {[nodeType $linkpeer1] == "pseudo"} {
					puts "   $link : $linkpeer2 ($nodeName2) - $linkpeer1 (pseudo node): mirror [getLinkMirror $link]"
				} elseif {[nodeType $linkpeer2] == "pseudo"} {
					puts "   $link : $linkpeer1 ($nodeName1) - $linkpeer2 (pseudo node): mirror [getLinkMirror $link]"
				} else {
					puts "   $link : $linkpeer1 ($nodeName1) - $linkpeer2 ($nodeName2)"
				}
		}
}
}




#****f* shell_procedures.tcl/clean
# NAME
#   clean experiment files
# SYNOPSIS
#   clean 
# FUNCTION
#   Procedure terminates all nodes and deletes experiment files
#****
proc clean {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	terminateAllNodes $eid
	deleteExperimentFiles $eid
	unset eid
}

#****f* shell_procedures.tcl/getRandomCoords
# NAME
#   getRandomCoordinates
# SYNOPSIS
#   getRandomCoords 
# FUNCTION
#   Procedure returns random coordinates within canvas size
# RESULT
#   * X and Y coordinates
#****
proc getRandomCoords {} {

    set canvasSize [getCanvasSize "c0"]
	set maxX [expr {[lindex $canvasSize 0] -40}]
	set maxY [expr {[lindex $canvasSize 1] -50}]

	set coordx [expr {20 + round(rand()*$maxX)}]
	set coordy [expr {20 + round(rand()*$maxY)}]

	return "$coordx $coordy"
}


#****f* shell_procedures.tcl/saveImnFile
# NAME
#   saveImnFile -- save current configuration to .imn file
# SYNOPSIS
#   saveImnFile $destination 
# FUNCTION
#   Saves current configuration to IMUNES .imn file
#****
#TODO check for imn extension
proc saveImnFile {destination} {
    set fileName $destination
	set fileId [open $fileName w]
	dumpCfg file $fileId
	close $fileId
}

#****f* shell_procedures.tcl/loadImnFile
# NAME
#   loadImnFile -- Load IMUNES .imn file
# SYNOPSIS
#   loadImnFile $sourceFile 
# FUNCTION
#   Loads previously saved .imn file and starts the experiment
# INPUT
#    * sourceFile -- path to location of file
#****
proc loadImnFile { sourceFile} {
    set eid [createContainer]
	set fileName [file tail $sourceFile]
	set fileId [open $sourceFile r]
	set cfg ""
	foreach entry [read $fileId] {
		lappend cfg $entry
	}
    close $fileId

	loadCfg $cfg

	global runtimeDir
	startConfiguration
	saveConfiguration
	writeDataToFile $runtimeDir/$eid/name $fileName
}

#****f* shell_procedures.tcl/createNodePhysIfc
# NAME
#   createNodePhysIfc -- create node physical interface
# SYNOPSIS
#   createNodePhysIfc $node $ifc
# FUNCTION
#   Creates physical interface for the given node.
# INPUTS
#   * node -- node id
#   * ifc -- interface name
#****
proc createNodePhysIfc { node ifc } {
    upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
    upvar 0 ::cf::[set ::curcfg]::eid eid
    global ifc_dad_disable isOSfreebsd isOSlinux

    set node_id "$eid.$node"
    # Create a vimage
    # Create "physical" network interfaces
    if {$isOSfreebsd} {
        switch -exact [string range $ifc 0 2] {
            eth {
                set ifid [createIfc $eid eiface ether]
                pipesExec "jexec $eid ifconfig $ifid vnet $node" "hold"
                pipesExec "jexec $node_id ifconfig $ifid name $ifc" "hold"

                # XXX ng renaming is automatic in FBSD 8.4 and 9.2, remove this!
                pipesExec "jexec $node_id ngctl name [set ifid]: $ifc" "hold"

        #        set peer [peerByIfc $node $ifc]
                set ether [getIfcMACaddr $node $ifc]
                        if {$ether == ""} {
                            autoMACaddr $node $ifc
                        }
                        set ether [getIfcMACaddr $node $ifc]
                global ifc_dad_disable
                if {$ifc_dad_disable} {
                    pipesExec "jexec $node_id sysctl net.inet6.ip6.dad_count=0" "hold"
                }
                pipesExec "jexec $node_id ifconfig $ifc link $ether" "hold"
                set ngnodemap($ifc@$node_id) $ifid
            }
            ext {
                set ifid [createIfc $eid eiface ether]
                set outifc "$eid-$node"
                pipesExec "ifconfig $ifid -vnet $eid" "hold"
                pipesExec "ifconfig $ifid name $outifc" "hold"

                # XXX ng renaming is automatic in FBSD 8.4 and 9.2, remove this!
                pipesExec "ngctl name [set ifid]: $outifc" "hold"

                set ether [getIfcMACaddr $node $ifc]
                        if {$ether == ""} {
                            autoMACaddr $node $ifc
                        }
                        set ether [getIfcMACaddr $node $ifc]
                pipesExec "ifconfig $outifc link $ether" "hold"
                set ngnodemap($ifc@$node_id) $ifid
            }
            ser {
    #        set ifnum [string range $ifc 3 end]
    #        set ifid [createIfc $eid iface inet]
    #        pipesExec "jexec $eid ngctl mkpeer $ifid: cisco inet inet" "hold"
    #        pipesExec "jexec $eid ngctl connect $ifid: $ifid:inet inet6 inet6" "hold"
    #        pipesExec "jexec $eid ngctl msg $ifid: broadcast" "hold"
    #        pipesExec "jexec $eid ngctl name $ifid:inet hdlc$ifnum\@$node" "hold"
    #        pipesExec "jexec $eid ifconfig $ifid vnet $node" "hold"
    #        pipesExec "jexec $node_id ifconfig $ifid name $ifc" "hold"
    #        set ngnodemap(hdlc$ifnum@$node_id) hdlc$ifnum\@$node"
            }
        }
    }
    if {$isOSlinux} {
        puts "Cant create node physical interface on Linux"
        return
            set ether [getIfcMACaddr $node $ifc]
            if {$ether == ""} {
                autoMACaddr $node $ifc
            }
            set ether [getIfcMACaddr $node $ifc]
            puts "ifc je $ifc"
            # prepare namespace files
            set nodeNs [createNetNs $node]
            puts "nodens $nodeNs"
            # generate temporary interface name
            set hostIfc "v${ifc}pn${nodeNs}"
            puts "hostIfc $hostIfc"
            # create veth pair
            set hostIfctmp "$hostIfc\_tmp"
            puts "hostifctmp $hostIfctmp"
            exec ip link add name "$hostIfc" type veth peer name "$hostIfctmp"
            #exec ip link add name martin type veth peer name martintmp
            # move veth pair side to node namespace
            setIfcNetNs $node $hostIfc $ifc
            # set mac addresse of node ifc
            exec nsenter -n -t $nodeNs ip link set dev "$ifc" \
            address "$ether"
            # delete net namespace reference file
            exec ip netns del $nodeNs
    }   
}


#Prints available commands
proc help {} {
	global procedures
	puts "Available commands:"
	foreach procedure $procedures {
		puts "   $procedure"
	}
    puts "Use \"man command_name\" for more options"
}

#****f* shell_procedures.tcl/setautoSaveOnChange
# NAME
#   setautoSaveOnChange -- set value variable autoSaveOnChange
# SYNOPSIS
#   setautoSaveOnChange $status 
# FUNCTION
#   Procedure sets value of variable setautoSaveOnChange to 0 or 1
#****
proc setautoSaveOnChange { status } {
    global autoSaveOnChange
	if { $status==1 || $status==0} {
		set autoSaveOnChange $status
		puts "autoSaveOnChange set to $status"
	} else {
		puts "Wrong argument. Acceptable 0 or 1"
	}
}

#****f* shell_procedures.tcl/getautoSaveOnChange
# NAME
#   getautoSaveOnChange -- get value of variable autoSaveOnChange
# SYNOPSIS
#   getautoSaveOnChange 
# FUNCTION
#   Procedure returns value of variable autoSaveOnChange
#****
proc getautoSaveOnChange { } {
    global autoSaveOnChange
	puts "Automatic saving when change occurs is set to $autoSaveOnChange"
}

#****f* shell_procedures.tcl/man
# NAME
#   man -- manual pages
# SYNOPSIS
#   man $procedure
# FUNCTION
#   Prints description of procedure
# INPUTS
#   * $procedure -- procedure name
#****
proc man {procedure} {
    set filep [open "shell_procedures.tcl" r]
    set lines [split [read $filep] "\n"]
    close $filep
    set man {}
    set first 0
    foreach command $lines {
        if { !$first } {
            set proced ""
            regexp "^#\\*\\*\\*\\*f\\*\.*\/(\.*)" $command match proced
            if {$proced != ""} {
                lappend man $proced
                set text {}
                set first 1
            }
            continue
        }
        if {[regexp "^#\\*\\*\\*\\*\$" $command]} {
            set first 0
            lappend man $text
            set text {}
            continue
        }
        if { $first } {
            set command [string trim $command "#"]
            set text "$text \"$command\""
        }
    }
    set index [lsearch -exact $man $procedure]
    if {$index>=0} {
        incr index
        foreach line [lindex $man $index] {
            puts "$line"
        }
    } else {
        puts "Procedure $procedure not found"
    }
}




proc upv {varname} {
	puts "upvar 0 ::cf::\[set ::curcfg\]::$varname $varname"
	return
    upvar 0 ::cf::[set ::curcfg]::$varname $varname
        if {"$varname" == "ngnodemap"} {
            parray ngnodemap
        } else {
            puts $varname
        }
}


#TODO elseif regex za IP dal je obavezan subnet?
# ovisno o sustavu Linux ili freeBSD
# setIfcIPv4addr (start/stop)
proc setIPv4OnIfc { node ifc ip } {
    upvar 0 ::cf::[set ::curcfg]::eid eid
        upvar 0 ::cf::[set ::curcfg]::node_list node_list
        global isOSfreebsd isOSlinux
        if {[lsearch -exact $node_list $node] < 0} {
            puts "Node not found, choose node: "
                puts $node_list    
        } elseif {[lsearch -exact [ifcList $node] $ifc] < 0} {
            puts "Interface $ifc on node $node not found."
                if {[llength [ifcList $node]] > 0} {
                    puts "Availabe interfaces: [ifcList $node]"
                } else {
                    puts "No interfaces on node $node"
                }
        } elseif {! [regexp "^((\[0-9]|\[1-9]\[0-9]|1\[0-9]{2}|2\[0-4]\[0-9]|25\[0-5])\.){3}(\[0-9]|\[1-9]\[0-9]|1\[0-9]{2}|2\[0-4]\[0-9]|25\[0-5])(\/(\[0-9]|\[0-2]\[0-9]|3\[0-2]))?\$" $ip]} {
            puts "Wrong format of IP address"
        }

        else {
            if {isOSfreebsd} {
                exec "jexec $eid.$node ifconfig $ifc $ip"
            }
            elseif {isOSlinux} {

            }
            setIfcIPv4addrs $node $ifc $addr
        }
}
#obsolete
proc saveConfigImn {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
	upvar 0 ::cf::[set ::curcfg]::ngnodemap ngnodemap
	global runtimeDir

	writeDataToFile $runtimeDir/$eid/timestamp [clock format [clock seconds]]

	dumpNgnodesToFile $runtimeDir/$eid/ngnodemap
	##set ngmapFile "$runtimeDir/$eid/ngnodemap"
	##set fileId [open $ngmapFile r]
	##array set ngnodemap [gets $fileId]
	##close $fileId

	set fileName "$runtimeDir/$eid/config.imn"
	set fileId [open $fileName w]
	dumpCfg file $fileId
	close $fileId
}

