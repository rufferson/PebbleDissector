--[[
-- vim: ts=4 sts=4 et

Inspired by: https://github.com/pieterjm/PebbleDissector

Copyright (c) 2017 Ruslan N. Marchenko
License: LGPLv3 https://www.gnu.org/licenses/lgpl-3.0.en.html

--]]
--
local pebble_proto = Proto("pebble","Pebble Serial Protocol")
local data = Dissector.get("data")

local pebble_endpoint = ProtoField.uint16("pebble.endpoint", "Endpoint")
local pebble_length = ProtoField.uint16("pebble.length", "Length")
local pebble_type = ProtoField.uint8("pebble.type", "Type")

pebble_proto.fields = { pebble_length, pebble_endpoint, pebble_type }

local lookup_tuple_type = {
		 [0] = "BYTE_ARRAY",
		 [1] = "CSTRING",
		 [2] = "UINT",
		 [3] = "INT"
}

local function uuid(buf)
    return buf(0,4).."-"..buf(4,2).."-"..buf(6,2).."-"..buf(8,2).."-"..buf(10,6)
end
local function utfs(buffer)
    return buffer:string(ENC_UTF8)
end

local lookup_amsg = {
	  [1] = {
	      name = "PUSH",
	      dissector = function(buffer,pinfo,tree)
			local numtuples = buffer(16,1):uint()
			tree:add(buffer(0,16),"UUID: " ..uuid(buffer(0,16)))
			tree:add(buffer(16,1),"Number of tuples: " .. numtuples)

			offset = 17
			for i = 1,numtuples do
			    subtree = tree:add(buffer(0,0),"Tuple " .. i)
			    subtree:add(buffer(offset,4),"Key: " .. buffer(offset,4):le_uint())

			    local type = buffer(offset + 4,1):uint()
			    subtree:add(buffer(offset + 4,1),"Type: " .. lookup_tuple_type[type] .. " (" .. type .. ")")

			    local length = buffer(offset + 5,2):le_uint()
			    subtree:add(buffer(offset + 5,2),"Length: " .. length )

			    local value = "undefined"
			    if type == 2 then
			       value = buffer(offset + 7,length):le_uint()
			    elseif type == 3 then
			       value = buffer(offset + 7,length):le_int()
			    end

			    subtree:add(buffer(offset + 7,length),"Value: " .. value )
			    offset = offset + 7 + length
			end
	      end
	  },
	  [2] = {
	      name = "REQUEST"
	  },
	  [127] = {
	  	name = "NACK"
	  },
	  [255] = {
	  	name = "ACK"	 
	  } 
}
local appMsg = function(buffer,pinfo,tree) 
    local type = buffer(0,1):uint()
    local transactionid = buffer(1,1):uint() 
    local len = buffer:len()
       		  
	local amsg = lookup_amsg[type]
	if amsg then
		pinfo.cols.info:append(" (" .. amsg.name .. ")")
		tree:add(buffer(0,1),"Type: " .. amsg.name .. "(" .. type .. ")" )    
       	tree:add(buffer(1,1),"Transaction Id: " .. transactionid)		  
		if len > 2 and amsg.dissector then
		    tree = tree:add(buffer(2,len - 2),amsg.name)
		    amsg.dissector(buffer(2, len - 2),pinfo,tree)
		end	
	else
  	    pinfo.cols.info = "ERROR: Unknown application message type (" .. type .. ")"
    end
end
local musCmd = {
    [1] = { name = "PlayPause" },
    [2] = { name = "Pause" },
    [3] = { name = "Play" },
    [4] = { name = "NextTrack" },
    [5] = { name = "PrevTrack" },
    [6] = { name = "VolumeUp" },
    [7] = { name = "VolumeDown" },
    [8] = { name = "GetCurrentTrack" },
    [16] = {
        name = "UpdateCurrentTrack",
        dissector = function(buffer,pinfo,tree)
            local plen = buffer(0,1):uint()
            local alen = buffer(plen+1,1):uint()
            local tlen = buffer(plen+alen+2,1):uint()
            local sub = tree:add(buffer(),"UpdateCurrentTrack",buffer())
            sub:add(buffer(1,plen),"Artist: "..buffer(1,plen):string(ENC_UTF8))
            sub:add(buffer(2+plen,alen),"Album: "..buffer(2+plen,alen):string(ENC_UTF8))
            sub:add(buffer(3+plen+alen,tlen),"Title: "..buffer(3+plen+alen,tlen):string(ENC_UTF8))
            local off = 3+plen+alen+tlen
            if off < buffer:len() then
                sub:add(buffer(off,4),"Length: "..buffer(off,4):uint())
                off = off + 4
            end
            if off < buffer:len() then
                sub:add(buffer(off,2),"Tracks: "..buffer(off,2):uint())
                off = off + 2
            end
            if off < buffer:len() then
                sub:add(buffer(off,2),"Current: "..buffer(off,2):uint())
            end
        end
    },
    [17] = {
        name = "UpdatePlayStateInfo",
        dissector = function(buffer,pinfo,tree)
            local sub = tree:add(buffer(),"UpdatePlayerStateInfo",buffer())
            local sts = {"Paused", "Playing", "Rewinding", "FForwarding", "Unknown"}
            local state = buffer(0,1):uint()
            sub:add(buffer(0,1),"State: "..sts[state+1].."["..state.."]")
            sub:add(buffer(1,4),"Track Position: "..buffer(1,4):le_uint())
            sub:add(buffer(5,4),"Play Rate: "..buffer(5,4):le_uint())
            local shufs = {"Unknown", "Off", "On"}
            local shuff = buffer(9,1):uint()
            sub:add(buffer(9,1),"Shuffle: "..shufs[shuff+1].."["..shuff.."]")
            local rept = buffer(10,1):uint()
            local reps = {"Unknown", "Off", "One", "All"}
            sub:add(buffer(10,1),"Repeat: "..reps[rept+1].."["..rept.."]")
        end
    },
    [18] = {
        name = "UpdateVolumeInfo",
        dissector = function(buffer,pinfo,tree)
            local sub = tree:add(buffer(),"UpdateVolumeInfo",buffer())
            sub:add(buffer(0,1),"Volume: "..buffer(0,1):uint().."%")
        end
    },
    [19] = {
        name = "UpdatePlayerInfo",
        dissector = function(buffer,pinfo,tree)
            local sub = tree:add(buffer(),"UpdatePlayerInfo",buffer())
            local len = buffer(0,1):uint()
            sub:add(buffer(0,1+len),"Package: "..buffer(1,len):string(ENC_UTF8))
            local nln = buffer(1+len,1):uint()
            sub:add(buffer(1+len,1+nln),"Name: "..buffer(2+len,nln):string(ENC_UTF8))
        end
    }
}
local function dissectAttrs(buffer,count,atts)
    local off = 0
    for i = 1,count do
        atts[i] = {
            id = buffer(off,1),
            len = buffer(off+1,2),
            data = buffer(off+3,len)
        }
        off = off + atts[i].len:le_uint() + 3
    end
    return off
end
local function dissectLayout(buffer,pinfo,tree)
    local size = buffer(0,2):le_uint()
    local sub = tree:add(buffer(0,size+4),"Layout")
    sub:add(buffer(0,2),"Size: "..size)
    local atc = buffer(2,1):uint()
    local acc = buffer(3,1):uint()
    sub:add(buffer(2,1),"AttributeNum: "..atc)
    sub:add(buffer(3,1),"ActionNum: "..acc)
    local atrs = {}
    local atrlen = dissectAttrs(buffer(4),atc,atrs)
    local attsub = sub:add(buffer(4,atrlen),"Attributes".."["..atc.."]")
    local actsub = sub:add(buffer(4+atrlen),"Actions".."["..acc.."]")
    local off = 4 + atrlen
    for i = 1, acc do
        local aats = {}
        local id = buffer(off,1)
        local type = buffer(off+1,1)
        local aatc = buffer(off+2,1):uint()
        local atln = dissectAttrs(buffer(off+3),aatc,aats)
        local item = actsub:add(buffer(off,3+atln),"Action "..id:uint())
        item:add(id,"ID: "..id:uint())
        item:add(type,"Type: "..type:uint())
        off = off + 3 + atln
    end
end
local dissectTimeline = function(buffer,pinfo,tree)
    local sub = tree:add(buffer(),"TimelineItem")
    sub:add(buffer(0,16),"Item UUID: "..uuid(buffer(0,16)))
    sub:add(buffer(16,16),"Parent UUID: "..uuid(buffer(16,16)))
    sub:add(buffer(32,4),"Time: "..format_date(buffer(32,4):le_uint()))
    sub:add(buffer(36,2),"Duration: "..buffer(36,2):uint())
    local type = {"Notification","TimelinePin","Reminder"}
    sub:add(buffer(38,1),"Type: "..type[buffer(38,1):uint()].."["..buffer(38,1):uint().."]")
    sub:add(buffer(39,2),"Flags: "..buffer(39,2))
    sub:add(buffer(41,1),"Layout: "..buffer(41,1):uint())
    dissectLayout(buffer(42),pinfo,sub)
end
local blobs = {
    [0] = { name = "Test" },
    [1] = {
        name = "Timeline",
        disk = uuid,
        disv = dissectTimeline
    },
    [2] = {
        name = "Application",
        disk = uuid,
        disv = function(buffer,pinfo,tree)
            local sub = tree:add(buffer(),"AppMetadata")
            sub:add(buffer(0,16),"UUID: "..uuid(buffer(0,16)))
            sub:add(buffer(16,4),"Flags: "..buffer(16,4))
            sub:add(buffer(20,4),"Icon: "..buffer(20,4):le_uint())
            sub:add(buffer(24,2),"AppVer: "..buffer(24,1):uint().."."..buffer(25,1):uint())
            sub:add(buffer(26,2),"SdkVer: "..buffer(26,1):uint().."."..buffer(27,1):uint())
            sub:add(buffer(28,1),"AppFaceBgColor: "..buffer(28,1))
            sub:add(buffer(29,1),"AppFaceTemplate: "..buffer(29,1):uint())
            sub:add(buffer(30,96),"AppName: "..buffer(30,96):stringz(ENC_UTF8))
        end
    },
    [3] = {
        name = "Reminder",
        disk = uuid,
        disv = dissectTimeline
    },
    [4] = {
        name = "Notification",
        disk = uuid,
        disv = dissectTimeline
    },
    [5] = { name = "Weather" },
    [6] = {
        name = "SendText",
        disk = utfs
    },
    [7] = {
        name = "Health",
        disk = utfs
    },
    [8] = {
        name = "Contact",
        disk = uuid
    },
    [9] = {
        name = "Settings",
        disk = utfs
    },
    [10] = {
        name = "Fitness",
        disk = utfs
    },
    [11] = { name = "Glances" },
    [255] = { name = "Void" }
}
local blobSts = {"Success", "Failure", "InvalidOp", "InvalidDbID", "InvalidData", "NoSuchKey", "DBisFull", "DBisStale", "NotSupported", "Locked", "TryAgain"}
local blobCmd = {
    [1] = {
        name = "Insert",
        dissector = function(buffer,pinfo,tree,blob)
            local klen = buffer(0,1):uint()
            local vlen = buffer(1+klen,2):le_uint()
            local sub = tree:add(buffer(),"InsertCommand")
            local b = blobs[blob]
            local key = (b.disk and b.disk(buffer(1,klen)) or buffer(1,klen))
            sub:add(buffer(0,1+klen),"Key: "..key)
            pinfo.cols.info:append(" "..key)
            if b.disv then
                b.disv(buffer(3+klen,vlen),pinfo,sub)
            end
        end
    },
    [4] = {
        name = "Delete",
        dissector = function(buffer,pinfo,tree,blob)
            local klen = buffer(0,1):uint()
            local sub = tree:add(buffer(),"DeleteCommand")
            local b = blobs[blob]
            local key = (b.disk and b.disk(buffer(1,klen)) or buffer(1,klen))
            sub:add(buffer(0,1+klen),"Key: "..key)
            pinfo.cols.info:append(" "..key)
        end
    },
    [5] = { name = "Clear" }
}

local fwVer = function(tvb,pinfo,tree)
    tree:add(tvb(0,4), "Timestamp:  "..format_date(tvb(0,4):uint()))
    tree:add(tvb(4,32),"VersionTag: "..tvb(4,32):stringz())
    tree:add(tvb(36,8),"GIT Hash:   "..tvb(36,8):stringz())
    tree:add(tvb(44,1),"IsRecovery: "..tvb(44,1))
    tree:add(tvb(45,1),"HardwarePf: 0x"..tvb(45,1))
    tree:add(tvb(46,1),"MetaDataVer:"..tvb(46,1))
end
local capsDis = function(buf,pinfo,tree)
    local pct = tree:add(buf(0,8),"ProtocolCaps: "..buf(0,8))
    local caps = buf:range(0,4)
    local pca = pct:add(buf(0,4), "Active Caps xxxx 0000: ".. caps)
    pca:add(buf(0,1),"0000 0000 0000 0001 [AppRunState    ]: "..caps:bitfield(7))
    pca:add(buf(0,1),"0000 0000 0000 0010 [InfiniteLogDump]: "..caps:bitfield(6))
    pca:add(buf(0,1),"0000 0000 0000 0100 [UpdMusicProto  ]: "..caps:bitfield(5))
    pca:add(buf(0,1),"0000 0000 0000 1000 [ExtendedNotify ]: "..caps:bitfield(4))
    pca:add(buf(0,1),"0000 0000 0001 0000 [LanguagePacks  ]: "..caps:bitfield(3))
    pca:add(buf(0,1),"0000 0000 0010 0000 [8kAppMessages  ]: "..caps:bitfield(2))
    pca:add(buf(0,1),"0000 0000 0100 0000 [Health Support ]: "..caps:bitfield(1))
    pca:add(buf(0,1),"0000 0000 1000 0000 [Voice Support  ]: "..caps:bitfield(0))
    pca:add(buf(1,1),"0000 0001 0000 0000 [Weather Support]: "..caps:bitfield(15))
    pca:add(buf(1,1),"0000 0010 0000 0000 [Unknown Caps   ]: "..caps:bitfield(14))
    pca:add(buf(1,1),"0000 0100 0000 0000 [Unknown Caps   ]: "..caps:bitfield(13))
    pca:add(buf(1,1),"0000 1000 0000 0000 [Can Send SMSs  ]: "..caps:bitfield(12))
    --
    pct:add(buf(4,4),"Reserved Caps .... xxxx: "..buf(4,4))
end
local lookup_endpoint = {
  [11] = {
    name = "TIME",
    dissector = function(buffer, pinfo, tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        local off = 1
        if type == 0 then
            pinfo.cols.info:append(" (Request)")
        elseif type == 1 then
            pinfo.cols.info:append(" (Response)")
            tree:add(buffer(1,4),"Time: "..format_date(buffer(1,4):uint()))
        elseif type == 2 then
            pinfo.cols.info:append(" (SetLocal)")
            tree:add(buffer(1,4),"Time: "..format_date(buffer(1,4):uint()))
        elseif type == 3 then
            pinfo.cols.info:append(" (SetUTC)")
            tree:add(buffer(1,4),"Time: "..format_date(buffer(1,4):uint()))
            tree:add(buffer(5,2),"Offset: "..buffer(5,2):int())
            local len = buffer(7,1):uint()
            tree:add(buffer(7,1+len),"Zone: "..buffer(8,len):string(ENC_UTF8))
        end
    end
  },
  [16] = {
    name = "VERSION",
    dissector = function(buffer, pinfo, tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        local off = 1
        if type == 0 then
            pinfo.cols.info:append(" (Request)")
        elseif type == 1 then
            pinfo.cols.info:append(" (Response)")
            local subv = tree:add(buffer(off,150),"WatchVersion", buffer(off,47+47+4+9+12+6+4+4+6+2+8+1))
            local afwv = subv:add(buffer(off,47), "ActiveFirmware", buffer(off,47))
            fwVer(buffer:range(off,47),pinfo,afwv)
            off = off + 47
            local rfwv = subv:add(buffer(off,47), "RecoveryFirmware", buffer(off,47))
            fwVer(buffer:range(off,47),pinfo,rfwv)
            off = off + 47
            subv:add(buffer(off,4), "Bootloader TS:   "..format_date(buffer(off,4):uint()))
            off = off + 4
            subv:add(buffer(off,9), "Board: "..buffer(off,9):stringz())
            off = off + 9
            subv:add(buffer(off,12), "Serial: "..buffer(off,12):string())
            off = off + 12
            subv:add(buffer(off,6), "BT MAC: "..tostring(buffer(off,6):ether()))
            off = off + 6
            subv:add(buffer(off,4), "ResourceCRC: "..buffer(off,4))
            off = off + 4
            subv:add(buffer(off,4), "Resource TS:   "..format_date(buffer(off,4):uint()))
            off = off + 4
            subv:add(buffer(off,6), "Language: "..buffer(off,6):stringz())
            off = off + 6
            subv:add(buffer(off,2), "LangVersion: "..buffer(off,2):uint())
            off = off + 2
            capsDis(buffer(off,8),pinfo,subv)
            off = off + 8
            if off < buffer:len() then
                subv:add(buffer(off,1), "IsUnfaithful: "..buffer(off,1))
            end
        else
            pinfo.cols.info:append(" ERROR: Unknown WatchVersion payload type ".. type)
        end
    end
 },
 [17] = {
	name = "PHONE_VERSION",
    dissector = function(buffer, pinfo, tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        if type == 0 then
            pinfo.cols.info:append(" (Request)")
        elseif type == 1 then
            pinfo.cols.info:append(" (Response)")
            local subv = tree:add("PhoneVersion",buffer(1,24))
            subv:add(buffer(1,4), "ProtocolVer:   "..buffer(1,4))
            subv:add(buffer(5,4), "SessionCaps:   "..buffer(5,4))
            subv:add(buffer(9,4), "PlatformFlags: "..buffer(9,4))
            subv:add(buffer(13,1),"ResponseVersion: "..buffer(13,1))
            local vst = subv:add(buffer(14,3),"VersionString: "..buffer(14,1):uint().."."..buffer(15,1):uint().."."..buffer(16,1):uint())
            vst:add(buffer(14,1),"MajorVersion:  "..buffer(14,1))
            vst:add(buffer(15,1),"MinorVersion:  "..buffer(15,1))
            vst:add(buffer(16,1),"BugfixVersion: "..buffer(16,1))
            --
            capsDis(buffer(17,8),pinfo,subv)
        else
            pinfo.cols.info:append(" ERROR: Unknown PhoneVersion payload type ".. type)
        end
    end
	},
 [18] = {
	name = "SYSTEM_MESSAGE",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(1,1):uint()
        tree:add(buffer(0,1),"Command: "..buffer(0,1))
        tree:add(pebble_type, buffer(1,1))
        local types = {"FwUpdateAvailable","FwUpdateStart","FwUpdateComplete","FwUpdateFailed","FwUpToDate","StopReconnecting","StartReconnecting","MAPDisabled","MAPEnabled","FwUpdateStartResponse"}
        pinfo.cols.info:append(" ("..types[type+1]..":"..buffer(0,1)..")")
        if type == 10 and buffer:len() > 2 then
            tree:add(buffer(2,1),"Response: "..buffer(2,1))
        end
    end
	},
 [32] = {
	name = "MUSIC_CONTROL",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        local cmd = musCmd[type]
        pinfo.cols.info:append(" ("..cmd.name..")")
        if cmd.dissector then
            cmd.dissector(buffer(1),pinfo,tree)
        end
    end
	},
 [33] = {
    name = "PHONE_CONTROL",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        local cmds = {"Answer","Hangup","StateRequest","StateResponse","Incoming","Outgoing","Missed","Ring","CallStart","CallEnd"}
        tree:add(pebble_type, buffer(0,1))
        pinfo.cols.info:append(" ("..cmds[type < 128 and type or type - 128]..":"..buffer(1,4)..")")
        if type == 4 or type == 6 then
            local len = buffer(5,1):uint()
            tree:add("Number: "..buffer(6,len):string(ENC_UTF8))
            tree:add("Name: "..buffer(7+len,buffer(6+len,1):uint()):string(ENC_UTF8))
            pinfo.cols.info:append(" "..buffer(6,len):string(ENC_UTF8))
        elseif type == 0x83 then
            local cnt = buffer(5,1):uint()
            local sub = tree:add(buffer(6),"Items["..cnt.."]")
        end
    end
	},
 [48] = {
	name = "APPLICATION_MESSAGE",
	dissector = appMsg
    },
 [49] = {
	name = "LAUNCHER",
    dissector = appMsg
	},
 [52] = {
    name = "APP_RUN_STATE",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        if type == 1 then
            pinfo.cols.info:append(" (START)")
            tree:add(buffer(1,16),"UUD: "..uuid(buffer(1,16)))
        elseif type == 2 then
            pinfo.cols.info:append(" (STOP)")
            tree:add(buffer(1,16),"UUD: "..uuid(buffer(1,16)))
        elseif type == 3 then
            pinfo.cols.info:append(" (Request)")
        end
    end
 },
 [2000] = {
	name = "LOGS"
	},
 [2001] = {
	name = "PING",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        tree:add(buffer(1,4),"Cookie: "..buffer(1,4))
        if type == 0 then
            tree:add(buffer(5,1),"Idle: "..buffer(5,1))
        end
        pinfo.cols.info:append(" ("..(type == 1 and "Pong" or "Ping")..")")
    end
	},
 [2002] = {
	name = "LOG_DUMP"
	},
 [2003] = {
	name = "RESET"
	},
 [2004] = {
	name = "APP"
	},
 [2006] = {
	name = "APP_LOGS"
	},
 [3010] = {
	name = "EXTENSIBLE_NOTIFS"
	},
 [4000] = {
	name = "RESOURCE"
	},
 [5000] = {
	name = "SYS_REG"
	},
 [5001] = {
	name = "FCT_REG",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        local len = buffer(1,1):uint()
        if type == 0 then
       		pinfo.cols.info:append(" (Request)")
            tree:add(buffer(2,len),"Key: "..buffer(2,len):string(ENC_UTF8))
        elseif type == 1 then
       		pinfo.cols.info:append(" (Response)")
            tree:add(buffer(2,len),"Value: "..buffer(2,len).."["..buffer(2,4):uint().."]")
        else
       		pinfo.cols.info:append(" (Error)")
        end
    end
	},
 [6000] = {
	name = "APP_MANAGER"
	},
 [6001] = {
	name = "APP_FETCH",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        if buffer:len() > 2 then
            tree:add(buffer(1,16),"AppUUID: "..uuid(buffer(1,16)))
            tree:add(buffer(17,4),"AppID: "..buffer(17,4):uint())
            pinfo.cols.info:append(" (Fetch["..type.."]) "..uuid(buffer(1,16)));
        else
            local status = {"Start","Busy","InvalidUUID","NoData"}
            local code = buffer(1,1):uint()
            tree:add(buffer(1,1),"Status: "..status[code].."["..code.."]")
            pinfo.cols.info:append(" ("..status[code].."["..code.."])")
        end
    end
	},
 [6778] = {
    name = "DATA_LOG",
    dissector = function(buffer,pinfo,tree) 
       	local type = buffer(0,1):uint()
        local dir = 0
        local log_type = {"DespoolOpenSession","DespoolSendData","CloseSession","ReportOpenSession","ACK","NACK","Timeout","EmptySession","GetSendEnableReq","GetSendEnableResp","SetSendEnable"}
       	tree:add(pebble_type, buffer(0,1))
        if type < 4 or type == 0x85 or type == 0x86 or type == 0x88 then
       	    tree:add(buffer(1,1),"SessionID: "..buffer(1,1))
       	    pinfo.cols.info:append(" ("..buffer(1,1)..":"..log_type[type > 127 and type - 128 or type]..")")
            if type == 1 then
                local sub = tree:add(buffer(2,27),"OpenSession")
                sub:add(buffer(2,16),"AppUUID: "..uuid(buffer(2,16)))
                sub:add(buffer(18,4),"Timestamp: "..format_date(buffer(18,4):le_uint()))
                sub:add(buffer(22,4),"LogTag: "..buffer(22,4):le_uint())
                local dits = {[0] = "ByteArray", [1] = "Unsigned", [2] = "Integer"}
                sub:add(buffer(26,1),"DataItemType: "..dits[buffer(26,1):uint()].."["..buffer(26,1):uint().."]")
                sub:add(buffer(27,2),"DataItemSize: "..buffer(27,2):le_uint())
            elseif type == 2 then
                tree:add(buffer(2,4),"ItemsLeft: "..buffer(2,4):le_uint())
                tree:add(buffer(6,4),"DataCRC: "..buffer(6,4))
                data:call(buffer(10):tvb(),pinfo,tree)
            end
        else
       	    pinfo.cols.info:append(" ("..log_type[type > 127 and type - 128 or type]..")")
            if type == 0x84 then
                local sub = tree:add(buffer(1),"Open Sessions["..(buffer:len()-1).."]")
                for i=1,buffer:len() do
                    sub:add(buffer(i,1),"Session "..buffer(i,1))
                end
            elseif type == 0x0a or type == 0x8b then
                tree:add(buffer(1,1),"Enabled: "..buffer(1,1))
            end
        end
    end
	},
 [8000] = {
	name = "SCREENSHOT"
	},
 [9000] = {
    name = "GETBYTES",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        tree:add(buffer(1,1),"TransactionID: "..buffer(1,1))
        local types = {"CoredumpRequest","InfoResponse","DataResponse","FileRequest","FlashRequest","UnreadCoredumpRequest"}
        pinfo.cols.info:append(" ("..buffer(1,1)..":"..types[type+1]..")")
        if type == 1 then
            local errs = {"Success","MalformedRequest","InProgress","DoesNotExist","Corrupted"}
            local err = buffer(2,1):uint()
            pinfo.cols.info:append(" ["..errs[err+1].."]")
            tree:add(buffer(2,1),"Status: "..errs[err+1].."["..err.."]")
            tree:add(buffer(3,4),"Length: "..buffer(3,4):uint())
        elseif type == 2 then
            tree:add(buffer(2,4),"Offset: "..buffer(2,4):uint())
            data:call(buffer(6):tvb(),pinfo,tree)
        elseif type == 3 then
            tree:add(buffer(2),"Filename: "..buffer(3,buffer(2,1):uint()):stringz(ENC_UTF8))
        elseif type == 4 then
            tree:add(buffer(2,4),"Offset: "..buffer(2,4):uint())
            tree:add(buffer(6,4),"Length: "..buffer(6,4):uint())
        end
    end

  },
  [10000] = {
    name = "AUDIO",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        tree:add(buffer(1,2),"SessionID: "..buffer(1,2))
        pinfo.cols.info:append(" ("..(type == 2 and "Data" or "Stop")..":"..buffer(1,2)..")")
        if type == 2 then
            local fc = buffer(3,1):uint()
            local sub = tree:add(buffer(3),"Frames["..fc.."]")
            data:call(buffer(4):tvb(),pinfo,sub)
        end
    end
  },
  [11000] = {
    name = "VOICE",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        local types = {"SessionSetup","DictationResult"}
        tree:add(pebble_type, buffer(0,1))
        tree:add(buffer(1,4),"Flags: "..buffer(1,4))
        pinfo.cols.info:append(" ("..types[type]..")")
        if type == 1 and buffer:len() > 7 then
            tree:add(buffer(5,1),"SessionType: "..buffer(5,1):uint())
            tree:add(buffer(6,2),"Session ID: "..buffer(6,2):uint())
        else
            local cmd = {"SessionSetup","DictationResult"}
            local res = {"Success","ServiceUnavailable","Timeout","RecognizerError","InvalidResponse","Disabled","InvalidMessage"}
            tree:add(buffer(5,1),"SessionType: "..cmd[buffer(5,1):uint()].."["..buffer(5,1):uint().."]")
            tree:add(buffer(5,1),"SetupResult: "..res[buffer(6,1):uint()+1].."["..buffer(6,1):uint().."]")
        end
    end
  },
  [11440] = {
        name = "ACTION"
  },
  [43981] = {
        name = "SORTING"
  },
  [45531] = {
	name = "BLOB_DB",
    dissector = function(buffer,pinfo,tree) 
        if buffer:len() == 3 then
            tree:add(buffer(0,2),"Token: "..buffer(0,2))
            tree:add(buffer(2,1),"Status: "..blobSts[buffer(2,1):uint()].."["..buffer(2,1).."]")
            pinfo.cols.info:append(" "..buffer(0,2).." ("..blobSts[buffer(2,1):uint()]..")")
            return
        end
       	local type = buffer(0,1):uint()
       	tree:add(pebble_type, buffer(0,1))
       	tree:add(buffer(1,2),"Token: "..buffer(1,2))
       	local blob = buffer(3,1):uint()
        local b = blobs[blob]
        local c = blobCmd[type]
       	pinfo.cols.info:append(" "..buffer(1,2).." ("..b.name..":"..c.name..")")
        if c.dissector then
            c.dissector(buffer(4),pinfo,tree,blob)
        end
    end
	},
  [45787] = {
        name = "BLOB_UPDATE"
  },
  [48879] = {
    name = "PUTBYTES",
    dissector = function(buffer,pinfo,tree)
        local type = buffer(0,1):uint()
        tree:add(pebble_type, buffer(0,1))
        if buffer:len() == 5 and type < 3 then
            local res = {"ACK","NACK"}
            pinfo.cols.info:append(" (" .. res[type] .. ")")
            tree:add(buffer(1,4),"Cookie: "..buffer(1,4))
            return 5
        end
        local cmds = {"Init","Put","Commit","Abort","Install"}
        pinfo.cols.info:append(" (" .. cmds[type] .. ")")
        if type == 1 then
            tree:add(buffer(1,4),"Object Size: "..buffer(1,4):uint())
            local types = {"Firmware","Recovery","SysResource","AppResource","AppBinary","File","Worker"}
            local app = buffer(5,1):bitfield(0)
            local objt = buffer(5,1):uint()
            objt = app and objt - 128 or objt
            local objn = types[objt] or "Unknown"
            tree:add(buffer(5,1),"Object Type: "..objn.."["..objt.."] - "..(app and "AppBundle" or "SysBundle"))
            if app then
                tree:add(buffer(6,4),"AppID: "..buffer(6,4):uint())
            else
                tree:add(buffer(6,1),"Bank: "..buffer(6,1):uint())
                tree:add(buffer(7),"FileName: "..buffer(7):stringz(ENC_UTF8))
            end
        else
            tree:add(buffer(1,4),"Cookie: "..buffer(1,4))
            if type == 2 then
                local size = buffer(5,4):uint()
                tree:add(buffer(5,4),"Data Size: "..size)
                data:call(buffer(9,(size < (buffer:len() - 9)) and size or nil):tvb(),pinfo,tree)
            elseif type == 3 then
                tree:add(buffer(5,4),"Data CRC: "..buffer(5,4))
            end
        end
    end
  }
}
local frag = {}
local pkts = {}
local pidx = {}
local pkep = {}
function pebble_proto.init()
    frag = {}
    pkts = {}
    pidx = {}
    pkep = {}
end
local f_dir = Field.new("frame.p2p_dir")
local function prev(pinfo)
    local dir = tostring(f_dir())
    return pkts[dir][pidx[dir][pinfo.number]-1]
end
local function store(pinfo)
    local dir = tostring(f_dir())
    if not pidx[dir] then
        pidx[dir] = {}
        pkts[dir] = {}
    end
    if not pidx[dir][pinfo.number] then
        pkts[dir][#pkts[dir]+1] = pinfo.number
        pidx[dir][pinfo.number] = #pkts[dir]
    end
end
function pebble_proto.dissector(buffer,pinfo,tree)
    pinfo.cols.protocol:set("PEBBLE")
    local subtree = tree:add(pebble_proto, buffer())
    local blen = buffer:len()
    local off = 0

    if blen < 4 then
       pinfo.cols.info:set("ERROR: header too short")
       return
    end

    store(pinfo)

    if frag[prev(pinfo)] and frag[prev(pinfo)] > 0 then
        off = frag[prev(pinfo)]
        pinfo.cols.info:set("Continuation of the previous segment["..off..":"..blen.."]")
        if off - blen >= 0 then
            frag[pinfo.number] = off - blen
            return
        else
            subtree:add(buffer(0,off),"Trailing part of previous segment",buffer(0,off))
        end
    end

    pinfo.cols.info:set("")
    repeat
        local len = buffer(off,2):uint()
        local endpoint = buffer(off+2,2):uint()
    
    
        local ep = lookup_endpoint[endpoint]
        if not ep then
           ep = {name = "UNKNOWN", dissector=data}
        end
    
        subtree:add(pebble_endpoint, buffer(off+2,2))
        subtree:add(pebble_length, buffer(off,2))
    
        pinfo.cols.info:append(ep.name)
        pinfo.cols.info:append("[".. buffer(off+2,2) .."]")
        pinfo.cols.info:append(" Len:" .. len)
    
        if blen < off + len + 4 then
            frag[pinfo.number] = off + len + 4 - blen
            pinfo.cols.info:append(" ...")
            len = blen - 4 - off
        end
        local payload = subtree:add(buffer(off+4, len), ep.name, buffer(off+4, len))
    
        if ep.dissector then
           ep.dissector(buffer(off+4,len):tvb(),pinfo,payload)
        end
        off = off + 4 + len
        if blen - off > 0 then
            pinfo.cols.info:append(" | ")
        end
    until off >= blen
    return blen
end
--]]
local rfcomm_table = DissectorTable.get("btrfcomm.dlci")
rfcomm_table:add_for_decode_as(pebble_proto)
rfcomm_table:add(2,pebble_proto)

