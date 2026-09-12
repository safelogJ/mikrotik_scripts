:global bassDriveStartFile
:if ([:len [/file find name=$bassDriveStartFile]] > 0) do={
    /file remove [find name=$bassDriveStartFile]
}
/tool fetch url="https://chi2.bassdrive.net/stream" dst-path=$bassDriveStartFile

# https://chi2.bassdrive.net/stream
# https://bassdrive.radioca.st/stream
# https://au.bassdrive.co/stream
# https://ice.bassdrive.net/stream
# https://ice.bassdrive.net/stream32
# https://ice.bassdrive.net/stream56