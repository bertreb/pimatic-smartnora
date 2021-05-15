module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  rxjs = require("rxjs")
  operators = require("rxjs/operators")
  connection = require("../node_modules/node-red-contrib-smartnora/build/firebase/connection.js")
  #connection = require("../firebase/connection.js")
  device_context = require("../node_modules/node-red-contrib-smartnora/build/firebase/device-context.js")
  #device_context = require("../firebase/device-context.js")
  util = require("../node_modules/node-red-contrib-smartnora/build/nodes/util.js")
  #util = require("./util.js")
  _ = require "lodash"

  class SwitchAdapter extends events.EventEmitter

    constructor: (config, pimaticDevice, smartnoraConfig) ->

      @id = config.pimatic_device_id #pimaticDevice.config.id
      @type = "noraf-switch"
      @pimaticDevice = pimaticDevice

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
        type: "action.devices.types.SWITCH"
        traits: [
          "action.devices.traits.OnOff"
        ]
        name: {
          name: config.name
        }
        roomHint: config.roomHint
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
        @pimaticDevice.changeStateTo(Boolean state.on)
      )

      # setup device handling in Pimatic
      #
      @pimaticDevice.on "state", @pimaticDeviceStateHandler
      @pimaticDevice.system = @
      @state =
        online: true
        on: false

      @pimaticDevice.getState()
      .then((state)=>
        @state.on = state
        @updateState(state)
        env.logger.debug "Initial state: " + state
      )

    status: (status) =>
      env.logger.debug("Switch device '#{@id}' status: " + JSON.stringify(status.text,null,2))

    pimaticDeviceStateHandler: (state) ->
      # device status changed, updating device status in Nora
      @system.updateState(state)

    updateState: (newState) =>
      unless newState is @state.on
        env.logger.debug "Update state to " + newState
        @state.on = Boolean newState
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
        @pimaticDevice.removeListener "state", @pimaticDeviceStateHandler if @pimaticDeviceStateHandler?
        @close$.next()
        @close$.complete()
        resolve(@id)

