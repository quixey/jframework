J = {}
J.stores = {}


J.debugFlush = true
if J.debugFlush
    trackerFlush = Tracker.flush
    Tracker.flush = ->
        console.debug "Tracker.flush!"
        trackerFlush()


J.bindEnvironment = if Meteor.isServer then Meteor.bindEnvironment else _.identity


J.g = J.graph = {} # jid: object
J.debugGraph = true
J._nextId = 0
J.getNextId = ->
    jid = J._nextId
    J._nextId += 1
    jid


if Meteor.isServer
    cslLog = console.log
    console.log = ->
        cslLog.apply console, arguments
    console.debug = ->
        cslLog.apply console, arguments
    console.info = ->
        cslLog.apply console, arguments
    console.warn = ->
        cslLog.apply console, arguments
    console.groupCollapsed = ->
        cslLog.apply console, arguments
    console.groupEnd = ->
        cslLog.apply console, arguments
    console.group = ->
        cslLog.apply console, arguments