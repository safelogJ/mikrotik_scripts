:local addressList "dolboeby"
:if ([:len $message] > 0) do={
    :local startPos [:find $message "from " 0]
    :if ([:len $startPos] > 0) do={
        :set startPos ($startPos + 5)
        :local endPos [:find $message " via" $startPos]
        :if ([:len $endPos] = 0) do={
            :set endPos [:len $message]
        }
        :local attackerIP [:pick $message $startPos $endPos]
        :if ([:len $attackerIP] > 7 && [:len [/ip firewall address-list find where address=$attackerIP list=$addressList]] = 0) do={
            /ip firewall address-list add list=$addressList address=$attackerIP timeout=2d comment=$message
        }
    }
}