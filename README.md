# PebbleDissector

This is Pebble wire protocol dissector for Wireshark. It is intended to be used for Bluetooth serial protocol profile HCI capture.

Normally you'd enable Bluetooth HCI dump under Developer settings which will start dumping HCI frames to btsnoop_hci.log file under SD card root.

Copy resulting file and load it to the wireshark.

## Usage

* Put the file into personal plugins dir (eg .config/wireshark/plugins) - create the dir if necessary
* Restart Wireshark, go to Analyze -> Enabled Protocols, find PEBBLE protocol and enable it
* Load bthci log file - plugin should automatically attach to DLCI Channel 1 (0x2), you may use Decode As.. to force it
* Optionally filter out service frames by adding filter 'btrfcomm.dlci==2 && btrfcomm.len > 1' 

On SailfishOS

* Install bluez-hcidump package (pkcon refresh + pkcon install bluez-hcidump)
* Capture full HCI frames to the file (hcidump -l0 -w /tmp/hcidump.pcap)
* Optional - reconnect BT device to capture connection handle or use decode override as below
* Copy pcap file to wireshark and force L2CAP CID 0x0040 as BT RFCOMM
* or use tshark -r btdump.pcap -d btl2cap.cid==64,btrfcomm
