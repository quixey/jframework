class J.AutoVar extends Tracker.Computation
    class @COMPUTING extends Error
        constructor: ->
            @name = "J.AutoVar.COMPUTING"
            @message = "Value will be available later in the computation."

    @makeComputingObject: ->
        # The commented-out lines are kinda helpful
        # for debugging but slow as hell.
        # e = Error()
        obj = new @COMPUTING
        obj.isServer = Meteor.isServer
        # obj.stack = e.stack
        obj

    @getFirstActiveAncestor = (comp) ->
        if comp is null
            null
        else if not comp.stopped
            comp
        else if comp instanceof @
            @getFirstActiveAncestor comp.creator
        else
            null


    constructor: (tag, valueFunc, onChange, options) ->
        ###
            AutoVars default to being "lazy", i.e. not calculated
            until .get().

            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoVar becomes non-lazy.

            options:
                creator: Set a different creator computation.
                wrap: Same as Var.wrap
        ###

        unless @ instanceof J.AutoVar
            return new J.AutoVar tag, valueFunc, onChange, options

        if _.isFunction tag
            # Alternate signature: J.AutoVar(valueFunc, onChange, options)
            options = onChange
            onChange = valueFunc
            valueFunc = tag
            tag = undefined

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless not onChange? or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "AutoVar onChange must be either null or a function
                or true (true simply forces non-lazy first evaluation): #{onChange}"

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        @tag = if J.debugTags then tag else null

        @valueFunc = valueFunc
        if Meteor.isServer
            @_func = Meteor.bindEnvironment @_runValueFunc.bind(@)
        else
            @_func = @_runValueFunc.bind(@)

        @onChange = onChange ? null
        if options?.creator is undefined
            @creator = Tracker.currentComputation
        else
            @creator = options.creator
        @wrap = options?.wrap ? true

        @sortKey = 0.3
        @invalidated = false
        @_invalidAncestors = {} # autoVarId: autoVar
        @_onInvalidateCallbacks = []
        @stopped = false

        @creator?.onInvalidate =>
            @stop()

        @_var = null

        if @onChange
            # Truthy onChange means do a non-lazy first run
            # of valueFunc.
            Tracker.afterFlush =>
                if not @_var? then @invalidate()


    _addInvalidAncestor: (autoVar) ->
        @_invalidAncestors[autoVar._id] = autoVar
        for compId, comp of @_var?._getters ? []
            comp._addInvalidAncestor? autoVar


    _removeInvalidAncestor: (autoVar) ->
        delete @_invalidAncestors[autoVar._id]
        for compId, comp of @_var._getters
            comp._removeInvalidAncestor? autoVar


    _runValueFunc: ->
        @_var ?= J.Var J.makeValueNotReadyObject(),
            tag:
                autoVar: @
                tag: "Var for AutoVar[#{@_id}](#{J.util.stringifyTag @tag})"
            creator: @
            onChange: if _.isFunction @onChange then @onChange
            wrap: @wrap

        @onInvalidate =>
            @_invalidAncestors = {}
            if not @stopped
                @_addInvalidAncestor @

        try
            # ValueFunc may either return or throw J.Var.NOT_READY
            # or throw @COMPUTING. It may not return undefined.
            value = @valueFunc.call null, @

        catch e
            if e instanceof J.AutoVar.COMPUTING
                @invalidate()
                return
            else if e instanceof J.VALUE_NOT_READY
                value = e
            else
                throw e

        if value is undefined
            throw new Meteor.Error "#{@toString()}.valueFunc must not return undefined."

        @_removeInvalidAncestor @

        # It's kosher for a valueFunc to call stop() on its own AutoVar.
        if not @stopped
            @_var.set value


    debug: ->
        console.log @toString()


    get: ->
        # console.log "GET", @toString(), @_var?, @currentValueMightChange()

        if arguments.length
            throw new Meteor.Error "Can't pass argument to AutoVar.get"

        if Meteor.isServer and J._inMethod.get()
            # We're just using the Var to wrap the value, e.g.
            # array becomes J.List.
            return J.Var(@valueFunc.call null, @).get()

        if @stopped
            ancestorComp = @constructor.getFirstActiveAncestor @creator
            if ancestorComp
                # There's an active ancestor, so there's a chance
                # that the function trying to get us will succeed
                # next time. That's why we can say we're "computing".
                if Tracker.active
                    throw @constructor.makeComputingObject()
                else
                    return undefined
            else
                console.error()
                throw new Meteor.Error "#{@constructor.name} ##{@_id} is stopped: #{@}."

        if not @_var?
            @_compute()

        if @currentValueMightChange()
            if Tracker.active
                throw J.AutoVar.makeComputingObject()
            else
                return undefined

        @_var.get()


    isActive: ->
        not @stopped


    currentValueMightChange: ->
        # Returns true if @_var.value might change between now
        # and the end of the current flush (or the end of
        # hypothetically calling Tracker.flush() now).
        # Note that true doesn't mean the current value
        # *will* change. It's possible that all invalidated
        # dependency values will recompute themselves to have
        # the same value, and thereby stop @_valueComp from
        # ever invalidating.
        not @_var? or not _.isEmpty @_invalidAncestors


    set: ->
        throw new Meteor.Error "There is no AutoVar.set"


    toString: ->
        s = "AutoVar[#{J.util.stringifyTag @tag ? ''}##{@_id}]=#{J.util.stringify @_var?._value}"
        if not @isActive() then s += " (inactive)"
        s