module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  childProcess = require("child_process")
  rxjs = require("rxjs")
  operators = require("rxjs/operators")
  connection = require("../node_modules/node-red-contrib-smartnora/build/firebase/connection.js")
  device_context = require("../node_modules/node-red-contrib-smartnora/build/firebase/device-context.js")
  util = require("../node_modules/node-red-contrib-smartnora/build/nodes/util.js")
  _ = require "lodash"


  class ShutterUpDownAdapter extends events.EventEmitter

    constructor: (config, pimaticDevice, smartnoraConfig) ->

      @id = config.pimatic_device_id #pimaticDevice.config.id
      @type = "noraf-blinds"
      @pimaticDevice = pimaticDevice

      @rollerTime = if config.auxiliary is "" then 20000 else (Number config.auxiliary) * 1000
      @position = 0

      noraConfig =
        email: smartnoraConfig.email
        password: smartnoraConfig.password
        group: smartnoraConfig.group
        valid: true
        localExecution: false

      deviceConfig =
        id: config.pimatic_device_id
        type: "action.devices.types.BLINDS"
        traits: [
          "action.devices.traits.OpenClose"
        ]
        name: {
          name: config.name
        }
        roomHint: config.roomHint
        willReportState: true
        state: 
          online: true
          openPercent: 100
        attributes: {}
        noraSpecific: {}

      @close$ = new rxjs.Subject()
      ctx = new device_context.DeviceContext(@)
      ctx.update(@close$)

      notifyState = (state) =>
        stateString = state.openPercent
        ctx.state$.next(stateString)

      # setup device stream from smartnora cloud
      #
      @device$ = connection.FirebaseConnection
        .withLogger(env.logger)
        .fromConfig(noraConfig, ctx)
        .pipe(operators.switchMap((connection) => connection.withDevice(deviceConfig, ctx)), util.withLocalExecution(noraConfig), operators.publishReplay(1), operators.refCount(), operators.takeUntil(@close$))

      @device$.pipe(operators.switchMap((d) => d.state$), operators.tap((state) => notifyState(state)), operators.takeUntil(@close$)).subscribe()
      @device$.pipe(operators.switchMap((d) => d.stateUpdates$), operators.takeUntil(@close$)).subscribe((state) => 
        env.logger.debug("Blinds received state: " + JSON.stringify(state,null,2))
        @changePositionTo(state.openPercent)
      )

      env.logger.debug "Tot hierooooo"

      # setup device handling in Pimatic
      #
      @pimaticDevice.on "position", @devicePositionHandler
      @pimaticDevice.system = @
      @state =
        online: true
        openPercent: 0

    status: (status) =>
      env.logger.debug("Blinds device '#{@id}' status: " + JSON.stringify(status.text,null,2))

    devicePositionHandler: (position) ->
      # device status changed, updating device status in Nora
      # position = ["up","down","stop"]
      switch position
        when "up"
          newPosition = 100
          @system.updatePosition(newPosition)
          @system.postiontimer = setTimeout(()=>
            @system.pimaticDevice.stop()
          , @system.rollerTime)
        when "down"
          newPosition = 0
          @system.updatePosition(newPosition)
          @system.postiontimer = setTimeout(()=>
            @system.pimaticDevice.stop()
          , @system.rollerTime)
        when "stopped"
          env.logger.debug "Stopped received, no further action"
        else
          env.logger.debug "Unknown position command '#{position}' from '#{@system.id}'"

    changePositionTo: (position) =>
      # position is number. actions moveUp, moveDown, stop, rollingtime
      # 
      if position is @position
        return
      if position > @position
        @pimaticDevice.moveUp()
        env.logger.debug "Blinds action: up"
      if position < @position
        @pimaticDevice.moveDown()
        env.logger.debug "Blinds action: down"

      clearTimeout(@positionTimer) if @positionTimer?

      stopShutter = () =>
        @pimaticDevice.stop()
        env.logger.debug "Blinds action: stop"

      @positionTimer = setTimeout(stopShutter, @rollerTime)

    updatePosition: (newPosition) =>
      unless newPosition is @state.openPercent
        env.logger.debug "Update position to " + newPosition
        @state.openPercent = newPosition
        @position = newPosition
        try 
          @device$.pipe(operators.first()).toPromise()
          .then (device)=>
            device.updateState(@state)
        catch err
          env.logger.debug("while updating state #{err.message}: #{err.stack}")

    getType: () ->
      return "blinds"

    getState: () ->
      return @state

    destroy: ->
      return new Promise (resolve,reject) =>
        @state.online = false;
        @updatePosition(@state.openPercent)
        @device.removeListener "position", @devicePositionHandler if @devicePositionHandler?
        clearTimeout(@positionTimer) if @positionTimer?
        @close$.next()
        @close$.complete()
        resolve(@id)

