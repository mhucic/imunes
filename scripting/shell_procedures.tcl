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

foreach f [list mac nodecfg linkcfg ipv4 ipv6 ipsec] {
    source "../config/$f.tcl"
}

foreach f [list editor] {
    source "../gui/$f.tcl"
}

# Set default L2 node list
set l2nodes "hub lanswitch click_l2 rj45 stpswitch filter packgen nat64"
# Set default L3 node list
set l3nodes "genericrouter quagga xorp static click_l3 host pc"

# Set default supported router models
set supp_router_models "xorp quagga static"

if { [string match -nocase "*linux*" $os] == 1 } {
    # Limit default nodes on linux
    set l2nodes "lanswitch rj45"
    set l3nodes "genericrouter quagga static pc host"
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

#~ foreach f [list pc] {
    #~ source "nodes/$f.tcl"
#~ }

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

# router
set rdconfig ""
set model quagga
set router_model $model
set routerDefaultsModel $model
set def_router_model quagga


# changeME
set currentFileBatch remoteBla

lappend cfg_list $curcfg
namespace eval ::cf::[set curcfg] {}
set eid_base i[format %04x [expr {[pid] + [expr { round( rand()*10000 ) }]}]]

proc createContainer {} {
	global eid_base runtimeDir
    upvar 0 ::cf::[set ::curcfg]::eid eid
    set eid ${eid_base}[string range $::curcfg 1 end]
    loadKernelModules
	prepareVirtualFS
	prepareDevfs
	createExperimentContainer
	
	file mkdir "$runtimeDir/$eid"
}

proc createNode { type } {
    set node [newNode $type]
    
    if {$type == "router"} {
		setNodeModel $node quagga
		setNodeProtocolRip $node 1
	}
		 
    
    instNode $node
    startNode $node

    return "Node $node created"
}

proc instNode { node } {
	upvar 0 ::cf::[set ::curcfg]::eid eid

	pipesCreate
	[typemodel $node].instantiate $eid $node
	pipesClose
}

proc startNode { node } {
	upvar 0 ::cf::[set ::curcfg]::eid eid

	[typemodel $node].start $eid $node
}

proc stopNode { node } {
	upvar 0 ::cf::[set ::curcfg]::eid eid
	
	[typemodel $node].shutdown $eid $node
}


proc createLink { node_id1 node_id2} {    
    set link [newLink $node_id1 $node_id2]
    
    startLink $link
    
    foreach node "$node_id1 $node_id2" {
		stopNode $node
		startNode $node
	}
	
	return "Link $link created"
}

proc startLink { link } {
	set node_id1 [lindex [linkPeers $link] 0]
	set node_id2 [lindex [linkPeers $link] 1]
	set ifname1 [ifcByPeer $node_id1 $node_id2]
	set ifname2 [ifcByPeer $node_id2 $node_id1]
	
	createLinkBetween $node_id1 $node_id2 $ifname1 $ifname2
	configureLinkBetween $node_id1 $node_id2 $ifname1 $ifname2 $link
}




proc deleteNode { node } {
	foreach ifc [ifcList $node] {
		set peer [peerByIfc $node $ifc]
		set link [linkByPeers $node $peer]
		deleteLink $link
	}
	
	removeNode $node
	
}

proc deleteLink { link } {
	set pnodes [linkPeers $link]
    foreach node $pnodes {
		stopNode $node
	}
	removeLink $link
	foreach node $pnodes {
		startNode $node
	}
	return "Link $link removed"
}


proc saveConfiguration {} {
	upvar 0 ::cf::[set ::curcfg]::eid eid
	saveRunningConfigurationInteractive $eid
}

proc printNodeList {} {
    upvar 0 ::cf::[set ::curcfg]::eid eid
    upvar 0 ::cf::[set ::curcfg]::node_list node_list
    upvar 0 ::cf::[set ::curcfg]::link_list link_list
	
	puts "eid: $eid"
	puts "nodes: $node_list"
	puts "links: "
	foreach link $link_list {
		puts "$link : [lindex [linkPeers $link] 0] - [lindex [linkPeers $link] 1]"
	}
	
}

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
	
	foreach node $node_list {
		[typemodel $node].start $eid $node
	}
}

createContainer 
createNode pc
createNode pc
createLink n0 n1
createNode router
createNode pc
createLink n1 n2
createLink n2 n3
printNodeList
