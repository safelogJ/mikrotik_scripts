# Twitch Multi-Quality Traffic Generator for MikroTik v7
# Скрипт качает все доступные варианты качества одновременно.

:local channelName "rflib_ru"
:local appId "kimne78kx3ncx6brgo4mv6wki5h1ko"
:local history ({})
:local maxHistory 300

# --- ФУНКЦИЯ ПОЛУЧЕНИЯ ВСЕХ ПЛЕЙЛИСТОВ ---
:local getTwitchPlaylists do={
    :local channel $1
    :local client $2
    :log info "Twitch: Requesting multi-quality access token..."

    :local chars "abcdefghijklmnopqrstuvwxyz0123456789"
    :local deviceId ""
    :for i from=1 to=32 do={
        :local charPos [:rndnum from=0 to=35]
        :set deviceId ($deviceId . [:pick $chars $charPos ($charPos + 1)])
    }

    :local gqlUrl "https://gql.twitch.tv/gql"
    :local gqlData "{\"operationName\":\"PlaybackAccessToken_Template\",\"query\":\"query PlaybackAccessToken_Template(\$login: String!, \$isLive: Boolean!, \$vodID: ID!, \$isVod: Boolean!, \$playerType: String!, \$platform: String!) {  streamPlaybackAccessToken(channelName: \$login, params: {platform: \$platform, playerBackend: \\\"mediaplayer\\\", playerType: \$playerType}) @include(if: \$isLive) {    value    signature   authorization { isForbidden forbiddenReasonCode }   __typename  }  videoPlaybackAccessToken(id: \$vodID, params: {platform: \$platform, playerBackend: \\\"mediaplayer\\\", playerType: \$playerType}) @include(if: \$isVod) {    value    signature   __typename  }}\",\"variables\":{\"isLive\":true,\"login\":\"$channel\",\"isVod\":false,\"vodID\":\"\",\"playerType\":\"site\",\"platform\":\"web\"}}"

    :do {
        :local gqlResponse ([/tool fetch url=$gqlUrl http-method=post http-data=$gqlData \
            http-header-field="Client-ID: $client,X-Device-Id: $deviceId,Origin: https://www.twitch.tv,Referer: https://www.twitch.tv/,Content-Type: text/plain;charset=UTF-8" \
            check-certificate=no output=user as-value]->"data")

        :local jsonData [:deserialize $gqlResponse from=json]
        :local tokenData (($jsonData->"data")->"streamPlaybackAccessToken")
        :local token ($tokenData->"value")
        :local sig ($tokenData->"signature")

        :if ([:len $token] > 0) do={
            :local cleanToken ""
            :for i from=0 to=([:len $token] - 1) do={
                :local char [:pick $token $i ($i + 1)]
                :if ($char = "\"") do={ :set cleanToken ($cleanToken . "%22") } else={ :set cleanToken ($cleanToken . $char) }
            }

            :local usherUrl "https://usher.ttvnw.net/api/channel/hls/$channel.m3u8\?client_id=$client&token=$cleanToken&sig=$sig&allow_source=true&allow_audio_only=true&type=any"
            :local masterPlaylist ([/tool fetch url=$usherUrl check-certificate=no output=user as-value]->"data")

            # БЕЗОПАСНЫЙ СБОР ВСЕХ ССЫЛОК (фикс бесконечного цикла)
            :local allUrls ({})
            :local searchPos 0
            :local urlStart [:find $masterPlaylist "https://" $searchPos]

            :while ([:len $urlStart] > 0) do={
                :local urlEnd [:find $masterPlaylist "\n" $urlStart]
                :local actualEnd $urlEnd
                :if ([:len $urlEnd] = 0) do={ :set actualEnd [:len $masterPlaylist] }

                :local foundUrl [:pick $masterPlaylist $urlStart $actualEnd]
                :if ([:pick $foundUrl ([:len $foundUrl]-1)] = "\r") do={ :set foundUrl [:pick $foundUrl 0 ([:len $foundUrl]-1)] }

                :set ($allUrls->([:len $allUrls])) $foundUrl

                :if ([:len $urlEnd] = 0) do={
                    :set urlStart ""
                } else={
                    :set searchPos ($urlEnd + 1)
                    :set urlStart [:find $masterPlaylist "https://" $searchPos]
                }
            }
            :return $allUrls
        }
    } on-error={ :log error "Twitch: Auth Failed" }
    :return ({})
}

# --- ОСНОВНОЙ ЦИКЛ ---
:local playlists ({})

:log warning "Twitch MULTI-STREAM: Service started for channel $channelName"

:while (true) do={
    :if ([:len $playlists] = 0) do={
        :set playlists [$getTwitchPlaylists $channelName $appId]
        :if ([:len $playlists] = 0) do={ :delay 10s } else={
            :log warning ("Twitch: Monitoring " . [:len $playlists] . " quality streams.")
        }
    }

    :if ([:len $playlists] > 0) do={
        :local sessionError false

        :foreach pUrl in=$playlists do={
            :do {
                :local content ([/tool fetch url=$pUrl check-certificate=no output=user as-value]->"data")

                # ОПТИМИЗИРОВАННЫЙ ПОИСК СЕГМЕНТОВ
                :local sPos 0
                :local segmentStart [:find $content "https://" $sPos]

                :while ([:len $segmentStart] > 0) do={
                    :local segmentEnd [:find $content "\n" $segmentStart]
                    :local actualEnd $segmentEnd
                    :if ([:len $segmentEnd] = 0) do={ :set actualEnd [:len $content] }

                    :local segmentUrl [:pick $content $segmentStart $actualEnd]
                    :if ([:pick $segmentUrl ([:len $segmentUrl]-1)] = "\r") do={ :set segmentUrl [:pick $segmentUrl 0 ([:len $segmentUrl]-1)] }

                    # ФИЛЬТР: Качаем только если это ссылка на видео-сегмент (.ts)
                    :if ([:find $segmentUrl ".ts" 0] > 0) do={
                        :if ([:len [:find $history $segmentUrl]] = 0) do={
                            :do {
                                /tool fetch url=$segmentUrl check-certificate=no keep-result=no
                                :set ($history->([:len $history])) $segmentUrl
                                if ([:len $history] > $maxHistory) do={ :set history [:pick $history 1 [:len $history]] }
                            } on-error={
                                :log warning "Twitch: Segment fetch FAILED (Network issue)"
                            }
                        }
                    }

                    :if ([:len $segmentEnd] = 0) do={
                        :set segmentStart ""
                    } else={
                        :set sPos ($segmentEnd + 1)
                        :set segmentStart [:find $content "https://" $sPos]
                    }
                }
            } on-error={ :set sessionError true }
        }

        :if ($sessionError) do={
            :log error "Twitch: Session expired, refreshing..."
            :set playlists ({})
            :set history ({})
            :delay 5s
        }

        :delay 2s
    }
}
