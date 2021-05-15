module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  rxjs = require("rxjs")
  operators = require("rxjs/operators")
  connection = require("../node_modules/node-red-contrib-smartnora/build/firebase/connection.js")
  device_context = require("../node_modules/node-red-contrib-smartnora/build/firebase/device-context.js")
  util = require("../node_modules/node-red-contrib-smartnora/build/nodes/util.js")
  _ = require "lodash"

  class LightAdapter extends events.EventEmitter

    constructor: (config, pimaticDevice, smartnoraConfig) ->

      @id = config.pimatic_device_id #pimaticDevice.config.id
      @type = "noraf-light"
      @pimaticDevice = pimaticDevice
      #@subDeviceId = adapterConfig.pimaticSubDeviceId
      #@UpdateState = adapterConfig.updateState

      @state =
        online: true
        on: false
        brightness: 100
      @stateAvailable = @pimaticDevice.hasAction("changeStateTo")    
      @turnOnOffAvailable = @pimaticDevice.hasAction("turnOn") and @pimaticDevice.hasAction("turnOff")

      noraConfig =
        email: smartnoraConfig.email
        password: smartnoraConfig.password
        group: smartnoraConfig.group
        valid: true
        localExecution: false

      env.logger.debug("noraCONFIG:" + JSON.stringify(noraConfig,null,2))

      if !(noraConfig? and noraConfig.valid)
        return

      @close$ = new rxjs.Subject()
      ctx = new device_context.DeviceContext(@)
      ctx.update(@close$)
 
      deviceConfig =
        id: config.pimatic_device_id
        type: "action.devices.types.LIGHT"
        traits: [
          "action.devices.traits.OnOff",
          "action.devices.traits.Brightness"
        ]
        name: {
          name: config.name
        }
        roomHint: config.roomHint
        willReportState: true
        state: 
          on: false
          online: true
          brightness: 100
        attributes: {}
        noraSpecific: 
          turnOnWhenBrightnessChanges: true

      notifyState = (state) =>
        stateString = state.on ? "on" : "off"
        stateString += " #{state.brightness}"
        ctx.state$.next(stateString)


      # setup device stream from smartnora cloud
      #
      @device$ = connection.FirebaseConnection
        .withLogger(env.logger)
        .fromConfig(noraConfig, ctx)
        .pipe(operators.switchMap((connection) => connection.withDevice(deviceConfig, ctx)), util.withLocalExecution(noraConfig), operators.publishReplay(1), operators.refCount(), operators.takeUntil(@close$))

      @device$.pipe(operators.switchMap((d) => d.state$), operators.tap((state) => notifyState(state)), operators.takeUntil(@close$)).subscribe()
      @device$.pipe(operators.switchMap((d) => d.stateUpdates$), operators.takeUntil(@close$)).subscribe((state) => 
        env.logger.debug("received state: " + JSON.stringify(state,null,2))
        if state.brightness isnt @state.brightness
          @pimaticDevice.changeDimlevelTo(state.brightness)
        else if state.on isnt @state.on
          # switch dimmer
          if @stateAvavailable
            @pimaticDevice.changeStateTo(state.on)
            .then ()=>
              @pimaticDevice.changeDimlevelTo(state.brightness)
          else if @turnOnOffAvailable
            if state.on
              @pimaticDevice.turnOn()
              .then ()=>
                @pimaticDevice.changeDimlevelTo(state.brightness)
            else
              @pimaticDevice.turnOff()
          else
            if state.on
              @pimaticDevice.changeDimlevelTo(state.brightness)
            else
              @pimaticDevice.changeDimlevelTo(0)

            
        @state.on = state.on if state.on?
        @state.brightness = state.brightness if state.brightness?
       )

      # setup device handling in Pimatic
      #

      @pimaticDevice.on "state", @pimaticDeviceStateHandler if @stateAvailable
      @pimaticDevice.on "dimlevel", @pimaticDeviceDimlevelHandler
      @pimaticDevice.system = @

    initState: ()=>
      if @stateAvavailable 
        @pimaticDevice.getState()
        .then((state)=>
          @state.on = state
          return @pimaticDevice.getDimlevel()
        )
        .then((dimlevel)=>
          @state.brightness = dimlevel
          @lastBrightness = dimlevel
          @setState(@state)
        )
      else
        @pimaticDevice.getDimlevel()
        .then((dimlevel)=>
          @state.brightness = dimlevel
          @setState(@state)
        )


    status: (status) =>
      env.logger.debug("Light device '#{@id}' status: " + JSON.stringify(status.text,null,2))
      if status.text is "connected"
        @initState()

    pimaticDeviceStateHandler: (state) ->
      # device status changed, updating device status in Nora
      @system.updateState(state)
    pimaticDeviceDimlevelHandler: (dimlevel) ->
      # device status changed, updating device status in Nora
      @system.updateDimlevel(dimlevel)

    updateState: (newState) =>
      unless newState is @state.on
        env.logger.debug "Update state to " + newState
        @state.on = newState
        @setState(@state)

    updateDimlevel: (newDimlevel) =>
      unless newDimlevel is @state.brightness
        env.logger.debug "Update dimlevel to " + newDimlevel
        @state.brightness = newDimlevel
        @setState(@state)

    setState: (newState)=>
      for key,val of newState
        @state[key] = val
      env.logger.debug "Set smartnora state to: " + JSON.stringify(@state)
      try 
        @device$.pipe(operators.first()).toPromise()
        .then (device)=>
          device.updateState(@state)
      catch err
        env.logger.debug("while updating state #{err.message}: #{err.stack}")

    getType: () ->
      return "light"

    getState: () ->
      return @state


    destroy: ->
      return new Promise((resolve,reject) =>
        @pimaticDevice.removeListener "state", @pimaticDeviceStateHandler if @pimaticDeviceStateHandler?
        @pimaticDevice.removeListener "dimlevel", @pimaticDeviceDimlevelHandler if @pimaticDeviceDimlevelHandler?
        @close$.next()
        @close$.complete()
        resolve(@id)
      )
