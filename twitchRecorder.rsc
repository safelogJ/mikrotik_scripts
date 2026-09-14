:local channelName "rflib_ru"
:local appId "kimne78kx3ncx6brgo4mv6wki5h1ko"
:local playlistUrl ""
:local isBestQuality false
:local lastMasterCheck [/system clock get time]
:local history ({})
:local maxHistory 30

# Настройки FTP для записи
:local ftpAddress "192.168.88.28"
:local ftpUser "netRecorder"
:local ftpPass "netRecorder"
:local ftpPort 8021

# --- ФУНКЦИЯ ПОЛУЧЕНИЯ ПЛЕЙЛИСТА ---
:local getTwitchPlaylist do={
    :local channel $1
    :local client $2
    :log info "Twitch: Attempting to get new access token..."
    # Генерация Device-ID
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
            :local usherUrl "https://usher.ttvnw.net/api/channel/hls/$channel.m3u8\?client_id=$client&token=$token&sig=$sig&allow_source=true&allow_audio_only=false&type=any"
            :local masterPlaylist ([/tool fetch url=$usherUrl check-certificate=no output=user as-value]->"data")
            # ВЫВОД MASTER PLAYLIST В ЛОГ ДЛЯ ПРОВЕРКИ ВАРИАНТОВ КАЧЕСТВА
            #:log info "Twitch Master Playlist: $masterPlaylist"
            # Ищем маркер Source качества (обычно "chunked")
            :local searchPos [:find $masterPlaylist "chunked" 0]
            :local isSourceFound true
            # Если не нашли по слову chunked, ищем по 1080p
            :if ([:len $searchPos] = 0) do={
                :set searchPos [:find $masterPlaylist "1080p" 0]
            }
            # Если всё еще не нашли, значит Source сейчас недоступен
            :if ([:len $searchPos] = 0) do={
                :set searchPos 0
                :set isSourceFound false
            }
            # Находим саму ссылку после выбранной позиции
            :local start [:find $masterPlaylist "https://" $searchPos]
            :local end [:find $masterPlaylist "\n" $start]
            :local finalUrl [:pick $masterPlaylist $start $end]
            # Очистка от \r
            :if ([:pick $finalUrl ([:len $finalUrl]-1)] = "\r") do={ :set finalUrl [:pick $finalUrl 0 ([:len $finalUrl]-1)] }
            # Возвращаем массив: [0] - URL плейлиста, [1] - булево (лучшее ли качество)
            :return ({$finalUrl; $isSourceFound})
        }
    } on-error={
        :log error "Twitch: Auth function failed."
    }
    :return ({})
}
# --- ОСНОВНОЙ ЦИКЛ ---
:log warning "Twitch: Service started for channel $channelName"
:while (true) do={
    # ПРОВЕРКА: Если качество не лучшее (не Source), пробуем переподключиться каждые 5 минут
    :if ($isBestQuality = false && $playlistUrl != "") do={
        :local now [/system clock get time]
        :local currentMin [:pick $now 3 5]
        # Каждые 5 минут (00, 05, 10...) сбрасываем ссылку для поиска Source
        :if ($currentMin % 5 = 0) do={
            :log info "Twitch: Quality is low ($currentMin min). Re-checking master playlist for Source..."
            :set playlistUrl ""
            :delay 1s
        }
    }

    # Получение плейлиста
    :if ($playlistUrl = "") do={
        # Вызываем функцию и получаем массив с URL и флагом качества
        :local result [$getTwitchPlaylist $channelName $appId]
        :if ([:len $result] = 0) do={
            :log error "Twitch: Could not get playlist, retrying in 10s..."
            :delay 10s
        } else={
            # Теперь мы правильно устанавливаем флаг прямо из результатов поиска в функции
            :set playlistUrl ($result->0)
            :set isBestQuality ($result->1)
            :if ($isBestQuality) do={
                :log warning "Twitch: High Quality (Source) obtained."
            } else={
                :log warning "Twitch: Source not available. Using fallback quality."
            }
        }
    }

    # Цикл загрузки сегментов
    :if ([:len $playlistUrl] > 0) do={
        :do {
            :local content ([/tool fetch url=$playlistUrl check-certificate=no output=user as-value]->"data")
            :local searchPos 0
            :local lineEnd [:find $content "\n" $searchPos]
            :while ([:len $lineEnd] > 0) do={
                :local line [:pick $content $searchPos $lineEnd]
                # Очистка строки
                :if ([:pick $line ([:len $line] - 1)] = "\r") do={ :set line [:pick $line 0 ([:len $line] - 1)] }

                :if ([:pick $line 0 8] = "https://") do={
                    :if ([:len [:find $history $line]] = 0) do={
                        :do {
                            /file remove [/file find where name~"^ramDisk/"]
                            :local sTime [/system clock get time]
                            :local cleanTime ([:pick $sTime 0 2] . [:pick $sTime 3 5] . [:pick $sTime 6 8])
                            :local fileName ($channelName . "_" . $cleanTime . ".ts")
                            :local bufferPath ("ramDisk/" . $fileName)

                            /tool fetch url=$line dst-path=$bufferPath keep-result=yes check-certificate=no

                            # Передача на FTP с mode=ftp в начале
                            /tool fetch mode=ftp address=$ftpAddress port=$ftpPort user=$ftpUser password=$ftpPass \
                                src-path=$bufferPath dst-path=$fileName upload=yes

                            :set ($history->([:len $history])) $line
                            :if ([:len $history] > $maxHistory) do={ :set history [:pick $history 1 [:len $history]] }
                        } on-error={ :log warning "Twitch: File skip (Net/FTP)" }
                    }
                }
                :set searchPos ($lineEnd + 1)
                :set lineEnd [:find $content "\n" $searchPos]
            }
            :delay 2s
        } on-error={
            :log error "Twitch: Playlist error or expired. Resetting session..."
            :set playlistUrl ""
            :set isBestQuality false
            :set history ({})
            :delay 5s
        }
    }
}
