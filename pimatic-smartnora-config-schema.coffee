module.exports = {
  title: "SmartNora"
  type: "object"
  properties:
    email:
      description: "The smartnora email"
      type: "string"
      default: ""
    password:
      description: "The smartnora password"
      type: "string"
      default: ""
    group:
      description: "The smartnora group"
      type: "string"
    home:
      description: "The smartnora home name"
      type: "string"
      default: ""
    localexecution:
      description: "The smartnora local execution"
      type: "boolean"
      default: true
    twofa:
      description: "The global smartnora two factor authorisation. If node is selected, 2FA is set per device"
      type: "string"
      enum: ["node","ack","pin"]
      default: "node"
    twofapin:
      description: "When twofa = pin, the pincode"
      type: "string"
      default: "0000"
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
