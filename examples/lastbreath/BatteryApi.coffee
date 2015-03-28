BATTERY_EVENT_NAMES = [
    'chargingchange'
    'levelchange'
    'chargingtimechange'
    'dischargingtimechange'
]
J._battery = null

J.getBattery = ->
    comp = Tracker.currentComputation
    if not comp?
        "Must call J.getBattery in a reactive computation"

    if not J._battery?
        navigator.getBattery().then (battery) ->
            J._battery = battery
            comp.invalidate()
        throw J.makeValueNotReadyObject()

    listenerFunc = -> comp.invalidate()
    for eventName in BATTERY_EVENT_NAMES
        J._battery.addEventListener eventName, listenerFunc

    comp.onInvalidate ->
        for eventName in BATTERY_EVENT_NAMES
            J._battery.removeEventListener eventName, listenerFunc

    J._battery