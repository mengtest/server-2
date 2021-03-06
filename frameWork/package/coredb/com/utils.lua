---
--- helper方法类
---
local mylog         = require "base.mylog"
local error         = error
local type          = type
local pairs         = pairs
local next          = next
local setmetatable  = setmetatable
local getmetatable  = getmetatable
local ipairs        = ipairs
local table_concat  = table.concat
local table_insert  = table.insert
local string_char   = string.char
local string_gsub   = string.gsub
local string_format = string.format

local quote_sql_str = function (v)  
    if type(v) == "number" then return v end
    if type(v) == "string" then return string_format("'%s'", v) end
    assert("error v")
end
local ngx_log       = mylog.info
local output        = mylog.info -- debug输出任意变量使用的输出方法

-- table数组去重值唯一，数组下标将自动重排
-- @param mixed data 拟调试输出的变量
-- @return array
local function unique(array)
    -- 类型检查
    if "table" ~= type(array) then
        return {}
    end
    local check = {}
    local result = {}
    for _, v in ipairs(array) do
        if not check[v] then
            table_insert(result,v)
            check[v] = true
        end
    end
    return result
end

-- 调试输出任意变量方法
-- @param mixed data 拟调试输出的变量
-- @param boolean showMetatable 是否要输出table的元组信息
-- [@param mixed lastCount 递归使用标记，调用时不许传参]
local function dump(data, showMetatable, lastCount)
    if type(data) ~= "table" then
        --Value
        if type(data) == "string" then
            output("\"", data, "\"")
        else
            output(tostring(data))
        end
    else
        --Format
        local count = lastCount or 0
        count = count + 1
        output("{\n")
        --Metatable
        if showMetatable then
            for i = 1,count do output("\t") end
            local mt = getmetatable(data)
            output("\"__metatable\" = ")
            dump(mt, showMetatable, count)    -- 如果不想看到元表的元表，可将showMetatable处填nil
            output(",\n")     --如果不想在元表后加逗号，可以删除这里的逗号
        end
        --Key
        for key,value in pairs(data) do
            for i = 1,count do output("\t") end
            if type(key) == "string" then
                output("\"", key, "\" = ")
            elseif type(key) == "number" then
                output("[", key, "] = ")
            else
                output(tostring(key))
            end
            dump(value, showMetatable, count) -- 如果不想看到子table的元表，可将showMetatable处填nil
            output(",\n")     --如果不想在table的每一个item后加逗号，可以删除这里的逗号
        end
        --Format
        for i = 1,lastCount or 0 do output("\t") end
        output("}")
    end
    --Format
    if not lastCount then
        output("\n")
    end
end

-- 检查变量是否为空，nil|空字符串|false|0|零字符串|ngx.null即NULL|空数组 均为认为是空，即返回true
-- @param mixed value
local function empty(value)
    if value == nil or value == '' or value == false or value == 0 or value == '0' then
        return true
    elseif "table" == type(value) then
        return next(value) == nil
    else
        return false
    end
end

-- 抛出异常
-- @param string message
local function exception(message)
    error(message)
end

-- 去除字符串中的所有反引号
-- @param string s 待处理的字符串
-- @return string
local function strip_back_quote(s)
    return string_gsub(s, "%`(.-)", "%1")
end

-- 设置字符串被反引号括起，一般用于处理 表名称、字段名称
-- @param string s 待处理的字符串
-- @return string
local function set_back_quote(s)
    -- 两边拼接反引号
    local s_rep = "`" .. s .. "`"

    -- as语法的处理，as不区分大小写
    local s1 = string_gsub(s_rep, "%s+%a+%s+", "` AS `")

    -- 如果匹配到了as语法的字段
    if not empty(s1) then
        s_rep = s1
    end

    -- 有别名的点(.)字符处理
    local s2 = string_gsub(s_rep, "(%.)", "`.`")
    if empty(s2) then
        return s_rep
    end

    return s2
end

-- 去除字符串两端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function trim(s, char)
    if empty(char) then
        return (string_gsub(s, "^%s*(.-)%s*$", "%1"))
    end
    return (string_gsub(s, "^".. char .."*(.-)".. char .."*$", "%1"))
end

-- 去除字符串左端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function ltrim(s, char)
    if empty(char) then
        return (string_gsub(s, "^%s*(.-)$", "%1"))
    end
    return (string_gsub(s, "^".. char .."*(.-)$", "%1"))
end

-- 去除字符串右端空白
-- @param string s 待处理的字符串
-- @param string char 可选的去除两边的字符类型，不传则去除空白，传则去除指定
local function rtrim(s, char)
    if empty(char) then
        return (string_gsub(s, "^(.-)%s*$", "%1"))
    end
    return (string_gsub(s, "^(.-)".. char .."*$", "%1"))
end

-- 使用1个字符串分割另外一个字符串返回数组
-- @param string delimiter 切割字符串的分隔点
-- @param string string 待处理的字符串
-- @return array
local function explode(delimiter, string)
    local rt= {}
    --
    string_gsub(string, '[^'..delimiter..']+', function(w)
        table_insert(rt, trim(w))
    end)

    return rt
end

-- 使用1个字符串将一个table结构的数组合并成1个字符串
-- @param string separator 数组元素相互连接之间的字符串
-- @param array array 待拼接的数组
-- @return array
local function implode(separator, array)
    return table_concat(array, separator)
end

-- 转移匹配模式特殊字符为其本身的含义表示法
-- @param string str 待escape的字符串
-- @return string
local function escape_pattern(str)
    -- 变量类型检查
    if "string" ~= type(str) then
        return nil
    end

    --local result,_ = string_gsub(str, "[%^%$%(%)%%%.%[%]%*%+%-%?]", function(match)
    local result,_ = string.gsub(str, "[%%]", function(match)
        return "%" .. match
    end)

    return result
end

-- 字符串替换
-- @param string|array search  拟查找替换的字符或多个字符串数组
-- @param string|array replace 查找替换后的字符串或字符串数组
-- @param string       subject 被查找替换的字符串
-- @return string
local function str_replace(search, replace, subject)
    if "string" == type(search) and "string" == type(replace) then

        return string_gsub(subject, search, escape_pattern(replace))
    end

    if "table" == type(search) and "table" == type(replace) and #search == #replace then
        for key,val in pairs(search) do
            subject = str_replace(val, replace[key], subject)
        end

        return subject
    end

    return false
end

-- 深度复制1个table
local function deep_copy(orig)
    local orig_type = type(orig)
    local copy = {}
    if "table" == orig_type then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- 浅度复制一个table
local function cold_copy(orig)
    local copy

    if "table" == type(orig) then
        copy = {}
        for k,v in pairs(orig) do
            copy[k] = v
        end
    else
        copy = orig
    end

    return copy
end

-- 合并两个数组
-- @param array arr1 原始数组
-- @param array arr2 新变量类型数组
-- @return array|false
local function array_merge(arr1, arr2)
    if "table" ~= type(arr1) or "table" ~= type(arr2) then
        return false
    end

    -- 遍历覆盖
    for k, v in pairs(arr2) do
        if v then
            arr1[k] = v
        end
    end

    return arr1
end

-- 获取一个数组的所有key构成的数组
-- @param array array 原始数组
-- @return array|false
local function array_keys(array)
    if "table" == type(array) then
        local result = {}

        for key,_ in pairs(array) do
            table_insert(result, key)
        end

        return result
    end

    return false
end

-- 获取一个数组的所有value构成的数组
-- @param array array 原始数组
-- @return array|false
local function array_values(array)
    if "table" == type(array) then
        local result = {}

        for _,value in pairs(array) do
            table_insert(result, value)
        end

        return result
    end

    return false
end
-- 获取1个数组的长度，支持索引数组和关联数组即对象
-- @param array array 需计数的数组
-- @return number
local function array_count(array)
    if "table" == type(array) then
        local count = 0

        for _,_ in pairs(array) do
            count = count + 1
        end

        return count
    end

    return false
end

-- 检查1个table是否为数组，即数字索引的table
local function table_is_array(t)
    if type(t) ~= "table" then
        return false
    end

    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then
            return false
        end
    end

    return true
end

-- 检查变量是否在数组之中
-- @param string hack 待检查的变量
-- @param array  needle 给定的数组
-- @return bool
local function in_array(hack, needle)
    if "table" ~= type(needle) then
        return false
    end
    for _, v in pairs(needle) do
        if v == hack then
            return true
        end
    end
    return false
end

-- quote转义单双引号
-- @param string value 需要单双引号转义处理的字符串
-- @return string 转义后的字符串
local function quote_value(value)
    if "string" ~= type(value) then
        return value
    end
    return quote_sql_str(value)
end

-- 转移特殊字符，与quote_value方法类似
-- @param string str 需转义的字符
-- @return string
local function escape_string(str)
    -- 变量类型检查
    if "string" ~= type(str) then
        return nil
    end

    local matches = {
        ['\\'] = '\\\\',
        ["\0"] = '\\0',
        ["\n"] = '\\n',
        ["\r"] = '\\r',
        ["'"] = "\\'",
        ['"'] = '\\"',
        ["\x1a"] = '\\Z'
    }

    for i = 0, 255 do
        local c = string_char(i)
        if c:match('[%z\1-\031\128-\255]') and not matches[c] then
            matches[c] = ('\\x%.2X'):format(i)
        end
    end

    return str:gsub('[\\"/%z\1-\031\128-\255]', matches)
end

-- 解析表和表别名、字段和字段别名
-- 分析 xx       形式key成为{'xx', ''}两个元素的数组
-- 分析 xx.yy    形式key成为{'xx', 'yy'}两个元素的数组
-- 分析 xx yy    形式key成为{'xx', 'yy'}两个元素的数组
-- 分析 xx zz yy 形式key成为{'xx', 'yy'}两个元素的数组，一般而言zz均为SQL里的as关键字
-- @param string key
-- @return array，若能分析出两个值则返回两个字符串，否则第二个字符串为空字符
local function parse_key(key)
    -- 去除可能的两端空白 后 将可能的点语法转换成空格，gsub中.为魔术字符，需要%转义
    key = str_replace("%.", " ", trim(key))

    -- 按空格或as语法截取后只处理长度为1、2、3的数组，多个自动忽略
    local _table_array = explode('%s+', key);

    -- 使用了as语法显式设置别名
    if #_table_array >= 3 then
        return { _table_array[1], _table_array[3] }
    end

    -- 使用了空格显式设置别名
    if #_table_array == 2 then
        return { _table_array[1], _table_array[2] }
    end

    -- 未显式设置别名，使用无前缀的表名作为别名
    if #_table_array == 1 then
        return { _table_array[1], "" }
    end
end

-- SQL变量绑定，内部自动处理引号问题
-- @param string sql 问号作为占位符的sql语句或sql构成部分
-- @param array 与sql参数中问号占位符数量相同的变量数组
-- @return string
local function db_bind_value(sql, value)
    -- 检查参数
    if not table_is_array(value) then
        exception("[bind]binds param need be type of index array")
        return sql
    end

    local times = 0
    local result,total = string_gsub(sql, '%?', function(res)
        times = times + 1
        -- quote后返回替换值
        return quote_value(value[times])
    end)

    -- 给定的待绑定的参数数量与sql中的问号变量不一致
    if total ~= #value then
        exception("[bind]bind index array of length not equal placeholder ('?') length")
        return sql
    end

    -- 返回替换后的结果集
    return result
end

-- 返回helper
return {
    exception        = exception,
    explode          = explode,
    implode          = implode,
    escape_pattern   = escape_pattern,
    str_replace      = str_replace,
    strip_back_quote = strip_back_quote,
    set_back_quote   = set_back_quote,
    unique           = unique,
    dump             = dump,
    trim             = trim,
    ltrim            = ltrim,
    rtrim            = rtrim,
    dump             = dump,
    empty            = empty,
    deep_copy        = deep_copy,
    cold_copy        = cold_copy,
    array_merge      = array_merge,
    array_keys       = array_keys,
    array_values     = array_values,
    array_count      = array_count,
    table_is_array   = table_is_array,
    in_array         = in_array,
    quote_value      = quote_value,
    escape_string    = escape_string,
    parse_key        = parse_key,
    db_bind_value    = db_bind_value,
}
