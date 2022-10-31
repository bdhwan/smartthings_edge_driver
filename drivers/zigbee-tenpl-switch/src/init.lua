---- Zigbee Tuya Switch
----
---- Licensed under the Apache License, Version 2.0 (the "License");
---- you may not use this file except in compliance with the License.
---- You may obtain a copy of the License at
----
----     http://www.apache.org/licenses/LICENSE-2.0
----
---- Unless required by applicable law or agreed to in writing, software
---- distributed under the License is distributed on an "AS IS" BASIS,
---- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
---- See the License for the specific language governing permissions and
---- limitations under the License.

local util = require "util"
local log = require "log"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local device_init = function(self, device)
  log.info("<<---- Moon ---->> single / device_init")
  util.check_120sec_issue(device)
end

local zigbee_tuya_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.refresh
  },
  lifecycle_handlers = {
    init = device_init,
  },
  sub_drivers = {
    require("multi-switch")
  }
}

defaults.register_for_default_handlers(zigbee_tuya_switch_driver_template, zigbee_tuya_switch_driver_template.supported_capabilities)
local zigbee_driver = ZigbeeDriver("zigbee-tenpl-switch", zigbee_tuya_switch_driver_template)
zigbee_driver:run()