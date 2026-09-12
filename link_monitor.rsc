:global lastLinkState
:local botToken "8890000023:AAEZdgsfgfdgfdgdfgfdgfdAhHdA53ho"
:local userId 520000037
:local monitoredPort "bridge_wifi5virt2"
:local status ""

:local currentState [/interface/get [find name=$monitoredPort] running]
:if ([:len $lastLinkState] = 0) do={
    :set lastLinkState $currentState
    :quit
}
:if ($currentState != $lastLinkState) do={
    :if ($currentState) do={
        :set status "Link+Monitor:+Port+$monitoredPort+is+UP+(Cable+plugged)"
        :log warning $status
    } else={
        :set status "Link+Monitor:+Port+$monitoredPort+is+DOWN!+(Cable+unplugged)"
        :log error $status
    }
    :set lastLinkState $currentState
    /tool fetch url="https://api.telegram.org/bot$botToken/sendMessage\?chat_id=$userId&text=$status" keep-result=no
}