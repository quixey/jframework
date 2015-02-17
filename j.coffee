J = {}
J.stores = {}


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