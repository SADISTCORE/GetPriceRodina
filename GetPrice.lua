local sampev = require("lib.samp.events")
local jsoncfg = require("jsoncfg")
local encoding = require("encoding")
local dlstatus = require ("moonloader").download_status

-- Конфигурация GitHub
local GITHUB_REPO = "https://raw.githubusercontent.com/SADISTCORE/GetPriceRodina/refs/heads/main/"
local SELL_DATA_URL = GITHUB_REPO .. "sell_prices.json"
local BUY_DATA_URL = GITHUB_REPO .. "buy_prices.json"
local VERSION_URL = GITHUB_REPO .. "version.txt"

-- Флаги обновления
local updateAvailable = false
local dataExpired = false
local updateInProgress = false

-- Конфигурация файлов данных
local SELL_DATA_FILE = "sell_prices"
local BUY_DATA_FILE = "buy_prices"

-- Цвета для чата
local COLORS = {
    header = 0x00FFAA,
    success = 0x00FF00,
    error = 0xFF0000,
    info = 0xADD8E6,
    text = 0xFFFFFF,
    divider = 0x808080
}

-- Дополнительные цвета
COLORS.update = 0xFFA500 -- Оранжевый для устаревших данных
COLORS.warning = 0xFFD700 -- Желтый для предупреждений

-- Таблицы для хранения данных
local sellData = {}
local buyData = {}

-- Загрузка данных с GitHub
local function fetchGitHubData(url, callback)
	local file_path = getWorkingDirectory() .. "/config/" .. url:match("([^/]+%.json)$")
	downloadUrlToFile(url, file_path, function(_, status, _, _)
		if status == dlstatus.STATUS_EXECUTING then
			callback(true, file_path)
		else
			callback(false)
		end
	end)
end

-- Проверка обновлений
local function checkForUpdates()
	if updateInProgress then return end
	updateInProgress = true
	
	-- Загрузка версии
	downloadUrlToFile(VERSION_URL, nil, function(_, status, _, _)
		if status == dlstatus.STATUS_ENDDOWNLOADDATA then 
			local remoteVersion = tonumber(io.readfile(update_path))
			local localVersion = tonumber(io.readfile("version.txt") or 0
			
			if remoteVersion > localVersion then
				updateAvailable = true
				sampAddChatMessage("Доступно обновление цен! Введите /updateprices", COLORS.warning)
			end
		end
		updateInProgress = false
	end)
end

-- Объединение данных
local function mergeData(localData, newData)
	local changes = 0
	for k, v in pairs(newData) do
		if not localData[k] or v.total > localData[k].total then
			localData[k] = v
			changes = changes + 1
		end
	end
	return changes
end

--Команда обновления
local function updatePricesCommand()
	if not updateAvailable then
		sampAddChatMessage("Нет доступных обновлений.", COLORS.info)
		return
	end
	
	sampAddChatMessage("Загрузка обновлений...", COLORS.header)
	
	fetchGitHubData(SELL_DATA_URL, function(success, path)
		if success then
			local newData = jsoncfg.load({}, path:match("([^/]+%.json)$"))
			local changes = mergeData(sellData, newData)
			sampAddChatMessage(string.format("Обновлено %d записей продаж.", changes), COLORS.success)
		end
	end)
	
	fetchGitHubData(BUY_DATA_URL, function(success, path)
		if success then
			local newData = jsoncfg.load({}, path:match("([^/]+%.json)$"))
			local changes = mergeData(buyData, newData)
			sampAddChatMessage(string.format("Обновлено %d записей покупки.", changes), COLORS.success)
			dataExpired = false
			jsoncfg.save(sellData, SELL_DATA_FILE)
			jsoncfg.save(buyData, BUY_DATA_FILE)
		else
			dataExpired = true
			sampAddChatMessage("Ошибка загрузки обновлений!", COLORS.error)
		end
	end)
end

-- Функция форматирования чисел
local function formatNumber(n)
    local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
    return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

-- Функция загрузки данных через jsoncfg
local function loadData()
    -- Проверяем существование файлов перед загрузкой
    if doesFileExist(SELL_DATA_FILE .. ".json") then
        sellData = jsoncfg.load(sellData, SELL_DATA_FILE)
    else
        sellData = sellData or {}
    end
    
    if doesFileExist(BUY_DATA_FILE .. ".json") then
        buyData = jsoncfg.load(buyData, BUY_DATA_FILE)
    else
        buyData = buyData or {}
    end
end

-- Обновление записи для цены
local function updatePrice(dataTable, itemName, price)
    price = tonumber(price)
    if not price or price <= 0 then return false end
    
    if dataTable[itemName] then
        dataTable[itemName].total = dataTable[itemName].total + price
        dataTable[itemName].count = dataTable[itemName].count + 1
    else
        dataTable[itemName] = { total = price, count = 1 }
    end
    return true
end

-- Вспомогательная функция для разбиения строки на аргументы
local function splitArgs(str)
    local args = {}
    for word in str:gmatch("%S+") do
        table.insert(args, word)
    end
    return args
end

-- Вывод сообщения о скрипте
local function printScriptInfo()
    sampAddChatMessage(string.rep("=", 60), COLORS.divider)
    sampAddChatMessage("Price Tracker v2.0", COLORS.header)
    sampAddChatMessage("Автоматический трекер рыночных цен", COLORS.info)
    sampAddChatMessage("Доступные команды:", COLORS.info)
    sampAddChatMessage("/sellprice [название] [цена] - сохранить цену продажи", COLORS.text)
    sampAddChatMessage("/buyprice [название] [цена] - сохранить цену покупки", COLORS.text)
    sampAddChatMessage("/getsell [название] - найти цену продажи", COLORS.text)
    sampAddChatMessage("/getbuy [название] - найти цену покупки", COLORS.text)
    sampAddChatMessage(string.rep("=", 60), COLORS.divider)
	sampAddChatMessage("/updatePrice - проверить обновления цен.", COLORS.text)
	if dataExpired then
		sampAddChatMessage("ВНИМАНИЕ: Данные требуют обновления!", COLORS.warning)
	end
end

-- Регистрация чат-команд
local function registerCommands()
    -- Обработчик для обеих команд
    local function handleCommand(cmd, dataTable, filename, actionName)
        return function(arg)
            local args = splitArgs(arg)
            if #args < 2 then
                sampAddChatMessage("Использование: /"..cmd.." [название] [цена]", COLORS.error)
                return
            end
            
            local price = tonumber(args[#args])
            if not price or price <= 0 then
                sampAddChatMessage("Ошибка: неверное значение цены", COLORS.error)
                return
            end
            
            local itemName = table.concat(args, " ", 1, #args-1)
            if updatePrice(dataTable, itemName, price) then
                jsoncfg.save(dataTable, filename)
                local avg = dataTable[itemName].total / dataTable[itemName].count
                sampAddChatMessage(string.format("%s обновлена: %s (Средняя: $%s)", 
                    actionName, itemName, formatNumber(string.format("%.2f", avg))), COLORS.success)
            end
        end
    end

    -- Команда /sellprice
    sampRegisterChatCommand("sellprice", handleCommand("sellprice", sellData, SELL_DATA_FILE, "Цена продажи"))
    
    -- Команда /buyprice
    sampRegisterChatCommand("buyprice", handleCommand("buyprice", buyData, BUY_DATA_FILE, "Цена покупки"))

	-- Обновлённый обработчик поиска
	local function handleGetCommand(cmd, dataTable, actionName)
		return function(arg)
			if arg == "" then
				sampAddChatMessage("Использование: /"..cmd.." [название]", COLORS.error)
				return
			end
        
			local query = arg:lower():gsub("%%", "%%%%") -- Экранирование %
			local matches = {}
        
			-- Ищем совпадения по шаблону
			for itemName, data in pairs(dataTable) do
				-- Преобразуем в нижний регистр и ищем частичное совпадение
				if itemName:lower():find(query, 1, true) then
					table.insert(matches, {name = itemName, data = data})
				end
			end

			-- Сортировка результатов по алфавиту
			table.sort(matches, function(a, b) return a.name:lower() < b.name:lower() end)
        
			-- Вывод результатов
			if #matches == 0 then
				sampAddChatMessage("Товары по запросу '"..arg.."' не найдены", COLORS.error)
				return
			end
        
			sampAddChatMessage(string.rep("-", 60), COLORS.divider)
			sampAddChatMessage(string.format("Результаты по запросу [%s]: '%s'", actionName, arg), COLORS.header)
        
			for _, match in ipairs(matches) do
				local color = dataExpired and COLORS.update or COLORS.text
				local warning = dataExpired and " {Устарело!}" or ""
			
				sampAddChatMessage(string.format(" %s: $%s (Записей: %d)%s",
					match.name, formattedPrice, match.data.count, warning), color)
			end
		
			if dataExpired then
				sampAddChatMessage("ВНИМАНИЕ: Данные устарели! Используйте /updateprices", COLORS.warning)
			end
		end
	end

    sampRegisterChatCommand("getsell", handleGetCommand("getsell", sellData, "продажа"))
    sampRegisterChatCommand("getbuy", handleGetCommand("getbuy", buyData, "покупка"))
end

-- Основная функция скрипта
function main()
    repeat wait(0) until isSampAvailable()
    
	checkForUpdates()
    loadData()
    registerCommands()
	sampRegisterChatCommand("updateprices", updatePricesCommand)
    printScriptInfo()
	
	-- Проверка обновления каждые 30 минут
	lua_thread.create(function()
		while true do
			wait(1800000)
			checkForUpdates()
		end
	end)
    
    while true do wait(0) end
end

-- Обработчик завершения скрипта
function onScriptTerminate()
    jsoncfg.save(sellData, SELL_DATA_FILE)
    jsoncfg.save(buyData, BUY_DATA_FILE)
    sampAddChatMessage("Price Tracker: Все данные сохранены!", COLORS.success)
end
