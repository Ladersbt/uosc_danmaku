-- 搜索历史模块
-- 功能：记录弹幕搜索关键词（含 |ds/|dy/|dm、@服务器 后缀的原样输入），在搜索框下方的菜单条目中
--       展示历史记录，点击即以该关键词重新搜索；新条目置顶、去重、超限裁剪。
-- 植入点清单（同步上游时需逐一检查保留）：
--   1. main.lua           require("modules/search_history")
--   2. modules/menu.lua   open_input_menu_uosc() 内追加的历史条目块
--   3. modules/menu.lua   search-anime-event 处理器首行的 SearchHistory.record(query)
--   4. modules/options.lua 表尾的 search_history_path / search_history_size 两项

local msg = require('mp.msg')
local utils = require('mp.utils')

SearchHistory = {}

local records = {} -- { { keyword = string, time = number }, ... }，新的在前

-- 解析配置中的历史文件路径；返回 nil 表示功能禁用
local function history_path()
    if not options.search_history_path or options.search_history_path == "" then
        return nil
    end
    return mp.command_native({ "expand-path", options.search_history_path })
end

-- 落盘。遵守仓库写盘纪律：先序列化拿到完整字符串，再开文件写盘，
-- 序列化失败不触碰磁盘（本机 mpv 的 utils.format_json 失败是抛 error 而非按手册返回 nil）
local function save()
    local path = history_path()
    if not path then return end
    local ok, json = pcall(utils.format_json, records)
    if not ok or json == nil then
        msg.warn("搜索历史序列化失败，放弃写盘: " .. path)
        return
    end
    local file = io.open(path, "w")
    if not file then
        msg.warn("搜索历史写盘失败（目录不存在？）: " .. path)
        return
    end
    file:write(json)
    file:close()
end

-- 供菜单渲染的历史列表（只读使用，勿直接修改返回的表）
function SearchHistory.list()
    return records
end

-- 记录一次搜索。query 为用户原样输入（含 |ds/|dy/|dm 与 @服务器 后缀，点击历史条目重放时行为完全一致）
function SearchHistory.record(query)
    local path = history_path()
    if not path or type(query) ~= "string" then return end
    local keyword = query:gsub("^%s+", ""):gsub("%s+$", "")
    if keyword == "" then return end
    -- 去重：重复搜索的词移到最前
    for i, r in ipairs(records) do
        if r.keyword == keyword then
            table.remove(records, i)
            break
        end
    end
    table.insert(records, 1, { keyword = keyword, time = os.time() })
    -- 超限裁剪：search_history_size 小于 1 表示不限制
    local limit = tonumber(options.search_history_size) or 15
    if limit >= 1 then
        while #records > limit do
            table.remove(records)
        end
    end
    save()
end

-- 启动时载入历史；文件缺失或损坏时静默空启动
do
    local path = history_path()
    if path then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            if content and content ~= "" then
                -- utils.parse_json 失败按手册契约返回 nil（非抛错），type 检查即为完整守卫
                local data = utils.parse_json(content)
                if type(data) ~= "table" then
                    msg.warn("搜索历史文件损坏，忽略: " .. path)
                else
                    for _, r in ipairs(data) do
                        if type(r) == "table" and type(r.keyword) == "string" and r.keyword ~= "" then
                            records[#records + 1] = {
                                keyword = r.keyword,
                                time = tonumber(r.time) or 0,
                            }
                        end
                    end
                end
            end
        end
    end
end
