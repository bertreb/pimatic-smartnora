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

  class ButtonAdapter extends events.EventEmitter

    constructor: (config, pimaticDevice, smartnoraConfig) ->

      @id = config.pimatic_device_id + ":" + config.pimatic_subdevice_id #pimaticDevice.config.id
      @type = "noraf-switch"
      @pimaticDevice = pimaticDevice
      @subDeviceId = config.pimatic_subdevice_id

      noraConfig =
        email: smartnoraConfig.email
        password: smartnoraConfig.password
        group: smartnoraConfig.group
        valid: true
        localExecution: false

      env.logger.debug("noraCONFIG:" + JSON.stringify(noraConfig,null,2))

      @pimaticDevice.system = @

      @pimaticDevice.on "button", @buttonHandler = (buttonId) =>
        #env.logger.debug "Pushed button ButtonId: " + buttonId
        #if buttonId is @subDeviceId
        @updateState(buttonId)

      @state =
        online: true
        on: false

      #if !(noraConfig? and noraConfig.valid)
      #  return

      try
        @close$ = new rxjs.Subject()
        ctx = new device_context.DeviceContext(@)
        ctx.update(@close$)
      catch e
        env.logger.debug "tot hier " + e
       

      deviceConfig =
        id: @id #config.pimatic_device_id
        type: "action.devices.types.SWITCH"
        traits: [
          "action.devices.traits.OnOff"
        ]
        name: {
          name: config.name
        }
        roomHint: config.roomHint ? ""
        willReportState: true
        state: 
          on: false
          online: true
        attributes: {}
        noraSpecific: {}


      notifyState = (state) =>
        stateString = state.on ? 'on' : 'off'
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
        # handle Pimatic action
        #
        if state.on
          @pimaticDevice.buttonPressed(@subDeviceId).then(() =>
            env.logger.debug "Button '" + @subDeviceId + "' pressed"       
          ).catch((err) =>
            env.logger.error "error: " + err.message
          )

      )

      @pimaticDevice.getButton()
      .then((buttonId)=>
        if buttonId is @subDeviceId
          @state.on = true
          @updateState(@buttonId)
      )

    status: (status) =>
      env.logger.debug("Button device '#{@id}' status: " + JSON.stringify(status.text,null,2))

    updateState: (buttonId) =>
      if buttonId is @subDeviceId
        @state.on = true
        env.logger.debug "Switch on " + @id
      else
        @state.on = false
        env.logger.debug "Switch off " + @id
      try 
        @device$.pipe(operators.first()).toPromise()
        .then (device)=>
          device.updateState(@state)
      catch err
        env.logger.debug("while updating state #{err.message}: #{err.stack}")

    getType: () ->
      return "switch"

    getState: () ->
      return @state

    destroy: ->
      return new Promise (resolve,reject) =>
        @state.online = false;
        @updateState(@state)
        @close$.next()
        @close$.complete()
        @pimaticDevice.removeListener "button", @buttonHandler if @buttonHandler?
        resolve(@id)
