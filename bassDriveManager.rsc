:global bassDriveCurrentShow
:global bassDriveStartFile
:local scriptRecorder "bassDriveRecorder"
:local diskSlot "usb1"
:local folder ($diskSlot . "/bassDrive/")

:local freeSpace (([/disk print as-value where slot=$diskSlot]->0)->"free")
:if ([:len "$freeSpace"] = 0) do={
    :log warning ("disk unavailable: " . $diskSlot . " script " . $scriptRecorder . " stopped")
    /system script job remove [find script=$scriptRecorder]
    :quit
}

# проверить свободное место, минимально допустимое свободное место (100 MB)
:if ($freeSpace < 104857600) do={
    :log warning ("low disk space on " . $diskSlot . "script " . $scriptRecorder . " stopped")
    /system script job remove [find script=$scriptRecorder]
    :quit
}

# start parse title block

:local rawTitle
:do {
    :set rawTitle [/tool fetch url="https://bassdrive.com/now-playing.php" output=user as-value]
} on-error={
    :log warning ("get now-playing show failed " . "script " . $scriptRecorder . " stopped")
    /system script job remove [find script=$scriptRecorder]
    :quit
}

:local html ($rawTitle->"data")
:local spanPos [:find $html "<span"]
:local newShow "Unknown BassDrive Show"

:if ([:len "$spanPos"] > 0) do={
    :set newShow [:pick $html 0 $spanPos]
}

# end parse title block

:local sanitizeShow
:set sanitizeShow do={
    :local input $1
    :local allowed "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_- "
    :local title ""
    :for i from=0 to=([:len $input] - 1) do={
        :local c [:pick $input $i ($i + 1)]
        :if ($allowed ~ $c) do={
            :set title ($title . $c)
        }
    }

    :while (([:len $title] > 0) && ([:pick $title ([:len $title] - 1)] = " ")) do={
        :set title [:pick $title 0 ([:len $title] - 1)]
    }
    :return $title
}

:local cleanName [$sanitizeShow $newShow]
#:log info ("BassDrive current show: " . $newShow . "clean: " . $cleanName)
:local date ([/system clock get date] . "/")
:local newFileName ($folder . $date . $cleanName . ".mp3")
:local finalName $newFileName
:local counter 1
:while ([:len [/file find name=$finalName]] > 0) do={
    :set finalName ($folder . $date . $cleanName . "_" . $counter . ".mp3")
    :set counter ($counter + 1)
    }

:if ([:len [/system script job find script=$scriptRecorder]] = 0) do={
    :set bassDriveStartFile ($folder . "bassDriveLive.mp3")
    :set bassDriveCurrentShow $newShow
    /system script run $scriptRecorder

} else={
   :if ($bassDriveCurrentShow != $newShow) do={
        /system script job remove [find script=$scriptRecorder]
        :log info "bassDrive new show started"
        :set bassDriveCurrentShow $newShow
        /system script run $scriptRecorder
    } else={
       :if ([:len [/file find name=$bassDriveStartFile]] > 0) do={
        /file set name=$finalName $bassDriveStartFile
       }
    }
}