# pimatic-smartnora
Plugin for connecting a Pimatic home automation system to a Google assistant via SmartNora

Background
-------
SmartNora is a Smart **NO**de-**R**ed home **A**utomation solution for connecting Node-red to Google Home/Assistant. SmartNora is build by [Andrei Tatar](https://github.com/andrei-tatar/node-red-contrib-smartnora). SmartNora is a followup of Nora. That free service stopped as a result of its success.

SmartNora consists of a plugin for node-red (node-red-contrib-smartnora) and the SmartNora cloud logic (Firebase) that acts as a gateway between node-red and Google Assistant.

For this plugin I'm not using node-red but refactored the SmartNora node-red plugin to fit Pimatic.
This plugin is a replacement of Pimatic-assistant. That plugin is based on the retired Nora service.

The Pimatic Devices interface with Google Assistant via . Pimatic devices are added in the config. The mapping of states and actions from Pimatic from/to Google Assistant is done as best as possible.

Preparation
---------
Before you can configure the plugin you need to get a Nora service token. The steps are:

- Go to the [SmartNora homepage](https://smart-nora.eu/)
- Create a login with an email address and password.
- When you are logged in, the SmartNora service is created and under 'My NORA' you can see your devices and the user id (not needed for the pimatic plugin)
- The email address and password are user in the device config of the plugin.

Link Nora to your Google Home via the Google Home app (these steps need to happen only once).
The steps are:
- Open your Google Home app and click Add
- In the Add and manage screen, select Set up device
- Select 'Have something already set up?'
- Search and select 'Smart NORA' and login again with the Google/Github account you used when logging in to the NORA homepage.

Done! SmartNora and Google Home are linked and you can install the plugin and add devices in the plugin.
Pimatic devices are not exposed automatically to Smart Nora and Google Assistant. You have to add or remove them individually in the device config.


Installation
------------
To enable the SmartNora plugin add this to the plugins section via the GUI or add it in the config.json file.

```
{
  plugin: "smartnora"
  email:  The email address from smartnora account
  password: The password from smartnora account
  group: name for grouping the devices of this assistant device (default = 'pimatic')
  home: suggested name for the structure (structureHint) where this device is installed.
  Google attempts to use this value during user setup
  localexecution: if checked will enable local execution support for devices that use this configuration
  twofa: ["node", "pin", "ack"] If 'node' is selected twofa can be set per device
  twofapin: number used as pincode when twofa = pin
  debug: Debug mode. Writes debug messages to the pimatic log
}
```

After the plugin is installed a SmartNora device can be added.

SmartNora device
-----------------
The SmartNora device is the main device for adding Pimatic devices to Google SmartNora. When you add/remove a supported Pimatic device to the SmartNora devicelist, the device is automatically added/removed in SmartNora and Google Assistant.

Below the settings with the default values. In the devices your configure which Pimatic devices will be controlled by Google Assistant. The name is visible in the Google Assistant and is the name you use in voice commands.
In this release the SwitchActuator, DimmerActuator and ButtonsDevice based Pimatic devices are supported.
When there's at least 1 device added, the connection to Nora is made. When connected the dot will go to present.

Some specific configurations:
#### Button
For the Buttons device the auxiliary field is used to identify the button. The id of the button can not contain a hyphen ('-'). You can use an underscore to make the id readable.

Device configuration
-----------------

```
{
  id:     "<assistant-device-id>"
  class:  "SmartNoraDevice"
    devices:  "list of devices connected to Google Assistant"
      name:                 "the device name, and command used in Google Assistant"
      roomHint:             "the optional roomname used in Google Assistant"
      pimatic_device_id:    "the ID of the pimatic device"
      pimatic_subdevice_id: "the ID of a pimatic subdevice, only needed for a button id"
      auxiliary:            "adapter specific field to add functionality"
      auxiliary2:            "2nd adapter specific field to add functionality"
      twofa:                 "Two-step confirmation. Google Assistant will ask for confirmation"
                              ["none", "ack", "pin"] default: "none"
      pin:                  "when twofa "pin" is used, the pin string (default: '0000')"
}
```

#### Two-step confirmation (twofa)
2-step confirmation (twofa) is supported. When twofa in the plugin is set to "node", you can enable twofa per device. You can use "ack", the assistant will ask if you are sure you what to execute the action. When you enable "pin", Google Assistant will ask for the pin to confirm the action. You need to enter the pin via the 'keyboard' or spelling the pin as one number (eg 123 => one hundred and twenty three)

#### Deleting an SmartNora device
Before you delete a SmartNora device, please remove first all Pimatic devices in the SmartNora device config and save the config. After that you can delete the SmartNora device.


-----------------

The minimum node requirement for this plugin is node **v10.24.1**. You could backup Pimatic before you are using this plugin!
