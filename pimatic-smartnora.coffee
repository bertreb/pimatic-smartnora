module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  #lightColorAdapter = require('./adapters/lightcolor')(env)
  #sensorAdapter = require('./adapters/sensor')(env)
  buttonAdapter = require('./adapters/button')(env)
  blindAdapter = require('./adapters/blinds')(env)

  _ = require('lodash')
  M = env.matcher
  

  class SmartNoraPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-smartnora-config-schema'
      @configProperties = pluginConfigDef.properties
      
      @smartnoraConfig =
        email: @config.email ? ""
        password: @config.password ? ""
        group: @config.group ? "pimatic"
        homename: @config.home ? ""
        localexecution: @config.localexecution ? false
        twofactor: @config.twofa ? "node"
        twofactorpin: @config.twofapin ? "0000"

      @adapters = {}
        
      deviceConfigDef =  require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('SmartNoraDevice', {
        configDef: deviceConfigDef.SmartNoraDevice,
        createCallback: (config, lastState) => new SmartNoraDevice(config, lastState, @framework, @)
      })

  class SmartNoraDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, plugin) ->
      #@config = config
      @id = @config.id
      @name = @config.name
      @plugin = plugin

      @adapters = @plugin.adapters

      @smartnoraConfig =
        email: @plugin.smartnoraConfig.email 
        password: @plugin.smartnoraConfig.password
        group: @plugin.smartnoraConfig.group
        homename: @plugin.smartnoraConfig.homename
        localexecution: @plugin.smartnoraConfig.localexecution
        twofactorGlobal: @plugin.smartnoraConfig.twofactor ? "node"
        twofactorpinGlobal: @plugin.smartnoraConfig.twofactorpin ? "0000"
        twofactorLocal: "none"
        twofactorpinLocal: "0000"
        noraf: null

      @_presence = lastState?.presence?.value or off

      @devMgr = @framework.deviceManager

      @configDevices = []
      @nrOfDevices = 0

      @framework.variableManager.waitForInit()
      .then ()=>
        @initSmartNora()

      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id or d.pimatic_subdevice_id == device.id)
          #throw new Error "Please remove device also in Assistant"
          env.logger.info "Please remove device also in Smartnora!"

      @framework.on "deviceChanged", (device) =>
        if device.config.class is "ButtonsDevice"
          _device = _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          if _device?
            unless _.find(device.config.buttons, (b)=> b.id == _device.pimatic_subdevice_id)
              #throw new Error "Please remove device also in Assistant"
              env.logger.info "Please remove button also in Smartnora!"

      super()


    initSmartNora: ()=>
      checkMultipleDevices = []
      for _device in @config.devices
        do(_device) =>
          if _.find(checkMultipleDevices, (d) => d.pimatic_device_id is _device.pimatic_device_id and d.pimatic_subdevice_id is _device.pimatic_device_id)?
            env.logger.info "Pimatic device '#{_device.pimatic_device_id}' is already used"
          else
            _fullDevice = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
            if _fullDevice?
              if @selectAdapter(_fullDevice, _device.auxiliary, _device.auxiliary2)?
                if _fullDevice.config.class is "ButtonsDevice"
                  _button = _.find(_fullDevice.config.buttons, (b) => _device.pimatic_subdevice_id == b.id)
                  if _button?
                    checkMultipleDevices.push _device
                    @configDevices.push _device
                  else
                    #throw new Error "Please remove button in Assistant"
                    env.logger.info "Please remove button also in Smartnora!"
                else
                  checkMultipleDevices.push _device
                  @configDevices.push _device
              else
                env.logger.info "Pimatic device class '#{_fullDevice.config.class}' is not supported"                  
            else
              env.logger.info "Pimatic device '#{_device.pimatic_device_id}' does not excist"
              
      @nrOfDevices = _.size(@configDevices)
      if @nrOfDevices > 0 then @_setPresence(on) else @_setPresence(off)
      @syncDevices(@configDevices)


    syncDevices: (configDevices) =>

      for i, adapter of @adapters
        env.logger.debug "Adapter.id " + adapter.id + ", d.name: " + JSON.stringify(configDevices,null,2)
        unless _.find(configDevices, (d)=> d.name is i)
          adapter.destroy()
          .then (id) =>
            env.logger.debug "deleting adapter " + id
            delete @adapters[id]
            env.logger.debug "Remaining adapters: " + (_.keys(@adapters))
        else
          env.logger.debug "Adapter #{adapter.id} already exists"

      addDevicesList = []
      for device in configDevices
        addDevicesList.push device
        env.logger.debug "Smartnora device added: " + device.name

      @addDevices(addDevicesList)
      .then (newDevices) =>
        @devices = newDevices
      .catch (e) =>
        env.logger.debug "error addDevices: " + JSON.stringify(e,null,2)



    addDevices: (configDevices) =>
      return new Promise((resolve,reject) =>

        devices = {}
        for _device, key in configDevices
          pimaticDevice = @devMgr.getDeviceById(_device.pimatic_device_id)
          _newDevice = null
          if pimaticDevice?
            pimaticDeviceId = _device.pimatic_device_id
            env.logger.debug "pimaticDeviceId: " + pimaticDeviceId
            if @plugin.smartnoraConfig.twofactor is "node"
              # set device specific 2FA settings
              @smartnoraConfig.twofactorLocal = _device.twofa ? "none"
              @smartnoraConfig.twofactorpinLocal = _device.twofapin ? "0000"

            #env.logger.debug "Device #{_device.id}, config3: " + JSON.stringify(@smartnoraConfig,null,2)

            try
              selectedAdapter = @selectAdapter(pimaticDevice, _device.auxiliary, _device.auxiliary2)
              switch selectedAdapter
                when "switch"
                  @adapters[pimaticDeviceId] = new switchAdapter(_device, pimaticDevice, @smartnoraConfig)
                when "light"
                  @adapters[pimaticDeviceId] = new lightAdapter(_device, pimaticDevice, @smartnoraConfig)
                when "button"
                  _pimaticDeviceId = pimaticDeviceId + '.' + _device.pimatic_subdevice_id
                  @adapters[_pimaticDeviceId] = new buttonAdapter(_device, pimaticDevice, @smartnoraConfig)
                when "blind"
                  @adapters[pimaticDeviceId] = new blindAdapter(_device, pimaticDevice, @smartnoraConfig)
                else
                  env.logger.debug "Device type #{pimaticDevice.config.class} is not supported!"
            catch e
              env.logger.debug "Error new adapter: " + JSON.stringify(e,null,2)

        resolve(devices)
      )

    selectAdapter: (pimaticDevice, aux1, aux2) =>
      _foundAdapter = null
      ###
      if pimaticDevice.config.class is "MilightRGBWZone" or pimaticDevice.config.class is "MilightFullColorZone"
        _foundAdapter = "lightColorMilight"
      if ((pimaticDevice.config.class).toLowerCase()).indexOf("rgb") >= 0
        _foundAdapter = "lightColor"
      else if ((pimaticDevice.config.class).toLowerCase()).indexOf("ct") >= 0
        _foundAdapter = "lightTemperature"
      else if (pimaticDevice.config.class).indexOf("Dimmer") >= 0
        _foundAdapter = "light"
      else if ((pimaticDevice.config.id).toLowerCase()).indexOf("vacuum") >= 0
        _foundAdapter = "vacuum"
      else if (pimaticDevice.config.class).indexOf("Dimmer") >= 0
        _foundAdapter = "light"
      else if (pimaticDevice.config.name).indexOf("lock") >= 0
        _foundAdapter = "lock"
      if ((pimaticDevice.config.class).toLowerCase()).indexOf("led") >= 0
        _foundAdapter = "lightColor"
      else if (pimaticDevice.config.class).toLowerCase().indexOf("luftdaten") >= 0
        _foundAdapter = "sensor"
        ###
      if (pimaticDevice.config.class).toLowerCase().indexOf("switch") >= 0
        _foundAdapter = "switch"
      else if (pimaticDevice.config.class).toLowerCase().indexOf("dimmer") >= 0
        _foundAdapter = "light"
      else if pimaticDevice instanceof env.devices.ButtonsDevice
        _foundAdapter = "button"
      else if pimaticDevice instanceof env.devices.ShutterController
        _foundAdapter = "blind"
      ###
      else if pimaticDevice instanceof env.devices.DummyHeatingThermostat
        _foundAdapter = "heatingThermostat"
      else if pimaticDevice.config.class is "DummyThermostat"
        _foundAdapter = "dummyThermostat"
      else if pimaticDevice instanceof env.devices.DummyHeatingThermostat
        _foundAdapter = "heatingThermostat"
      else if pimaticDevice.config.class is "DummyThermostat"
        _foundAdapter = "dummyThermostat"
      else if pimaticDevice.hasAttribute(aux1)
        _foundAdapter = "temperature"
      ###

      if _foundAdapter?
        env.logger.debug _foundAdapter + " device found"
      return _foundAdapter

    destroy: =>
      ###
      for i, adapter of @plugin.adapters
        env.logger.debug "Checking adapter " + i
        @plugin.adapters[i].destroy()
        .then (_i)=>
          delete @plugin.adapters[_i]
          env.logger.debug "Adapter '#{_i}' deleted"
      ### 
      super()

  plugin = new SmartNoraPlugin
  return plugin
