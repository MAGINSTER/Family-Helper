require('lib.moonloader')
local imgui = require("mimgui")
local encoding = require('encoding')
local requests = require("requests")

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new = imgui.new

local window = new.bool()
local sizeX, sizeY = getScreenResolution()
local menu = 1

-- 🔧 текущая версия
local CURRENT_VERSION = "1.0.3"

-- 🔧 проверка и автообновление
function checkUpdates()
    lua_thread.create(function()
        local url_version = "https://raw.githubusercontent.com/MAGINSTER/Family-Helper/refs/heads/main/version.txt"
        local url_script  = "https://raw.githubusercontent.com/MAGINSTER/Family-Helper/main/FamHelper.lua"

        local r, err = requests.get(url_version)
        if r and r.status_code == 200 then
            local latest = r.text:match("([%d%.]+)")
            if latest and latest ~= CURRENT_VERSION then
                sampAddChatMessage("[FamilyHelper] Доступна новая версия: "..latest.." (у тебя "..CURRENT_VERSION..")", 0xFF6600)
                sampAddChatMessage("[FamilyHelper] Скачиваю обновление...", 0xFF6600)

                local script, err2 = requests.get(url_script)
                if script and script.status_code == 200 then
                    local f = io.open(getGameDirectory().."\\moonloader\\family_helper.lua", "w")
                    f:write(script.text)
                    f:close()
                    sampAddChatMessage("[FamilyHelper] Скрипт обновлён! Перезапусти игру или MoonLoader.", 0x66CCFF)
                else
                    sampAddChatMessage("[FamilyHelper] Ошибка загрузки скрипта: "..tostring(err2), 0xFF0000)
                end
            else
                sampAddChatMessage("[FamilyHelper] У тебя актуальная версия ("..CURRENT_VERSION..")", 0x66CCFF)
            end
        else
            sampAddChatMessage("[FamilyHelper] Ошибка проверки обновлений: "..tostring(err), 0xFF0000)
        end
    end)
end

function main()
    repeat wait(100) until isSampAvailable()
    sampRegisterChatCommand("fh", function()
        window[0] = not window[0]
        imgui.Process = window[0]
    end)
    sampAddChatMessage("[FamilyHelper] Используй /fh для открытия меню", 0x66CCFF)

    -- 🔧 проверка обновлений при запуске
    checkUpdates()

    while true do wait(0) end
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
end)

imgui.OnFrame(
    function() return window[0] end,
    function(this)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(500, 400), imgui.Cond.FirstUseEver)
        imgui.Begin("Family Helper", window, imgui.WindowFlags.NoResize)

        -- Вкладки
        if imgui.Button(u8"Главная", imgui.ImVec2(100,30)) then menu = 1 end
        imgui.SameLine()
        if imgui.Button(u8"Новости", imgui.ImVec2(100,30)) then menu = 2 end
        imgui.SameLine()
        if imgui.Button(u8"Обновления", imgui.ImVec2(100,30)) then menu = 3 end

        imgui.Separator()

        -- Главная
        if menu == 1 then
            imgui.Text(u8"Лидер семьи: Ilya_Fedyaev")
            imgui.Text(u8"Тип семьи: Dynasty")
            imgui.Text(u8"Заместитель 1: Egor_Enotav")
            imgui.Text(u8"Заместитель 2: David_Dias")
            imgui.Text(u8"Заместитель 3: Слот не куплен")

            imgui.Separator()
            imgui.Text(u8"Действия семьи:")

            if imgui.Button(u8"Пригласить игрока (/faminvite)", imgui.ImVec2(-1,30)) then
                sampSetChatInputText("/faminvite ")
                window[0] = false
                imgui.Process = false
            end

            if imgui.Button(u8"Выдать ранг (/frank)", imgui.ImVec2(-1,30)) then
                sampSetChatInputText("/frank ")
                window[0] = false
                imgui.Process = false
            end

            if imgui.Button(u8"Выдать варн (/famwarn)", imgui.ImVec2(-1,30)) then
                sampSetChatInputText("/famwarn ")
                window[0] = false
                imgui.Process = false
            end

            if imgui.Button(u8"Исключить (/famkick)", imgui.ImVec2(-1,30)) then
                sampSetChatInputText("/famkick ")
                window[0] = false
                imgui.Process = false
            end
        end

        -- Новости
        if menu == 2 then
            imgui.Text(u8"Новости семьи:")
            imgui.Separator()
            imgui.Text(u8"Пока новостей нет.")
        end

        -- Обновления
        if menu == 3 then
            imgui.Text(u8"Обновления Family Helper:")
            imgui.Separator()
            imgui.Text(u8"Пока обновлений нет.")
        end

        imgui.End()
    end
)
