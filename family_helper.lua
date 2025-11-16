-- Family Helper (Final Arizona Edition)
-- Version: v1.3
-- FULLY compatible with MoonLoader 0.26.5-beta (Arizona Launcher)
-- NO sampev, NO samparsen, NO imgui.new — safe mode

local imgui = require("imgui")
local json  = require("json")
local http  = require("socket.http")
local ltn12 = require("ltn12")
local lfs   = require("lfs")

---------------------------
-- CONFIG
---------------------------
local MY_FAMILY_ID = 5                 -- Твой ID семьи
local currentVersion = "v1.3"

-- GitHub URLs
local versionCheckURL   = "https://raw.githubusercontent.com/username/repo/main/version.txt"
local scriptDownloadURL = "https://raw.githubusercontent.com/username/repo/main/family_helper.lua"
local accessListURL     = "https://raw.githubusercontent.com/username/repo/main/access_list.json"

-- Discord webhook (если пусто — лог отключён)
local discordWebhookURL = ""

-- Paths
local scriptName = "family_helper.lua"
local scriptPath = getWorkingDirectory() .. "\\" .. scriptName

local configFolder = getWorkingDirectory() .. "\\Retex Helper Family\\"
local configPath   = configFolder .. "family_helper_config.json"

---------------------------
-- STATE
---------------------------

local windowFH = false     -- меню /fh
local windowFLM = false    -- меню /flm

local showUpdatePopup = false
local showRestartPopup = false
local updateText = ""

local selected_tab = "Информация"

local accessList = {}
local accessVerified = false
local accessCodeEntered = ""

local keybinds = {}
local bind_keys = { "F1","F2","F3","F4","F5","F6" }
local bind_selected = 1
local bind_command = ""

local selectedPlayer = {
    id = 0, nick = "",
    rank = 0, warns = 0,
    inFamily = false, vip = false
}

local my_family_id = 0

-- Новости
local newsList = {
    "Добро пожаловать в Retex Dynasty!",
    "Следите за обновлениями — вкладка 'Обновления'.",
    "Исправлены ошибки и улучшена стабильность."
}

-- Обновления
local updatesList = {
    "v1.0 — Релиз",
    "v1.1 — Добавлено меню FLM",
    "v1.2 — Авторизация GitHub",
    "v1.3 — Полная совместимость с Arizona ML"
}

---------------------------
-- Utils
---------------------------

function ensureConfigFolder()
    local attr = lfs.attributes(configFolder)
    if not attr then
        lfs.mkdir(configFolder)
        sampAddChatMessage("[FamilyHelper] Создана папка настроек", 0x66CCFF)
    end
end

function saveConfig()
    ensureConfigFolder()
    local f = io.open(configPath, "w+b")
    if not f then
        sampAddChatMessage("[FamilyHelper] Ошибка сохранения настроек!", 0xFF3333)
        return
    end
    f:write(json.encode({ keybinds = keybinds }))
    f:close()
    sampAddChatMessage("[FamilyHelper] Настройки сохранены", 0x00FF00)
end

function loadConfig()
    ensureConfigFolder()
    local f = io.open(configPath, "r")
    if not f then return end

    local data = f:read("*all")
    f:close()

    local ok, cfg = pcall(json.decode, data)
    if ok and cfg and cfg.keybinds then
        keybinds = cfg.keybinds
        sampAddChatMessage("[FamilyHelper] Настройки загружены", 0x00FF00)
    end
end

---------------------------
-- HTTP / Discord
---------------------------

function httpGet(url)
    local resp = {}
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(resp)
    }
    if code == 200 then
        return table.concat(resp)
    end
    return nil
end

function sendDiscord(msg)
    if discordWebhookURL == "" then return end

    local data = '{"content":"' .. msg:gsub('"','\\"') .. '"}'
    http.request{
        url = discordWebhookURL,
        method = "POST",
        headers = {["Content-Type"]="application/json",["Content-Length"]=#data},
        source = ltn12.source.string(data),
        sink = ltn12.sink.null()
    }
end

---------------------------
-- Access Control
---------------------------

function fetchAccessList()
    local raw = httpGet(accessListURL)
    if not raw then
        sampAddChatMessage("[FamilyHelper] Не удалось загрузить access_list.json", 0xFF3333)
        return
    end

    local ok, parsed = pcall(json.decode, raw)
    if ok then
        accessList = parsed
        sampAddChatMessage("[FamilyHelper] Список доступа загружен", 0x00FF00)
    end
end

function checkAccess(nick, code)
    for _,entry in ipairs(accessList) do
        if entry.nick == nick and entry.code == code then
            return true
        end
    end
    return false
end

---------------------------
-- UPDATES
---------------------------

function fetchLatestVersionAndChangelog()
    local raw = httpGet(versionCheckURL)
    if not raw then return nil, nil end
    local latest = raw:match("Version:%s*(%S+)")
    local changelog = raw:match("Changelog:(.+)") or ""
    return latest, changelog
end

function downloadAndUpdateScript()
    local raw = httpGet(scriptDownloadURL)
    if not raw then
        sampAddChatMessage("[FamilyHelper] Ошибка скачивания обновления", 0xFF3333)
        return false
    end
    local f, err = io.open(scriptPath, "w+b")
    if not f then
        sampAddChatMessage("[FamilyHelper] Ошибка записи файла: "..tostring(err), 0xFF3333)
        return false
    end
    f:write(raw)
    f:close()
    showRestartPopup = true
    sampAddChatMessage("[FamilyHelper] Обновление скачано. Перезапустите игру для установки.", 0x00FF00)
    return true
end

---------------------------
-- DRAW: popups
---------------------------

function drawUpdatePopup()
    if not showUpdatePopup then return end
    imgui.SetNextWindowSize(imgui.ImVec2(480,360), imgui.Cond.Appearing)
    if imgui.Begin("Доступна новая версия") then
        imgui.TextWrapped(updateText)
        imgui.Separator()
        if imgui.Button("Закрыть") then showUpdatePopup = false end
        imgui.SameLine()
        if imgui.Button("Скачать и установить") then
            downloadAndUpdateScript()
            showUpdatePopup = false
        end
        imgui.End()
    end
end

function drawRestartPopup()
    if not showRestartPopup then return end
    imgui.SetNextWindowSize(imgui.ImVec2(420,140), imgui.Cond.Appearing)
    if imgui.Begin("Перезапуск") then
        imgui.TextWrapped("Файл обновлён. Перезапустите игру для завершения установки.")
        imgui.Separator()
        if imgui.Button("Закрыть") then showRestartPopup = false end
        imgui.End()
    end
end

---------------------------
-- DRAW: FH (main menu)
---------------------------

function drawMenuFH()
    if not windowFH then return end
    imgui.SetNextWindowSize(imgui.ImVec2(520,460), imgui.Cond.FirstUseEver)
    if imgui.Begin("Family Helper — /fh", windowFH) then
        -- top buttons act as tabs
        if imgui.Button("Информация") then selected_tab = "Информация" end
        imgui.SameLine()
        if imgui.Button("Биндеры") then selected_tab = "Биндеры" end
        imgui.SameLine()
        if imgui.Button("Новости") then selected_tab = "Новости" end
        imgui.SameLine()
        if imgui.Button("Обновления") then selected_tab = "Обновления" end

        imgui.Separator()

        if selected_tab == "Информация" then
            imgui.Text("Никнейм: " .. (selectedPlayer.nick ~= "" and selectedPlayer.nick or "-"))
            imgui.Text("ID: " .. (selectedPlayer.id ~= 0 and tostring(selectedPlayer.id) or "-"))
            imgui.Text("Ранг: " .. tostring(selectedPlayer.rank))
            imgui.Text("Член семьи: " .. (selectedPlayer.inFamily and "Да" or "Нет"))
            imgui.Text("VIP: " .. (selectedPlayer.vip and "Да" or "Нет"))
            imgui.Text("Предупреждения: " .. tostring(selectedPlayer.warns))
        elseif selected_tab == "Биндеры" then
            imgui.Text("Команда (например: /faminvite [ID]):")
            local new_cmd = imgui.InputText("Команда", bind_command)
            if new_cmd then bind_command = new_cmd end
            imgui.Text("Выберите клавишу:")
            for i,k in ipairs(bind_keys) do
                if imgui.RadioButton(k, bind_selected_index == i) then bind_selected_index = i end
                imgui.SameLine()
            end
            imgui.NewLine()
            if imgui.Button("Назначить биндер") then
                local key = bind_keys[bind_selected_index]
                if bind_command and bind_command ~= "" then
                    keybinds[key] = bind_command
                    saveConfig()
                    sampAddChatMessage("[FamilyHelper] Биндер "..key.." -> "..bind_command, 0x00FF00)
                else
                    sampAddChatMessage("[FamilyHelper] Укажите команду для бинда", 0xFF3333)
                end
            end
            imgui.Separator()
            imgui.Text("Активные биндеры:")
            for k,cmd in pairs(keybinds) do imgui.Text(k.." -> "..cmd) end
        elseif selected_tab == "Новости" then
            imgui.Text("Новости семьи:")
            imgui.Separator()
            for i, n in ipairs(newsList) do imgui.Text("- "..n) end
        elseif selected_tab == "Обновления" then
            imgui.Text("Обновления скрипта:")
            imgui.Separator()
            for i, u in ipairs(updatesList) do imgui.Text("- "..u) end
            imgui.Separator()
            if imgui.Button("Проверить обновления") then
                local latest, changelog = fetchLatestVersionAndChangelog()
                if latest and latest ~= currentVersion then
                    updateText = "Доступна версия: "..latest.."\nСписок изменений:\n"..changelog
                    showUpdatePopup = true
                else
                    sampAddChatMessage("[FamilyHelper] У вас последняя версия: "..currentVersion, 0x00FF00)
                end
            end
        end

        imgui.Separator()
        if imgui.Button("Закрыть") then windowFH = false end
        imgui.End()
    end
end

---------------------------
-- DRAW: FLM (actions menu)
---------------------------

function drawMenuFLM()
    if not windowFLM then return end
    imgui.SetNextWindowSize(imgui.ImVec2(420,380), imgui.Cond.FirstUseEver)
    if imgui.Begin("Family Helper — Actions", windowFLM) then
        if not accessVerified then
            imgui.Text("Доступ ограничен. Введите код доступа через диалог:")
            if imgui.Button("Открыть диалог ввода кода") then
                sampShowInputDialog("FamilyHelper","Введите код доступа:","",true,false)
            end
            imgui.Separator()
            if imgui.Button("Закрыть") then windowFLM = false end
            imgui.End()
            return
        end

        if validPlayer(selectedPlayer.id) then
            if imgui.Button("Уволить из семьи") then
                sampSetCurrentDialogEditboxText("/famuinvite "..selectedPlayer.id.." Причина")
                sendDiscord(selectedPlayer.nick.." уволен из семьи")
            end
            imgui.SameLine()
            if imgui.Button("Выдать ранг") then
                -- open a simple prompt via chat editbox - user can edit rank
                sampSetCurrentDialogEditboxText("/setfrank "..selectedPlayer.id.." 5")
                sendDiscord(selectedPlayer.nick.." выдан ранг 5")
            end
            imgui.SameLine()
            if imgui.Button("Предупреждение") then
                sampSetCurrentDialogEditboxText("/famwarn "..selectedPlayer.id.." Причина")
                sendDiscord(selectedPlayer.nick.." получил предупреждение")
            end

            imgui.Spacing()

            if imgui.Button("Снять мут") then
                sampSetCurrentDialogEditboxText("/famunmute "..selectedPlayer.id)
                sendDiscord(selectedPlayer.nick.." мут снят")
            end
            imgui.SameLine()
            if imgui.Button("Снять предупреждение") then
                sampSetCurrentDialogEditboxText("/famunwarn "..selectedPlayer.id.." Причина")
                sendDiscord(selectedPlayer.nick.." предупреждение снято")
            end
            imgui.SameLine()
            if imgui.Button("Выдать тег") then
                sampSetCurrentDialogEditboxText("/famtag "..selectedPlayer.id.." VIP")
                sendDiscord(selectedPlayer.nick.." получил тег VIP")
            end
        else
            imgui.Text("Игрок не выбран или ID неверный.")
        end

        imgui.Separator()
        if imgui.Button("Закрыть") then windowFLM = false end
        imgui.End()
    end
end

---------------------------
-- KEYBINDS & HOTKEY
---------------------------

function checkKeybinds()
    for k,cmd in pairs(keybinds) do
        local vk = nil
        if k == "F1" then vk = 0x70
        elseif k == "F2" then vk = 0x71
        elseif k == "F3" then vk = 0x72
        elseif k == "F4" then vk = 0x73
        elseif k == "F5" then vk = 0x74
        elseif k == "F6" then vk = 0x75
        end
        if vk and isKeyDown(vk) then
            local out = cmd
            out = out:gsub("%[ID%]", tostring(selectedPlayer.id))
            out = out:gsub("%[RANK%]", tostring(selectedPlayer.rank))
            out = out:gsub("%[NICK%]", selectedPlayer.nick)
            sampSetCurrentDialogEditboxText(out)
        end
    end
end

function checkHotkey()
    if isKeyDown(VK_RBUTTON) and isKeyDown(VK_E) then
        fetchAccessList()
        if requestAccessIfNeeded() and canOpenMenu() then windowFLM = true end
    end
    checkKeybinds()
end

---------------------------
-- DIALOG / SERVER callbacks
---------------------------

function onDialogResponse(dialogId, buttonId, list, input)
    if not input or input == "" then return end
    accessCodeEntered = input
    if #accessList == 0 then fetchAccessList() end
    if checkAccess(sampGetPlayerNickname(playerid), accessCodeEntered) then
        accessVerified = true
        sampAddChatMessage("[FamilyHelper] Доступ подтверждён", 0x00FF00)
        if canOpenMenu() then windowFLM = true end
    else
        accessCodeEntered = ""
        accessVerified = false
        sampAddChatMessage("[FamilyHelper] Неверный код доступа", 0xFF3333)
    end
end

function onServerMessage(color, msg)
    -- parse family id from server message like: "Семья: Retex Dynasty (ID: 5)"
    local id = msg:match("Семья: .- %(ID: (%d+)%)")
    if id then
        my_family_id = tonumber(id)
        -- don't spam chat, commented out; uncomment for debug:
        -- sampAddChatMessage("[FamilyHelper] Обновлён ID семьи: "..tostring(my_family_id), 0x66CCFF)
    end
end

---------------------------
-- CHAT commands
---------------------------

sampRegisterChatCommand("fh", function()
    fetchAccessList()
    if requestAccessIfNeeded() and canOpenMenu() then
        -- attempt to select nearest player if available
        local nearest = getNearestPlayer() or 0
        if validPlayer(nearest) then
            selectedPlayer.id = nearest
            selectedPlayer.nick = sampGetPlayerNickname(nearest)
        end
        windowFH = true
    end
end)

sampRegisterChatCommand("flm", function()
    fetchAccessList()
    if requestAccessIfNeeded() and canOpenMenu() then
        local nearest = getNearestPlayer() or 0
        if validPlayer(nearest) then
            selectedPlayer.id = nearest
            selectedPlayer.nick = sampGetPlayerNickname(nearest)
        end
        windowFLM = true
    end
end)
---------------------------
-- ACCESS / PERMISSIONS
---------------------------

-- Проверяем и уведомляем, что меню доступно только для нужной семьи
function canOpenMenu()
    if my_family_id == MY_FAMILY_ID then return true end
    sampAddChatMessage("[FamilyHelper] Этот скрипт предназначен для Retex Dynasty", 0xFF5555)
    return false
end

-- Запрашиваем код доступа (диалог) или проверяем уже введённый
function requestAccessIfNeeded()
    if accessVerified then return true end
    if not accessCodeEntered or accessCodeEntered == "" then
        -- показать системный диалог ввода (на который приходит onDialogResponse)
        sampShowInputDialog("FamilyHelper","Введите код доступа:","",true,false)
        return false
    end
    -- если код введён — проверяем в списке
    local nick = sampGetPlayerNickname(playerid)
    if checkAccess(nick, accessCodeEntered) then
        accessVerified = true
        sampAddChatMessage("[FamilyHelper] Доступ разрешён", 0x00FF00)
        return true
    else
        accessCodeEntered = ""
        accessVerified = false
        sampAddChatMessage("[FamilyHelper] Доступ запрещён: неправильный ник или код", 0xFF5555)
        return false
    end
end

---------------------------
-- AUTO-INVITE in radius
---------------------------

-- radius in game units (tweak as needed)
local AUTOINVITE_RADIUS = 2.0
local AUTOINVITE_ENABLED = true

-- Placeholder distance function — replace with server-specific coords if available.
-- getNearestPlayer() is a placeholder; if you have functions to get player coords, replace here.
function autoInviteNearby()
    if not AUTOINVITE_ENABLED then return end
    local pid = getNearestPlayer() or 0
    if not validPlayer(pid) then return end
    -- NOTE: This check assumes getNearestPlayer returns only players within radius.
    -- If your server exposes coordinates, compute actual distance here.
    -- Execute invite command
    sampSetCurrentDialogEditboxText("/faminvite " .. pid)
    sendDiscord(selectedPlayer.nick .. " auto-invited (id:"..tostring(pid)..")")
    sampAddChatMessage("[FamilyHelper] Автоинвайт исполнен для ID "..tostring(pid), 0x00FF00)
end

---------------------------
-- AUTO-RANK DETECTION (placeholder)
---------------------------

-- Реализация зависит от сервера: если у вас есть команда /fmembers, /stats с парсингом — нужно парсер.
-- Здесь даётся заглушка: вызовите эту функцию после заполнения selectedPlayer.id чтобы попытаться определить ранг.
function autoDetectRank(pid)
    -- TODO: заменить на реальный парсер:
    -- 1) отправьте /fmembers и перехватите onServerMessage чтобы распарсить строку с ником и цифровым рангом
    -- 2) присвойте selectedPlayer.rank = полученное_число
    -- Пока — оставляем как есть.
    return false
end

---------------------------
-- HIDE RANKS 9 & 10 for deputies
---------------------------

-- Возвращает true если текущий игрок (тот, кто использует скрипт) имеет право видеть/назначать 9/10
-- Реализуйте проверку на свой internal logic; пока заглушка: только лидер видит 10, зам - 9 скрыт
local MY_NUMERIC_RANK = 10 -- настройте: 10 - лидер, 9 - зам

function canSeeRankButton(targetRank)
    -- если юзер не лидер (10) то не показываем кнопки для 9 и 10
    -- нужно реализовать проверку ранга текущего игрока (текущий ранк: my_numeric_rank)
    local my_numeric_rank = MY_NUMERIC_RANK -- замените если у вас есть способ определять
    if my_numeric_rank < 9 and (targetRank == 9 or targetRank == 10) then
        return false
    end
    return true
end

---------------------------
-- COMMAND ALIASES & ACTIONS
---------------------------

-- Утилита для простого выполнения команды (вставляет в чат-редактор, чтобы пользователь подтвердил)
local function execCmdTemplate(template, pid, extra)
    extra = extra or ""
    if not validPlayer(pid) then
        sampAddChatMessage("[FamilyHelper] Неверный ID игрока", 0xFF3333)
        return
    end
    local cmd = template:gsub("{id}", tostring(pid)):gsub("{extra}", extra)
    sampSetCurrentDialogEditboxText(cmd)
    sendDiscord(cmd .. " (выполнено через FamilyHelper)")
end

-- Регистрация основных алиасов (локальные хуки, чтобы пользователь мог вызывать /fi, /frank и т.д.)
sampRegisterChatCommand("fi", function(arg)
    sampAddChatMessage("[FamilyHelper] Алиас /fi является псевдо-командой; используйте /faminvite или GUI", 0xAAAAFF)
end)

sampRegisterChatCommand("faminvite", function(arg)
    local id = tonumber(arg)
    if not id then
        sampAddChatMessage("Использование: /faminvite <id>", 0xFF3333)
        return
    end
    execCmdTemplate("/faminvite {id}", id)
end)

sampRegisterChatCommand("frank", function(arg)
    local pid, rank = arg:match("^(%d+)%s+(%d+)$")
    pid = tonumber(pid)
    rank = tonumber(rank)
    if not pid or not rank then
        sampAddChatMessage("Использование: /frank <id> <rank>", 0xFF3333)
        return
    end
    execCmdTemplate("/setfrank {id} "..rank, pid)
end)

sampRegisterChatCommand("famwarn", function(arg)
    local pid, reason = arg:match("^(%d+)%s+(.+)$")
    pid = tonumber(pid)
    if not pid or not reason then
        sampAddChatMessage("Использование: /famwarn <id> <причина>", 0xFF3333)
        return
    end
    execCmdTemplate("/famwarn {id} "..reason, pid)
end)

sampRegisterChatCommand("fammute", function(arg)
    local pid, time = arg:match("^(%d+)%s*(%d*)$")
    pid = tonumber(pid)
    if not pid then
        sampAddChatMessage("Использование: /fammute <id> <время>", 0xFF3333)
        return
    end
    execCmdTemplate("/fammute {id} "..(time ~= "" and time or "60"), pid)
end)

sampRegisterChatCommand("famunmute", function(arg)
    local pid = tonumber(arg)
    if not pid then
        sampAddChatMessage("Использование: /famunmute <id>", 0xFF3333)
        return
    end
    execCmdTemplate("/famunmute {id}", pid)
end)

sampRegisterChatCommand("famunwarn", function(arg)
    local pid, reason = arg:match("^(%d+)%s+(.+)$")
    pid = tonumber(pid)
    if not pid or not reason then
        sampAddChatMessage("Использование: /famunwarn <id> <причина>", 0xFF3333)
        return
    end
    execCmdTemplate("/famunwarn {id} "..reason, pid)
end)

sampRegisterChatCommand("famuinvite", function(arg)
    local pid = tonumber(arg)
    if not pid then
        sampAddChatMessage("Использование: /famuinvite <id>", 0xFF3333)
        return
    end
    execCmdTemplate("/famuinvite {id}", pid)
end)

sampRegisterChatCommand("famtag", function(arg)
    local pid, tag = arg:match("^(%d+)%s+(.+)$")
    pid = tonumber(pid)
    if not pid or not tag then
        sampAddChatMessage("Использование: /famtag <id> <tag>", 0xFF3333)
        return
    end
    execCmdTemplate("/famtag {id} "..tag, pid)
end)


---------------------------
-- BINDERS handling
---------------------------

-- call this in main loop to apply keybinds
function processKeybinds()
    for key, cmd in pairs(keybinds) do
        local vk = nil
        if key == "F1" then vk = 0x70
        elseif key == "F2" then vk = 0x71
        elseif key == "F3" then vk = 0x72
        elseif key == "F4" then vk = 0x73
        elseif key == "F5" then vk = 0x74
        elseif key == "F6" then vk = 0x75
        end
        if vk and isKeyDown(vk) then
            local out = cmd
            out = out:gsub("%[ID%]", tostring(selectedPlayer.id))
            out = out:gsub("%[NICK%]", selectedPlayer.nick)
            sampSetCurrentDialogEditboxText(out)
        end
    end
end
---------------------------
-- HOTKEY: ПКМ + E
---------------------------

local VK_RBUTTON = 0x02
local VK_E       = 0x45

function checkHotkeyFast()
    -- ПКМ + E ? открыть FLM
    if isKeyDown(VK_RBUTTON) and isKeyDown(VK_E) then
        fetchAccessList()

        if requestAccessIfNeeded() and canOpenMenu() then
            -- авто-выбор игрока
            local nearest = getNearestPlayer() or 0
            if validPlayer(nearest) then
                selectedPlayer.id = nearest
                selectedPlayer.nick = sampGetPlayerNickname(nearest)
            end
            windowFLM = true
        end
    end
end

---------------------------
-- PLAYER RESOLUTION
---------------------------

-- заглушка: можно заменить если у тебя есть получение координат
function getNearestPlayer()
    -- Вернуть ID ближайшего игрока
    -- Arizona Launcher НЕ предоставляет позицию, поэтому можно:
    -- 1) Использовать сторонний мод (SAMPFUNCS) — но его нет в AZ Launcher.
    -- 2) Использовать кастомный способ, если сервер отдаёт список.
    -- Пока оставим заглушку.
    return 0
end

function validPlayer(id)
    return id and tonumber(id) and id > 0 and id < 1000
end

---------------------------
-- MAIN IMGUI DRAW
---------------------------

function imgui.OnDrawFrame()
    checkHotkeyFast()
    processKeybinds()

    drawMenuFH()
    drawMenuFLM()
    drawUpdatePopup()
    drawRestartPopup()
end

---------------------------
-- MAIN
---------------------------

function main()
    repeat wait(100) until isSampAvailable()

    loadConfig()
    sampAddChatMessage("[FamilyHelper] Загружен (v"..currentVersion..")", 0x66CCFF)
    sampAddChatMessage("[FamilyHelper] Команда: /fh — главное меню", 0x66CCFF)
    sampAddChatMessage("[FamilyHelper] Команда: /flm — меню действий", 0x66CCFF)
    
    while true do
        wait(0)
        -- Здесь можно выполнять автоинвайт, если нужно постоянно
        -- autoInviteNearby()
    end
end

---------------------------
-- SERVER MESSAGE PARSE
---------------------------

function onServerMessage(color, msg)
    -- Пример строки: "Семья: Retex Dynasty (ID: 5)"
    local id = msg:match("Семья:%s*.-%(ID:%s*(%d+)%)")
    if id then
        my_family_id = tonumber(id)
    end
end

---------------------------
-- DIALOG RESPONSE (код доступа)
---------------------------

function onDialogResponse(dialogId, button, list, input)
    if not input or input == "" then return end

    accessCodeEntered = input
    if #accessList == 0 then fetchAccessList() end

    if checkAccess(sampGetPlayerNickname(playerid), accessCodeEntered) then
        accessVerified = true
        sampAddChatMessage("[FamilyHelper] Доступ подтверждён!", 0x00FF00)
        if canOpenMenu() then windowFLM = true end
    else
        accessCodeEntered = ""
        accessVerified = false
        sampAddChatMessage("[FamilyHelper] Неверный код доступа", 0xFF3333)
    end
end

---------------------------
-- END OF FILE
---------------------------
