J = {}
J.stores = {}

J.counts = {}
J.inc = (countName, num = 1) ->
    J.counts[countName] ?= 0
    J.counts[countName] += num

J.g = J.graph = {} # jid: object
J.debugGraph = Meteor.settings?.public?.jframework?.debug?.graph ? false
J.debugTags = Meteor.settings?.public?.jframework?.debug?.tags ? false
J._nextId = 0
J.getNextId = ->
    jid = J._nextId
    J._nextId += 1
    jid

J.getIds = {}
J.getValueIds = {}
J.forEachIds = {}
J.mapIds = {}

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


J.stats = ->
    for id, x of J.graph
        if x instanceof J.List
            if x._valuesVar?
                J.inc 'compactLists'
                J.inc 'compactListElements', x._valuesVar._value.length
            else
                J.inc 'expandedLists'
                J.inc 'expandedListElements', x._arr.length

    J.counts