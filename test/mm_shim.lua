-- mm_shim.lua
-- Emulates the MoneyMoney WebBanking host environment well enough to run the
-- parsing functions of amazon-orders.lua against saved HTML pages offline.
--
-- The real host parses HTML with libxml2 (HTML parser + XPath); we wrap xmlua
-- (a libxml2 binding) to mirror the node-set API the plugin relies on:
--   :xpath(q) :text() :attr(n[,v]) :each(fn) :length() :get(n) :children()
-- Form/navigation methods (:submit/:click/:select) are stubbed because offline
-- tests exercise parsing, not live scraping.

local xmlua = require("xmlua")

local M = {}

----------------------------------------------------------------------
-- NodeSet: array-like (result[1] is the first element) AND method-bearing.
-- Every "element" handed to plugin code is itself a single-node NodeSet, so
-- element:text()/:attr()/:xpath() all work uniformly.
----------------------------------------------------------------------
local NodeSet = {}
NodeSet.__index = NodeSet

local function single(node, doc)
  local o = setmetatable({ _nodes = { node }, _doc = doc }, NodeSet)
  o[1] = o
  return o
end

local function wrap(nodes, doc)
  local o = setmetatable({ _nodes = nodes, _doc = doc }, NodeSet)
  for i, n in ipairs(nodes) do
    o[i] = single(n, doc)
  end
  return o
end

-- libxml2 searches `//x` from the document regardless of context node, and
-- `.//x` / `./x` relative to the context node. We run the query from the first
-- node of the set (matching how the plugin always uses single-node contexts).
function NodeSet:xpath(query)
  local ctx = self._nodes[1]
  if ctx == nil then
    return wrap({}, self._doc)
  end
  local ok, res = pcall(function() return ctx:search(query) end)
  if not ok or res == nil then
    return wrap({}, self._doc)
  end
  local nodes = {}
  for _, n in ipairs(res) do nodes[#nodes + 1] = n end
  return wrap(nodes, self._doc)
end

function NodeSet:text()
  local n = self._nodes[1]
  if n == nil then return "" end
  local ok, t = pcall(function() return n:text() end)
  if not ok or t == nil then return "" end
  return t
end

function NodeSet:attr(name, value)
  local n = self._nodes[1]
  if value ~= nil then
    if n ~= nil and n.set_attribute then
      pcall(function() n:set_attribute(name, value) end)
    end
    return self
  end
  if n == nil then return "" end
  local ok, v = pcall(function() return n:get_attribute(name) end)
  if not ok or v == nil then return "" end
  return v
end

function NodeSet:each(fn)
  for i = 1, #self._nodes do
    local cont = fn(i, self[i])
    if cont == false then break end
  end
  return self
end

function NodeSet:length()
  return #self._nodes
end

function NodeSet:get(n)
  return self[n] or wrap({}, self._doc)
end

-- element children (skip text nodes) — matches how the plugin uses :children()
function NodeSet:children()
  return self:xpath("./*")
end

function NodeSet:html()
  local n = self._nodes[1]
  if n == nil then return "" end
  local ok, h = pcall(function() return n:to_html() end)
  if not ok or h == nil then return "" end
  return h
end

-- navigation stubs: error loudly so a test that hits them is obvious
local function navStub(name)
  return function()
    error("mm_shim: NodeSet:" .. name .. "() called — not supported offline")
  end
end
NodeSet.select = navStub("select")
NodeSet.submit = navStub("submit")
NodeSet.click  = navStub("click")

----------------------------------------------------------------------
-- HTML(content) host function
----------------------------------------------------------------------
function M.HTML(content)
  local doc = xmlua.HTML.parse(content or "")
  local root = doc:root()
  if root == nil then
    return wrap({}, doc)
  end
  return single(root, doc)
end

----------------------------------------------------------------------
-- Sandbox: load amazon-orders.lua with host globals stubbed, return its env
-- so tests can call its global functions (getOrdersFromSummary, etc.).
----------------------------------------------------------------------
function M.loadPlugin(path)
  local env = {}

  local MM = {
    md5 = function(s) return tostring(s) end,
    base64 = function(s) return s end,
    urlencode = function(s) return tostring(s) end,
    toEncoding = function(_, s) return s end,
    printStatus = function() end,
    sleep = function() end,
  }

  local JSONmeta = {}
  JSONmeta.__index = JSONmeta
  function JSONmeta:dictionary() return self._d or {} end
  function JSONmeta:set(d) self._d = d; return self end
  function JSONmeta:json() return "{}" end
  local function JSON(s)
    return setmetatable({ _d = {} }, JSONmeta)
  end

  -- Provide standard library + host stubs; fall back to real _G for the rest.
  local overrides = {
    HTML = M.HTML,
    MM = MM,
    JSON = JSON,
    LocalStorage = nil,             -- nil => top-level cache block is skipped
    Connection = function() error("Connection() not available offline") end,
    WebBanking = function() end,
    ProtocolWebBanking = "ProtocolWebBanking",
    AccountTypeOther = "AccountTypeOther",
    LoginFailed = "LoginFailed",
    io = nil,                       -- nil => behaves like signed build (no fs)
    print = function(...) end,      -- silence plugin's load-time prints
  }
  setmetatable(env, { __index = function(t, k)
    local v = overrides[k]
    if v ~= nil then return v end
    return _G[k]
  end })

  local chunk, err = loadfile(path)
  if not chunk then error("loadfile failed: " .. tostring(err)) end
  setfenv(chunk, env)
  chunk()
  return env
end

M.NodeSet = NodeSet
M.wrap = wrap
return M
