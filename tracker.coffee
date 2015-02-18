###
    A few things to augment Meteor's Tracker.

    We monkey patch the tracker package because
    we want other Meteor packages like "mongo"
    to use the same global object.
###


dummyComputation = Tracker.autorun ->
if dummyComputation._id isnt 1
    # A computation was already created by one of the packages that jframework
    # uses, which means it may be too late for our monkey patch to work right.
    console.warn "JFramework's attempt to monkey patch Tracker might not work."
dummyComputation.stop()

Tracker.active = false

Tracker.currentComputation = null

setCurrentComputation = (c) ->
    Tracker.currentComputation = c
    Tracker.active = c?

_debugFunc = -> Meteor?._debug ? console?.log ? ->

_throwOrLog = (from, e) ->
    if throwFirstError
        throw e
    else
        if e.stack and e.message
            idx = e.stack.indexOf e.message
            if 0 <= idx <= 10
                # Message is part of e.stack, as in Chrome
                messageAndStack = e.stack
            else
                messageAndStack = e.message +
                    (if e.stack.charAt(0) is '\n' then '' else '\n') +
                    e.stack
        else
            messageAndStack = e.stack or e.message

    _debugFunc() "Exception from Tracker #{from} function:",
        messageAndStack, e

withNoYieldsAllowed = (f) ->
    if not Meteor? or Meteor.isClient then f
    else ->
        args = arguments
        Meteor._noYieldsAllowed -> f.apply null, args

nextId = 1
pendingComputations = []

# true if a Tracker.flush is scheduled, or if we are in Tracker.flush now
willFlush = false

# true if we are in Tracker.flush now
inFlush = false

# true if we are computing a computation now, either first time
# or recompute.  This matches Tracker.active unless we are inside
# Tracker.nonreactive, which nullifies currentComputation even though
# an enclosing computation may still be running.
inCompute = false

# true if the _throwFirstError option was passed in to the call
# to Tracker.flush that we are in. When set, throw rather than log the
# first error encountered while flushing. Before throwing the error,
# finish flushing (from a finally block), logging any subsequent
# errors.
throwFirstError = false

afterFlushCallbacks = []

requireFlush = ->
    if not willFlush
        setTimeout Tracker.flush, 1
        willFlush = true

# Tracker.Computation constructor is visible but private
# (throws an error if you try to call it)
constructingComputation = false;

Tracker.Computation = (f, parent) ->
    if not constructingComputation
        throw new Error "Tracker.Computation constructor is private;
            use Tracker.autorun"

    constructingComputation = false

    @stopped = false
    @invalidated = false

    @firstRun = true

    @_id = nextId++
    @_onInvalidateCallbacks = []

    @_parent = parent
    @_func = f
    @_recomputing = false

    errored = true
    try
        @_compute()
        errored = false
    finally
        @firstRun = false
        if errored then @stop()

Tracker.Computation::onInvalidate = (f) ->
    unless _.isFunction f
        throw new Error "onInvalidate requires a function"

    if Meteor.isServer
        f = Meteor.bindEnvironment f

    if @invalidated
        Tracker.nonreactive ->
            withNoYieldsAllowed(f) @
    else
        @_onInvalidateCallbacks.push f

Tracker.Computation::invalidate = ->
    if not @invalidated
        # If we're currently in _recompute(), don't enqueue
        # ourselves, since we'll rerun immediately anyway
        if not @_recomputing and not @stopped
            requireFlush()
            pendingComputations.push @

        @invalidated = true

        # Callbacks can't add callbacks, because
        # self.invalidated is true
        for f in @_onInvalidateCallbacks
            Tracker.nonreactive -> withNoYieldsAllowed(f) @

        @_onInvalidateCallbacks = []

Tracker.Computation::stop = ->
    if not @stopped
        @stopped = true
        @invalidate()

Tracker.Computation::_compute = ->
    @invalidated = false

    previous = Tracker.currentComputation
    setCurrentComputation @
    previousInCompute = inCompute
    inCompute = true

    try
        withNoYieldsAllowed(@_func) @
    finally
        setCurrentComputation previous
        inCompute = previousInCompute

Tracker.Computation::_recompute = ->
    @_recomputing = true
    try
        while @invalidated and not @stopped
            try
                @_compute()
            catch e
                _throwOrLog "recompute", e
    finally
        @_recomputing = false

Tracker.flush = (_opts) ->
    console.debug "Tracker.flush!"

    if inFlush
        throw new Error "Can't call Tracker.flush while flushing"

    if inCompute
        throw new Error "Can't flush inside Tracker.autorun"

    inFlush = true
    willFlush = true
    throwFirstError = _opts?._throwfirstError ? false

    finishedTry = false
    try
        while pendingComputations.length or afterFlushCallbacks.length
            # Recompute all pending computations
            while pendingComputations.length
                comp = pendingComputations.shift()
                comp._recompute()

            if afterFlushCallbacks.length
                J.util.sortByKey afterFlushCallbacks,
                    (afc) -> afc.sortKey

                # Call one afterFlush callback, which may
                # invalidate more computations
                afc = afterFlushCallbacks.shift()
                try
                    afc.func.call null
                catch e
                    _throwOrLog "afterFlush", e

        finishedTry = true

    finally
        if not finishedTry
            # We're erroring
            inFlush = false # needed before calling Tracker.flush() again
            Tracker.flush _throwFirstError: false # finished flushing
        willFlush = false
        inFlush = false

Tracker.autorun = (f) ->
    if not _.isFunction f
        throw new Error "Tracker.autorun requires a function argument"

    if Meteor.isServer
        f = Meteor.bindEnvironment f

    constructingComputation = true
    c = new Tracker.Computation f, Tracker.currentComputation

    if Tracker.active
        Tracker.onInvalidate -> c.stop()

    c

Tracker.nonreactive = (f) ->
    previous = Tracker.currentComputation
    setCurrentComputation null
    try
        f()
    finally
        setCurrentComputation previous

Tracker.onInvalidate = (f) ->
    if not Tracker.active
        throw new Error "Tracker.onInvalidate requires a currentComputation"

    Tracker.currentComputation.onInvalidate f

Tracker.afterFlush = (f, sortKey = 0.5) ->
    if Meteor.isServer
        f = Meteor.bindEnvironment f

    unless _.isNumber(sortKey) and 0 <= sortKey <= 1
        throw new Error "afterFlush sortKey must be a number between 0 and 1 (lower comes first)"

    afterFlushCallbacks.push func: f, sortKey: sortKey
    requireFlush()



class Tracker.Dependency
    ###
        Like Meteor's Tracker.Dependency except that a "creator",
        i.e. a reactive data source, should be able to freely read
        its own reactive values as it's mutating them without
        invalidating itself.
        But the creator should still invalidate if it reads
        its own values which other objects then mutate.
    ###

    constructor: (@creator = Tracker.currentComputation) ->
        @_dependentsById = {}


    depend: (computation) ->
        if not computation?
            return false if not Tracker.active
            computation = Tracker.currentComputation

        id = computation._id
        if id of @_dependentsById
            false
        else
            @_dependentsById[id] = computation
            computation.onInvalidate =>
                delete @_dependentsById[id]
            true


    changed: ->
        for id, computation of @_dependentsById
            unless computation is Tracker.currentComputation is @creator
                @_dependentsById[id].invalidate()


    hasDependents: ->
        not _.isEmpty @_dependentsById
