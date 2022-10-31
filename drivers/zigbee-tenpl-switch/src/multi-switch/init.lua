-- Zigbee Tuya Switch
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local util = require "util"
local log = require "log"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local remapSwitchTbl = {
  ["one"] = "switch1",
  ["two"] = "switch2",
  ["three"] = "switch3",
  ["one_two"] = "switchA",
  ["one_three"] = "switchB",
  ["two_three"] = "switchC",
  ["all"] = "all",
}

local function get_ep_offset(device)
  return device.fingerprinted_endpoint_id - 1
end

local function get_remap_switch(device)
  log.info("<<---- Moon ---->> multi / remapSwitch")
  local remapSwitch = remapSwitchTbl[device.preferences.remapSwitch]

  if remapSwitch == nil then
    return "switch1"
  else
    return remapSwitch
  end
end

local function send_multi_switch(device, s1, s2, s3, ev, on_off)
  device.profile.components["main"]:emit_event(ev)

  if s1 == true then
    device.profile.components["switch1"]:emit_event(ev)
    device:send_to_component("switch1", on_off)
  end

  if s2 == true then
    device.profile.components["switch2"]:emit_event(ev)
    device:send_to_component("switch2", on_off)
  end

  if s3 == true and get_gang_count(device) >= 3 then
    device.profile.components["switch3"]:emit_event(ev)
    device:send_to_component("switch3", on_off)
  end
end

local on_off_handler = function(driver, device, command)
  log.info("<<---- Moon ---->> multi / on_off_handler - command.component : ", command.component)
  log.info("<<---- Moon ---->> multi / on_off_handler - command.command : ", command.command)
  local capa_on_off = (command.command == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
  local cluster_on_off = (command.command == "off") and zcl_clusters.OnOff.server.commands.Off(device) or zcl_clusters.OnOff.server.commands.On(device)

  -- Due to legacy profile and automation, remapSwitchTbl structure cannot be changed
  if command.component == "main" and get_remap_switch(device) == "all" then
    send_multi_switch(device, true, true, true, capa_on_off, cluster_on_off)
  elseif command.component == "main" and get_remap_switch(device) == "switchA" then
    send_multi_switch(device, true, true, false, capa_on_off, cluster_on_off)
  elseif command.component == "main" and get_remap_switch(device) == "switchB" then
    send_multi_switch(device, true, false, true, capa_on_off, cluster_on_off)
  elseif command.component == "main" and get_remap_switch(device) == "switchC" then
    send_multi_switch(device, false, true, true, capa_on_off, cluster_on_off)
  else
    if command.component == "main" or command.component == get_remap_switch(device) then
      device.profile.components["main"]:emit_event(capa_on_off)
      command.component = get_remap_switch(device)
    end

    -- Note : The logic is the same, but it uses endpoint.
    -- From hub 41.x end_point should be int (Note : Lua don't have int primitive type
    --local endpoint = device:get_endpoint_for_component_id(command.component)
    --endpoint = math.floor(endpoint)
    --device:emit_event_for_endpoint(endpoint, capa_on_off)
    --device:send(cluster_on_off:to_endpoint(endpoint))

    device.profile.components[command.component]:emit_event(capa_on_off)
    device:send_to_component(command.component, cluster_on_off)
  end
end

-- when receive zb_rx from device
local attr_handler = function(driver, device, OnOff, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value
  log.info("<<---- Moon ---->> multi / attr_handler ep :", ep)

  local number = ep - get_ep_offset(device)
  local component_id = string.format("switch%d", number)
  log.info("<<---- Moon ---->> multi / attr_handler :", component_id)

  local clickType = OnOff.value
  local ev = capabilities.switch.switch.off()
  if clickType == true then
    ev = capabilities.switch.switch.on()
  end

  if component_id == get_remap_switch(device) then
    device.profile.components["main"]:emit_event(ev)
  end
  device.profile.components[component_id]:emit_event(ev)
  --device:emit_event_for_endpoint(src_endpoint, ev) -- it cannot be used since endpoint_to_component does not handle main button sync
  syncMainComponent(device)
end

local component_to_endpoint = function(device, component_id)
  log.info("<<---- Moon ---->> multi / component_to_endpoint - component_id : ", component_id)
  local ep = component_id:match("switch(%d)")
  -- From hub 41.x end_point should be int (Note : Lua don't have int primitive type)
  -- Use math.floor or tonumber to remove decimal point
  return math.floor(ep + get_ep_offset(device))
end

-- It will not be called due to received_handler in zigbee_handlers
local endpoint_to_component = function(device, ep)
  log.info("<<---- Moon ---->> multi / endpoint_to_component - endpoint : ", ep)
  local number = ep - get_ep_offset(device)
  return string.format("switch%d", number)
end

function syncMainComponent(device)
  local component_id = get_remap_switch(device)
  log.info("<<---- Moon ---->> multi / syncMainComponent : ", component_id)
  local remapButtonStatus = device:get_latest_state(component_id, "switch", "switch", "off", nil)
  local switch1Status = device:get_latest_state("switch1", "switch", "switch", "off", nil)
  local switch2Status = device:get_latest_state("switch2", "switch", "switch", "off", nil)
  local switch3Status = device:get_latest_state("switch3", "switch", "switch", "off", nil)
  local ev

  -- Preference option name does not allow on/off keyword
  -- on1 is the legacy value due to cache
  -- if on1, off1 이 더이상 로그에서 보여지지 않으면, 코드에서 삭제해도 무방
  log.info("<<---- Moon ---->> multi / mainPriority : ", device.preferences.mainPriority)

  if device.preferences.mainPriority == "anyOn" or device.preferences.mainPriority == "on1"then
    mainPriority = "on"
    ev = capabilities.switch.switch.off()
  else
    mainPriority = "off"
    ev = capabilities.switch.switch.on()
  end

  if component_id == "all" and get_gang_count(device) == 3 then
    if switch1Status == mainPriority or switch2Status == mainPriority or switch3Status == mainPriority then
      ev = (mainPriority == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
    end
  elseif component_id == "all" and get_gang_count(device) == 2 then
    if switch1Status == mainPriority or switch2Status == mainPriority then
      ev = (mainPriority == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
      log.info("<<---- Moon ---->> multi / ev : ", ev)

    end
  elseif component_id == "switchA" then
    if switch1Status == mainPriority or switch2Status == mainPriority then
      ev = (mainPriority == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
    end
  elseif component_id == "switchB" then
    if switch1Status == mainPriority or switch3Status == mainPriority then
      ev = (mainPriority == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
    end
  elseif component_id == "switchC" then
    if switch2Status == mainPriority or switch3Status == mainPriority then
      ev = (mainPriority == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
    end
  else
    ev = (remapButtonStatus == "off") and capabilities.switch.switch.off() or capabilities.switch.switch.on()
  end

  device.profile.components["main"]:emit_event(ev)
end

local device_init = function(self, device)
  log.info("<<---- Moon ---->> multi / device_init")
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component) -- emit_event_for_endpoint

  -- source from : https://github.com/Mariano-Github/Edge-Drivers-Beta/blob/main/zigbee-multi-switch-v3.5/src/init.lua
  -- https://github.com/SmartThingsCommunity/SmartThingsPublic/blob/master/devicetypes/smartthings/zigbee-multi-switch.src/zigbee-multi-switch.groovy#L259
  --- special cofigure for this device, read attribute on-off every 120 sec and not configure reports
  util.check_120sec_issue(device)
end

local device_added = function(driver, device)
  log.info("<<---- Moon ---->> multi / device_added")
  -- Workaround : Should emit or send to enable capabilities UI
  for key, value in pairs(device.profile.components) do
    log.info("<<---- Moon ---->> multi / device_added - key : ", key)
    device.profile.components[key]:emit_event(capabilities.switch.switch.on())
    device:send_to_component(key, zcl_clusters.OnOff.server.commands.On(device))
  end
  device:refresh()
end

local device_driver_switched = function(driver, device, event, args)
  log.info("<<---- Moon ---->> multi / device_driver_switched")
  syncMainComponent(device)
end

function get_gang_count(device)
  return device:component_count() - 1
end

local device_info_changed = function(driver, device, event, args)
  log.info("<<---- Moon ---->> multi / device_info_changed")

  if args.old_st_store.preferences.remapSwitch ~= device.preferences.remapSwitch or
      args.old_st_store.preferences.mainPriority ~= device.preferences.mainPriority then
    syncMainComponent(device)
  end

  if args.old_st_store.preferences.dashBoardStyle ~= device.preferences.dashBoardStyle then
    profileName = 'zigbee-tenpl-switch-' .. tostring(get_gang_count(device))
    if device.preferences.dashBoardStyle == "multi" then
      profileName = profileName .. '-group'
    end
    local success, msg = pcall(device.try_update_metadata, device, { profile = profileName, vendor_provided_label = 'zambobmaz' })
  end
end

local device_doconfigure = function(self, device)
  log.info("<<---- Moon ---->> multi / configure_device")
  device:configure()
end

local is_multi_switch = function(opts, driver, device)
  if get_gang_count(device) >= 2 then
    log.info("<<---- Moon ---->> multi / is_multi_switch : true / device.fingerprinted_endpoint_id :", device.fingerprinted_endpoint_id)
    return true
  else
    log.info("<<---- Moon ---->> multi / is_multi_switch : false")
    return false
  end
end

local multi_switch = {
  NAME = "mutil switch",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_off_handler,
      [capabilities.switch.commands.off.NAME] = on_off_handler,
    },
  },
  zigbee_handlers = {
    attr = {
      [zcl_clusters.OnOff.ID] = {
        [zcl_clusters.OnOff.attributes.OnOff.ID] = attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = device_driver_switched,
    infoChanged = device_info_changed,
    doConfigure = device_doconfigure
  },
  can_handle = is_multi_switch,
}

return multi_switch