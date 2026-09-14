#  copy /b *.ts merged.ts
# ffmpeg -i merged.ts -c copy ready_video.mp4
# "C:\Users\attl\Downloads\ffmpeg.exe" -i merged.ts -c copy ready_video.mp4

:local iptvBaseUrl "https://river-1.rutube.ru/stream/genetta-403.ntv.rutube.ru/UWYfUhDIrv26fBSdtggbPw/1781706410/392b4686b770bae2da6bf5ac4574add5/"
:local iptvListUrl ($iptvBaseUrl . "1080p_stream.m3u8")
:local ftpAddress "192.168.88.28"
:local login "netRecorder"
:local downloadedList [:toarray ""]


:local getFolderPath do={
    :local sDate [/system clock get date]
    :return ("hd_iptv_channel/" . [:pick $sDate 0 4] . [:pick $sDate 5 7] . [:pick $sDate 8 10])
}
:local videoDateFolder [$getFolderPath]
:do {
    :local playlistContent
    :local startPosTsLink
    :local endPosTsLink
    :local hasChunks true
    :local hasChunk true
    :local playlistDelay 1
    :while ($hasChunks) do={
        :delay $playlistDelay
        :set playlistContent ([/tool fetch url=$iptvListUrl output=user as-value]->"data")
        :local searchPosPointer 0
        :local startPosTsLink [:find $playlistContent ("1080p/seg") $searchPosPointer]
        :if ([:len $startPosTsLink] = 0) do={
            :log info ("No Links in List")
            :set hasChunks false
            :set hasChunk false
        } else={
            :set hasChunk true
        }
        :local downloadedCount 0
        :while ($hasChunk) do={
            :local endPosTsLink [:find $playlistContent "\n" $startPosTsLink]
            :local segmentFile [:pick $playlistContent $startPosTsLink $endPosTsLink]
            :local isDownloaded [:find $downloadedList $segmentFile]
            :if ([:len $isDownloaded] = 0) do={
                :set videoDateFolder [$getFolderPath]
                :local chunkFileLocalPath ($videoDateFolder . "/" . $segmentFile)
                /file remove [/file find where name~"^ramDisk/"]
                :local uploadFile [:pick $segmentFile 6 [:len $segmentFile]]
                :local bufferPath ("ramDisk/" . $uploadFile)
                :local chunkFileUrl ($iptvBaseUrl . $segmentFile)
                :log warning ("Downloading: " . $chunkFileUrl)
                :do {
                    :delay 200ms
                    /tool fetch url=$chunkFileUrl dst-path=$bufferPath keep-result=yes
                    :set downloadedCount ($downloadedCount + 1)
                    :set downloadedList ($downloadedList , $segmentFile)

                    # Ограничиваем массив, например, последними 100 чанками
                    :local listLen [:len $downloadedList]
                    :if ($listLen > 100) do={
                    # Отрезаем самый старый первый элемент, оставляя в массиве только свежие 100 штук
                        :set downloadedList [:pick $downloadedList 1 $listLen]
                    }

                    #:log warning ("Uploading: " . $uploadFile)
                    /tool fetch address="$ftpAddress" src-path="$bufferPath" user="$login" password="$login" port=8021 upload=yes mode=ftp dst-path="$uploadFile"
                } on-error={
                    :log warning ("Failed to download chunk: " . $chunkFileUrl)
                }
            } else={
                #:log warning ("HAS " . $segmentFile)
            }

            :set searchPosPointer ($endPosTsLink + 1)
            :set startPosTsLink [:find $playlistContent ("1080p/seg") $searchPosPointer]
            :if ([:len $startPosTsLink] = 0) do={
                :log info ("End Links")
                :set hasChunk false
            }
        }
        :if ($hasChunks) do={
            :if ($downloadedCount > 0) do={
                :local calculatedDelay (10 - (2 * $downloadedCount))
                :if ($calculatedDelay < 2) do={
                    :set calculatedDelay 200ms
                }
                :set playlistDelay $calculatedDelay
                :log info "HLS_Parser: Downloaded $downloadedCount chunks. Next playlist check in $playlistDelay s."
            } else={
                :set playlistDelay 10
                :log info "HLS_Parser: No NEW chunks in playlist. Cooling down for 10s."
            }
        }
    }
    :log info "HLS_Parser: All segments from current playlist verified."
} on-error={
    :log error ("HLS_Parser ERROR: ")
}